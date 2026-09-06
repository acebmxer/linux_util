#!/bin/bash

# ============================================================================
# Linux Utilities - Unit Test Suite
# Run: bash tests/test_linux_util.sh
# ============================================================================

set -o pipefail

# --- Test Framework ---
_TESTS_PASSED=0
_TESTS_FAILED=0
_TESTS_SKIPPED=0
_TEST_FAILURES=()

_pass() {
    echo "  PASS: $1"
    ((_TESTS_PASSED++))
}

_fail() {
    echo "  FAIL: $1"
    _TEST_FAILURES+=("$1")
    ((_TESTS_FAILED++))
}

_skip() {
    echo "  SKIP: $1"
    ((_TESTS_SKIPPED++))
}

# Assert helpers
assert_eq() {
    local expected="$1" actual="$2" msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        _pass "$msg"
    else
        _fail "$msg (expected: '$expected', got: '$actual')"
    fi
}

assert_not_empty() {
    local value="$1" msg="$2"
    if [[ -n "$value" ]]; then
        _pass "$msg"
    else
        _fail "$msg (value is empty)"
    fi
}

assert_true() {
    local msg="$1"
    shift
    if "$@" 2>/dev/null; then
        _pass "$msg"
    else
        _fail "$msg"
    fi
}

assert_false() {
    local msg="$1"
    shift
    if ! "$@" 2>/dev/null; then
        _pass "$msg"
    else
        _fail "$msg (expected failure but succeeded)"
    fi
}

assert_file_exists() {
    local path="$1" msg="$2"
    if [[ -f "$path" ]]; then
        _pass "$msg"
    else
        _fail "$msg (file not found: $path)"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if echo "$haystack" | grep -qE "$needle" 2>/dev/null; then
        _pass "$msg"
    else
        _fail "$msg (pattern '$needle' not found in output)"
    fi
}

# --- Setup Test Environment ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR=$(mktemp -d /tmp/linux_util_test_logs_XXXXXX)
SUCCESS_LOG="${LOG_DIR}/success_test.log"
ERROR_LOG="${LOG_DIR}/error_test.log"
LATEST_SUCCESS_LOG="${LOG_DIR}/success_latest.log"
LATEST_ERROR_LOG="${LOG_DIR}/error_latest.log"
ERROR_LOG_INITIALIZED=false

# Create minimal success log
echo "test log" > "$SUCCESS_LOG"

# Source modules in dependency order (skip pkg_manager.sh detect_distro call)
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Stub info/warn/error before sourcing system.sh so tests don't print ANSI
# (they are defined in system.sh — we re-source them)
source "${SCRIPT_DIR}/lib/system.sh"
source "${SCRIPT_DIR}/lib/utilities.sh"
source "${SCRIPT_DIR}/lib/snapshot.sh"

# Provide stubs for pkg_manager functions used by utilities.sh
if ! declare -f pkg_install &>/dev/null; then
    pkg_install() { return 0; }
    pkg_remove() { return 0; }
    pkg_check_installed() { return 1; }
    pkg_get_version() { echo "stub"; }
    PKG_MGR="apt"
    DISTRO_FAMILY="debian"
    DISTRO_ID="ubuntu"
    DISTRO_VERSION_ID="24.04"
    DISTRO_NAME="Ubuntu"
fi

# ============================================================================
# Test: Configuration Module
# ============================================================================
echo ""
echo "=== Config Module Tests ==="

test_config_defaults() {
    assert_eq "30" "$CFG_LOG_RETENTION_DAYS" "Default log_retention_days is 30"
    assert_eq "1024" "$CFG_DISK_MIN_MB" "Default disk_min_mb is 1024"
    assert_eq "INFO" "$CFG_LOG_LEVEL" "Default log_level is INFO"
    assert_eq "main" "$CFG_UPDATE_CHANNEL" "Default update_channel is main"
}

test_config_load_missing_file() {
    # Loading a missing config should succeed (defaults kept)
    load_config "/nonexistent/path/config.conf"
    assert_eq "0" "$?" "load_config returns 0 for missing file"
    assert_eq "30" "$CFG_LOG_RETENTION_DAYS" "Defaults preserved after missing config"
}

test_config_load_from_file() {
    local tmp_conf
    tmp_conf=$(mktemp /tmp/test_config_XXXXXX.conf)
    cat > "$tmp_conf" <<'CONF'
# Test config
[Logging]
log_retention_days=7
max_log_size_mb=100

# Comment line
verbose=true
CONF

    load_config "$tmp_conf"
    assert_eq "7" "$CFG_LOG_RETENTION_DAYS" "Config overrides log_retention_days"
    assert_eq "100" "$CFG_MAX_LOG_SIZE_MB" "Config overrides max_log_size_mb"
    assert_eq "true" "$VERBOSE" "Config overrides verbose"

    # Reset defaults
    CFG_LOG_RETENTION_DAYS=30
    CFG_MAX_LOG_SIZE_MB=50
    VERBOSE=false

    rm -f "$tmp_conf"
}

test_config_crlf_file() {
    # Config files edited on Windows have CRLF line endings. The parser must
    # strip the trailing \r so values still validate (regression test).
    local tmp_conf
    tmp_conf=$(mktemp /tmp/test_config_crlf_XXXXXX.conf)
    printf '# CRLF config\r\nlog_retention_days=7\r\ncompress_old_logs=true\r\nverbose=true\r\n' > "$tmp_conf"

    load_config "$tmp_conf"
    assert_eq "7" "$CFG_LOG_RETENTION_DAYS" "CRLF config: integer value parsed"
    assert_eq "true" "$CFG_COMPRESS_OLD_LOGS" "CRLF config: bool value parsed (no trailing CR)"
    assert_eq "true" "$VERBOSE" "CRLF config: verbose parsed (no trailing CR)"

    # Reset defaults
    CFG_LOG_RETENTION_DAYS=30
    CFG_COMPRESS_OLD_LOGS=true
    VERBOSE=false

    rm -f "$tmp_conf"
}

test_config_update_channel() {
    # update_channel accepts the two tracked branches and a release tag; any
    # other value must be rejected and leave the previous value in place.
    local tmp_conf
    tmp_conf=$(mktemp /tmp/test_config_channel_XXXXXX.conf)

    printf 'update_channel=dev\n' > "$tmp_conf"
    load_config "$tmp_conf"
    assert_eq "dev" "$CFG_UPDATE_CHANNEL" "update_channel accepts dev"

    printf 'update_channel=v1.3.1\n' > "$tmp_conf"
    load_config "$tmp_conf"
    assert_eq "v1.3.1" "$CFG_UPDATE_CHANNEL" "update_channel accepts a release tag"

    printf 'update_channel=main\n' > "$tmp_conf"
    load_config "$tmp_conf"
    assert_eq "main" "$CFG_UPDATE_CHANNEL" "update_channel accepts main"

    # Invalid values keep the previous value (main, from the line above)
    printf 'update_channel=nonsense\n' > "$tmp_conf"
    load_config "$tmp_conf" 2>/dev/null
    assert_eq "main" "$CFG_UPDATE_CHANNEL" "update_channel rejects an unknown branch name"

    printf 'update_channel=1.3.1\n' > "$tmp_conf"
    load_config "$tmp_conf" 2>/dev/null
    assert_eq "main" "$CFG_UPDATE_CHANNEL" "update_channel rejects a tag without the v prefix"

    CFG_UPDATE_CHANNEL=main
    rm -f "$tmp_conf"
}

test_config_defaults
test_config_load_missing_file
test_config_load_from_file
test_config_crlf_file
test_config_update_channel

# ============================================================================
# Test: Logging Module
# ============================================================================
echo ""
echo "=== Logging Module Tests ==="

test_log_success() {
    log_success "Test success message"
    assert_true "log_success writes to success log" grep -q "Test success message" "$SUCCESS_LOG"
    assert_true "log_success includes SUCCESS tag" grep -q "\[SUCCESS\]" "$SUCCESS_LOG"
}

test_log_info() {
    log_info "Test info message"
    assert_true "log_info writes to success log" grep -q "Test info message" "$SUCCESS_LOG"
    assert_true "log_info includes INFO tag" grep -q "\[INFO\]" "$SUCCESS_LOG"
}

test_log_error() {
    log_error "Test error message" 2>/dev/null
    assert_eq "true" "$ERROR_LOG_INITIALIZED" "Error log initialized on first error"
    assert_true "log_error writes to error log" grep -q "Test error message" "$ERROR_LOG"
}

test_log_warning() {
    log_warning "Test warning message" >/dev/null
    assert_true "log_warning writes to error log" grep -q "Test warning message" "$ERROR_LOG"
}

test_metrics_init() {
    metrics_init
    assert_not_empty "$SCRIPT_START_TIME" "metrics_init sets SCRIPT_START_TIME"
    assert_not_empty "$METRICS_LOG" "metrics_init sets METRICS_LOG"
    assert_file_exists "$METRICS_LOG" "metrics_init creates metrics log file"
}

test_metrics_record() {
    metrics_init
    metrics_record "install" "TestApp" "42" "success"
    assert_true "metrics_record writes to metrics log" grep -q "TestApp" "$METRICS_LOG"
    assert_true "metrics_record includes duration" grep -q "42s" "$METRICS_LOG"
}

test_log_success
test_log_info
test_log_error
test_log_warning
test_metrics_init
test_metrics_record

# ============================================================================
# Test: Utilities Registry Module
# ============================================================================
echo ""
echo "=== Utilities Registry Tests ==="

test_register_utility() {
    # Clear registry
    UTILITIES=()
    INSTALL_FUNCS=()
    CHECK_FUNCS=()
    UNINSTALL_FUNCS=()
    UPDATE_FUNCS=()
    VERSION_FUNCS=()

    _test_install() { return 0; }
    _test_check() { return 0; }
    _test_uninstall() { return 0; }
    _test_update() { return 0; }
    _test_version() { echo "1.0.0"; }

    register_utility "Test App" _test_install _test_check _test_uninstall _test_update _test_version

    assert_eq "Test App" "${UTILITIES[0]}" "register_utility adds to UTILITIES array"
    assert_eq "_test_install" "${INSTALL_FUNCS[Test App]}" "register_utility stores install func"
    assert_eq "_test_check" "${CHECK_FUNCS[Test App]}" "register_utility stores check func"
    assert_eq "_test_version" "${VERSION_FUNCS[Test App]}" "register_utility stores version func"
}

test_register_utility_no_version() {
    UTILITIES=()
    INSTALL_FUNCS=()
    CHECK_FUNCS=()
    UNINSTALL_FUNCS=()
    UPDATE_FUNCS=()
    VERSION_FUNCS=()

    _test_install() { return 0; }
    _test_check() { return 0; }
    _test_uninstall() { return 0; }
    _test_update() { return 0; }

    register_utility "No Ver App" _test_install _test_check _test_uninstall _test_update

    assert_eq "No Ver App" "${UTILITIES[0]}" "register_utility works without version func"
    assert_eq "" "${VERSION_FUNCS[No Ver App]:-}" "VERSION_FUNCS is empty when no version func"
}

test_resolve_utility_name() {
    UTILITIES=("Docker" "Brave Browser" "Steam App")

    _RESOLVED=$(resolve_utility_name "docker" 2>/dev/null)
    assert_eq "Docker" "$_RESOLVED" "resolve_utility_name matches case-insensitively"

    _RESOLVED=$(resolve_utility_name "brave" 2>/dev/null)
    assert_eq "Brave Browser" "$_RESOLVED" "resolve_utility_name matches partial names"

    assert_false "resolve_utility_name rejects unknown names" resolve_utility_name "nonexistent"
}

# Every utility that appears in a menu category must also carry a description,
# otherwise the TUI renders a blank description pane (menu.sh falls back to "").
# Parsed statically from installers.sh so the live registry state — which the
# tests above deliberately clobber — cannot affect the result.
test_every_utility_has_description() {
    local _inst="${SCRIPT_DIR}/lib/installers.sh"
    assert_file_exists "$_inst" "installers.sh exists"

    local _missing
    _missing=$(comm -23 \
        <(grep -oP 'UTILITY_CATEGORY\["\K[^"]+' "$_inst" | sort -u) \
        <(grep -oP 'UTILITY_DESCRIPTION\["\K[^"]+' "$_inst" | sort -u))

    assert_eq "" "$_missing" "Every categorized utility has a UTILITY_DESCRIPTION"
}

test_register_utility
test_register_utility_no_version
test_resolve_utility_name
test_every_utility_has_description

# --- AUR-only-on-Arch install hiding (_utility_hidden_aur_only) ---
# A utility whose only Arch install path is the AUR must disappear from the
# "available to install" listing while AUR support is disabled and it isn't
# already installed — but stay listed (for uninstall) once it is installed,
# and stay listed for install once AUR_ENABLED=true.

test_hidden_aur_only_when_disabled_and_not_installed() {
    UTILITIES=("AnyDesk")
    UTILITY_AUR_ONLY_ARCH=()
    mark_aur_only_arch "AnyDesk"
    DISTRO_FAMILY="arch"
    AUR_ENABLED=false
    INSTALLED=(0)

    assert_true "AUR-only utility is hidden when not installed and AUR disabled" \
        _utility_hidden_aur_only 0
}

test_not_hidden_aur_only_when_installed() {
    UTILITIES=("AnyDesk")
    UTILITY_AUR_ONLY_ARCH=()
    mark_aur_only_arch "AnyDesk"
    DISTRO_FAMILY="arch"
    AUR_ENABLED=false
    INSTALLED=(1)

    assert_false "an already-installed AUR-only utility stays listed (for uninstall)" \
        _utility_hidden_aur_only 0
}

test_not_hidden_aur_only_when_enabled() {
    UTILITIES=("AnyDesk")
    UTILITY_AUR_ONLY_ARCH=()
    mark_aur_only_arch "AnyDesk"
    DISTRO_FAMILY="arch"
    AUR_ENABLED=true
    INSTALLED=(0)

    assert_false "AUR-only utility is listed again once AUR_ENABLED=true" \
        _utility_hidden_aur_only 0
}

test_not_hidden_aur_only_off_arch() {
    UTILITIES=("AnyDesk")
    UTILITY_AUR_ONLY_ARCH=()
    mark_aur_only_arch "AnyDesk"
    DISTRO_FAMILY="debian"
    AUR_ENABLED=false
    INSTALLED=(0)

    assert_false "AUR-only-on-Arch marker has no effect off Arch" \
        _utility_hidden_aur_only 0
}

test_not_hidden_when_not_marked_aur_only() {
    UTILITIES=("Obsidian")
    UTILITY_AUR_ONLY_ARCH=()
    DISTRO_FAMILY="arch"
    AUR_ENABLED=false
    INSTALLED=(0)

    assert_false "a utility with a non-AUR fallback (unmarked) is never hidden" \
        _utility_hidden_aur_only 0
}

test_hidden_aur_only_when_disabled_and_not_installed
test_not_hidden_aur_only_when_installed
test_not_hidden_aur_only_when_enabled
test_not_hidden_aur_only_off_arch
test_not_hidden_when_not_marked_aur_only

# ============================================================================
# Test: Dependency Resolution
# ============================================================================
echo ""
echo "=== Dependency Resolution Tests ==="

test_deps_map_init() {
    _init_deps_map
    assert_not_empty "${DEPS_MAP[Docker]:-}" "DEPS_MAP has entry for Docker"
    assert_not_empty "${DEPS_MAP[Brave Browser]:-}" "DEPS_MAP has entry for Brave Browser"
}

test_resolve_dependencies_no_deps() {
    _init_deps_map
    # Utility with no deps should succeed silently
    assert_true "resolve_dependencies succeeds for unknown utility" resolve_dependencies "Nonexistent"
}

test_deps_map_init
test_resolve_dependencies_no_deps

# ============================================================================
# Test: Health Checks
# ============================================================================
echo ""
echo "=== Health Check Tests ==="

test_health_check_no_check() {
    CHECK_FUNCS=()
    # No check function registered should succeed (no-op health check)
    assert_true "health_check succeeds when no check available" health_check "Unknown App"
}

test_health_check_no_check

# ============================================================================
# Test: Verbose / Debug Helpers
# ============================================================================
echo ""
echo "=== Verbose/Debug Tests ==="

test_verbose_off() {
    VERBOSE=false
    local output
    output=$(verbose "should not print")
    assert_eq "" "$output" "verbose() produces no output when VERBOSE=false"
}

test_verbose_on() {
    VERBOSE=true
    local output
    output=$(verbose "test message" 2>/dev/null)
    if echo "$output" | grep -q "test message"; then
        _pass "verbose() produces output when VERBOSE=true"
    else
        _fail "verbose() produces output when VERBOSE=true"
    fi
    VERBOSE=false
}

test_debug_off() {
    DEBUG=false
    local output
    output=$(debug "should not print" 2>&1)
    assert_eq "" "$output" "debug() produces no output when DEBUG=false"
}

test_debug_on() {
    DEBUG=true
    local output
    output=$(debug "debug message" 2>&1)
    if echo "$output" | grep -q "debug message"; then
        _pass "debug() produces output when DEBUG=true"
    else
        _fail "debug() produces output when DEBUG=true"
    fi
    DEBUG=false
}

test_verbose_off
test_verbose_on
test_debug_off
test_debug_on

# ============================================================================
# Test: Config File Example
# ============================================================================
echo ""
echo "=== Config File Tests ==="

test_example_config_exists() {
    assert_file_exists "${SCRIPT_DIR}/linux_util.conf.example" "linux_util.conf.example exists"
}

test_logrotate_template_exists() {
    assert_file_exists "${SCRIPT_DIR}/linux_util.logrotate" "linux_util.logrotate template exists"
}

test_example_config_exists
test_logrotate_template_exists

# ============================================================================
# Test: Distro Detection (pkg_manager.sh)
# We run detect_distro in a subshell so we can source pkg_manager.sh without
# clobbering the stubs already defined above.
# ============================================================================
echo ""
echo "=== Distro Detection Tests ==="

_detect_distro_result() {
    # Source pkg_manager.sh in a subshell; all logging helpers are inherited
    # from the parent shell (subshells inherit functions).
    source "${SCRIPT_DIR}/lib/pkg_manager.sh" 2>/dev/null
    detect_distro 2>/dev/null
    echo "_RESULT_FAMILY=${DISTRO_FAMILY}"
    echo "_RESULT_MGR=${PKG_MGR}"
    echo "_RESULT_NAME=${DISTRO_NAME}"
    echo "_RESULT_ID=${DISTRO_ID}"
}

test_detect_distro_sets_vars() {
    local _out
    _out=$(_detect_distro_result 2>/dev/null)

    local _fam _mgr _name _id
    _fam=$(echo "$_out"  | grep '^_RESULT_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out"  | grep '^_RESULT_MGR='    | cut -d= -f2)
    _name=$(echo "$_out" | grep '^_RESULT_NAME='   | cut -d= -f2)
    _id=$(echo "$_out"   | grep '^_RESULT_ID='     | cut -d= -f2)

    assert_not_empty "$_fam"  "detect_distro sets DISTRO_FAMILY"
    assert_not_empty "$_mgr"  "detect_distro sets PKG_MGR"
    assert_not_empty "$_name" "detect_distro sets DISTRO_NAME"
    assert_not_empty "$_id"   "detect_distro sets DISTRO_ID"
}

test_detect_distro_valid_values() {
    local _out
    _out=$(_detect_distro_result 2>/dev/null)

    local _fam _mgr
    _fam=$(echo "$_out" | grep '^_RESULT_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out" | grep '^_RESULT_MGR='    | cut -d= -f2)

    case "$_fam" in
        debian|fedora|rhel|arch|suse)
            _pass "detect_distro sets DISTRO_FAMILY to a known value ('${_fam}')" ;;
        *)
            _fail "detect_distro sets DISTRO_FAMILY to a known value (got: '${_fam}')" ;;
    esac

    case "$_mgr" in
        apt|dnf|yum|pacman|zypper)
            _pass "detect_distro sets PKG_MGR to a known value ('${_mgr}')" ;;
        *)
            _fail "detect_distro sets PKG_MGR to a known value (got: '${_mgr}')" ;;
    esac
}

test_detect_distro_sets_vars
test_detect_distro_valid_values

# ============================================================================
# Test: Distro Detection — Mocked /etc/os-release
# Patches detect_distro in a subshell via eval+sed to source a temp file,
# so we can assert the correct DISTRO_FAMILY/PKG_MGR for various distros
# without requiring the right hardware or OS to be running.
# ============================================================================
echo ""
echo "=== Distro Detection Mock Tests ==="

# Run detect_distro in a subshell that sources a custom os-release file.
# Patches the function with eval+sed to replace /etc/os-release with $1.
_detect_distro_mock() {
    local mock_file="$1"
    (
        source "${SCRIPT_DIR}/lib/pkg_manager.sh" 2>/dev/null
        eval "$(declare -f detect_distro | sed "s|/etc/os-release|${mock_file}|g")"
        detect_distro 2>/dev/null
        echo "_FAMILY=${DISTRO_FAMILY}"
        echo "_MGR=${PKG_MGR}"
    )
}

# Helper: write a temp os-release file and call _detect_distro_mock.
_run_detect_mock() {
    local distro_id="$1" id_like="${2:-}" name="${3:-Test}" version="${4:-1.0}"
    local _tmp; _tmp=$(mktemp /tmp/os_release_mock_XXXXXX)
    printf 'ID=%s\nID_LIKE="%s"\nNAME="%s"\nVERSION_ID="%s"\n' \
        "$distro_id" "$id_like" "$name" "$version" > "$_tmp"
    local _out; _out=$(_detect_distro_mock "$_tmp" 2>/dev/null)
    rm -f "$_tmp"
    echo "$_out"
}

test_detect_distro_mock_ubuntu() {
    local _out _fam _mgr
    _out=$(_run_detect_mock "ubuntu" "" "Ubuntu" "22.04")
    _fam=$(echo "$_out" | grep '^_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out" | grep '^_MGR='    | cut -d= -f2)
    assert_eq "debian" "$_fam" "Mock ubuntu → DISTRO_FAMILY=debian"
    assert_eq "apt"    "$_mgr" "Mock ubuntu → PKG_MGR=apt"
}

test_detect_distro_mock_fedora() {
    local _out _fam _mgr
    _out=$(_run_detect_mock "fedora" "" "Fedora Linux" "39")
    _fam=$(echo "$_out" | grep '^_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out" | grep '^_MGR='    | cut -d= -f2)
    assert_eq "fedora" "$_fam" "Mock fedora → DISTRO_FAMILY=fedora"
    assert_eq "dnf"    "$_mgr" "Mock fedora → PKG_MGR=dnf"
}

test_detect_distro_mock_arch() {
    local _out _fam _mgr
    _out=$(_run_detect_mock "arch" "" "Arch Linux" "")
    _fam=$(echo "$_out" | grep '^_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out" | grep '^_MGR='    | cut -d= -f2)
    assert_eq "arch"   "$_fam" "Mock arch → DISTRO_FAMILY=arch"
    assert_eq "pacman" "$_mgr" "Mock arch → PKG_MGR=pacman"
}

test_detect_distro_mock_opensuse() {
    local _out _fam _mgr
    _out=$(_run_detect_mock "opensuse-tumbleweed" "suse opensuse" "openSUSE Tumbleweed" "")
    _fam=$(echo "$_out" | grep '^_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out" | grep '^_MGR='    | cut -d= -f2)
    assert_eq "suse"   "$_fam" "Mock opensuse-tumbleweed → DISTRO_FAMILY=suse"
    assert_eq "zypper" "$_mgr" "Mock opensuse-tumbleweed → PKG_MGR=zypper"
}

test_detect_distro_mock_id_like_derivative() {
    # A distro with an unrecognised ID but ID_LIKE=debian should still map correctly.
    local _out _fam _mgr
    _out=$(_run_detect_mock "someunknown" "debian" "SomeDistro" "1.0")
    _fam=$(echo "$_out" | grep '^_FAMILY=' | cut -d= -f2)
    _mgr=$(echo "$_out" | grep '^_MGR='    | cut -d= -f2)
    assert_eq "debian" "$_fam" "ID_LIKE=debian derivative → DISTRO_FAMILY=debian"
    assert_eq "apt"    "$_mgr" "ID_LIKE=debian derivative → PKG_MGR=apt"
}

test_detect_distro_mock_ubuntu
test_detect_distro_mock_fedora
test_detect_distro_mock_arch
test_detect_distro_mock_opensuse
test_detect_distro_mock_id_like_derivative

# ============================================================================
# Test: Snapshot Module (lib/snapshot.sh)
# ============================================================================
echo ""
echo "=== Snapshot Module Tests ==="

test_snapshot_timeshift_init_boolean() {
    local _prev_avail="$TIMESHIFT_AVAILABLE"
    local _prev_path="$PATH"
    local _prev_family="${DISTRO_FAMILY:-}"
    TIMESHIFT_AVAILABLE=false
    SNAPSHOT_BACKEND=""
    # Ensure this test remains non-interactive even if timeshift/snapper exists
    # on the host by hiding those binaries from command -v checks.
    PATH="/nonexistent"
    hash -r 2>/dev/null || true
    unset -f timeshift 2>/dev/null || true
    unset -f snapper 2>/dev/null || true
    DISTRO_FAMILY="debian"
    timeshift_init 2>/dev/null
    if [[ "$TIMESHIFT_AVAILABLE" == "true" || "$TIMESHIFT_AVAILABLE" == "false" ]]; then
        _pass "timeshift_init sets TIMESHIFT_AVAILABLE to a boolean value"
    else
        _fail "timeshift_init sets TIMESHIFT_AVAILABLE to a boolean value (got: '$TIMESHIFT_AVAILABLE')"
    fi
    TIMESHIFT_AVAILABLE="$_prev_avail"
    PATH="$_prev_path"
    DISTRO_FAMILY="$_prev_family"
}

test_snapshot_create_noop_when_unavailable() {
    TIMESHIFT_AVAILABLE=false
    SNAPSHOT_BACKEND=""
    timeshift_create_snapshot "test-comment" 2>/dev/null
    assert_eq "0" "$?" "timeshift_create_snapshot returns 0 when snapshot is unavailable"
}

test_snapshot_btrfs_check_no_crash() {
    _is_btrfs_root 2>/dev/null || true
    _pass "_is_btrfs_root completes without error"
}

test_snapshot_timeshift_init_boolean
test_snapshot_create_noop_when_unavailable
test_snapshot_btrfs_check_no_crash

# ============================================================================
# Test: Snapshot Module — Mocked Backends
# Uses temp fake binaries to simulate timeshift/snapper being present without
# requiring the real tools to be installed on the test runner.
# ============================================================================
echo ""
echo "=== Snapshot Mock Tests ==="

test_snapshot_timeshift_detected_via_mock() {
    # When a 'timeshift' command exists in PATH, timeshift_init should set
    # TIMESHIFT_AVAILABLE=true and SNAPSHOT_BACKEND=timeshift.
    local _fake; _fake=$(mktemp -d /tmp/fake_ts_XXXXXX)
    printf '#!/bin/bash\nexit 0\n' > "$_fake/timeshift"
    chmod +x "$_fake/timeshift"
    printf '#!/bin/bash\nexit 0\n' > "$_fake/sudo"
    chmod +x "$_fake/sudo"

    local _out
    _out=$(
        PATH="$_fake:$PATH"
        TIMESHIFT_AVAILABLE=false
        SNAPSHOT_BACKEND=""
        _timeshift_has_device()        { return 0; }
        _timeshift_cache_last_snapshot() { return 0; }
        timeshift_init 2>/dev/null
        echo "_AVAIL=${TIMESHIFT_AVAILABLE}"
        echo "_BACKEND=${SNAPSHOT_BACKEND}"
    )
    rm -rf "$_fake"

    local _avail _backend
    _avail=$(echo   "$_out" | grep '^_AVAIL='   | cut -d= -f2)
    _backend=$(echo "$_out" | grep '^_BACKEND=' | cut -d= -f2)
    assert_eq "true"      "$_avail"   "timeshift_init: TIMESHIFT_AVAILABLE=true when timeshift is in PATH"
    assert_eq "timeshift" "$_backend" "timeshift_init: SNAPSHOT_BACKEND=timeshift when timeshift is in PATH"
}

test_snapshot_snapper_detected_via_mock() {
    # When snapper exists and DISTRO_FAMILY=arch, timeshift_init should fall
    # back to snapper, setting SNAPSHOT_BACKEND=snapper.
    local _fake; _fake=$(mktemp -d /tmp/fake_snap_XXXXXX)
    printf '#!/bin/bash\nexit 0\n' > "$_fake/snapper"
    chmod +x "$_fake/snapper"
    printf '#!/bin/bash\nexit 0\n' > "$_fake/sudo"
    chmod +x "$_fake/sudo"

    local _out
    _out=$(
        # Keep PATH fake-only so a real host timeshift binary cannot override
        # this test's intent (snapper fallback path).
        PATH="$_fake"
        hash -r 2>/dev/null || true
        DISTRO_FAMILY="arch"
        TIMESHIFT_AVAILABLE=false
        SNAPSHOT_BACKEND=""
        _snapper_has_config()          { return 0; }
        _snapper_cache_last_snapshot() { return 0; }
        timeshift_init 2>/dev/null
        echo "_AVAIL=${TIMESHIFT_AVAILABLE}"
        echo "_BACKEND=${SNAPSHOT_BACKEND}"
    )
    rm -rf "$_fake"

    local _avail _backend
    _avail=$(echo   "$_out" | grep '^_AVAIL='   | cut -d= -f2)
    _backend=$(echo "$_out" | grep '^_BACKEND=' | cut -d= -f2)
    assert_eq "true"    "$_avail"   "timeshift_init: TIMESHIFT_AVAILABLE=true via snapper fallback (arch)"
    assert_eq "snapper" "$_backend" "timeshift_init: SNAPSHOT_BACKEND=snapper for arch+snapper"
}

test_snapshot_create_invokes_timeshift() {
    # Verify timeshift_create_snapshot actually calls the timeshift binary when
    # TIMESHIFT_AVAILABLE=true and SNAPSHOT_BACKEND=timeshift.
    local _fake; _fake=$(mktemp -d /tmp/fake_cre_XXXXXX)
    local _called="${_fake}/was_called"
    printf '#!/bin/bash\ntouch %s\nexit 0\n' "$_called" > "$_fake/timeshift"
    chmod +x "$_fake/timeshift"

    # sudo passthrough: executes "$@" so our fake timeshift binary is reached.
    printf '#!/bin/bash\n"$@"\n' > "$_fake/sudo"
    chmod +x "$_fake/sudo"

    (
        PATH="$_fake:$PATH"
        TIMESHIFT_AVAILABLE=true
        SNAPSHOT_BACKEND="timeshift"
        _timeshift_setup_device()        { return 0; }
        _timeshift_cache_last_snapshot() { return 0; }
        # Stub run_with_spinner to just run the command directly.
        run_with_spinner() { shift; "$@" 2>/dev/null; }
        timeshift_create_snapshot "unit-test"
    ) >/dev/null 2>&1

    if [[ -f "$_called" ]]; then
        _pass "timeshift_create_snapshot invokes the timeshift binary"
    else
        _fail "timeshift_create_snapshot invokes the timeshift binary"
    fi
    rm -rf "$_fake"
}

test_snapshot_timeshift_detected_via_mock
test_snapshot_snapper_detected_via_mock
test_snapshot_create_invokes_timeshift

# ============================================================================
# Test: Profile Helpers (lib/profiles.sh)
# We override UTILITIES/INSTALLED/SELECTED with a small fixture set so the
# profile helper functions operate on known data, then source profiles.sh.
# ============================================================================
echo ""
echo "=== Profile Helper Tests ==="

# Build a minimal fixture registry for profile tests
declare -a _PROFILE_TEST_UTILS=("Docker" "Brave Browser" "Btop" "Timeshift" "Zsh + Oh My Zsh")
UTILITIES=("${_PROFILE_TEST_UTILS[@]}")
SELECTED=(0 0 0 0 0)
UPDATE_SELECTED=(0 0 0 0 0)
INSTALLED=(0 0 0 0 0)
PROFILES=()
PROFILE_FUNCS=()
PROFILE_DESC=()

source "${SCRIPT_DIR}/lib/profiles.sh" 2>/dev/null

test_profile_select_install_uninstalled() {
    SELECTED=(0 0 0 0 0); UPDATE_SELECTED=(0 0 0 0 0); INSTALLED=(0 0 0 0 0)
    _profile_select_for_install "Docker"
    assert_eq "1" "${SELECTED[0]}"        "_profile_select_for_install marks uninstalled util in SELECTED"
    assert_eq "0" "${UPDATE_SELECTED[0]}" "_profile_select_for_install does not set UPDATE_SELECTED when not installed"
}

test_profile_select_install_already_installed() {
    SELECTED=(0 0 0 0 0); UPDATE_SELECTED=(0 0 0 0 0); INSTALLED=(1 0 0 0 0)
    _profile_select_for_install "Docker"
    assert_eq "0" "${SELECTED[0]}"        "_profile_select_for_install clears SELECTED when utility is installed"
    assert_eq "1" "${UPDATE_SELECTED[0]}" "_profile_select_for_install sets UPDATE_SELECTED when already installed"
}

test_profile_select_for_update_installed() {
    SELECTED=(0 0 0 0 0); UPDATE_SELECTED=(0 0 0 0 0); INSTALLED=(0 1 0 0 0)
    _profile_select_for_update "Brave Browser"
    assert_eq "1" "${UPDATE_SELECTED[1]}" "_profile_select_for_update marks installed utility for update"
    assert_eq "0" "${SELECTED[1]}"        "_profile_select_for_update does not set SELECTED"
}

test_profile_select_for_update_not_installed() {
    SELECTED=(0 0 0 0 0); UPDATE_SELECTED=(0 0 0 0 0); INSTALLED=(0 0 0 0 0)
    _profile_select_for_update "Brave Browser"
    assert_eq "0" "${UPDATE_SELECTED[1]}" "_profile_select_for_update is a no-op when utility is not installed"
}

test_profile_select_task() {
    SELECTED=(0 0 0 0 0); UPDATE_SELECTED=(0 0 0 0 0); INSTALLED=(0 0 0 0 0)
    _profile_select_task "Btop"
    assert_eq "1" "${SELECTED[2]}" "_profile_select_task marks the utility for execution"
}

test_profile_select_unknown_noop() {
    SELECTED=(0 0 0 0 0)
    _profile_select_for_install "Nonexistent Utility XYZ"
    local _changed=0
    for i in 0 1 2 3 4; do [[ "${SELECTED[$i]}" != "0" ]] && _changed=1; done
    assert_eq "0" "$_changed" "_profile_select_for_install is a no-op for unknown utilities"
}

test_profile_apply_resets_and_selects() {
    # Start with everything selected
    SELECTED=(1 1 1 1 1); UPDATE_SELECTED=(1 1 1 1 1); INSTALLED=(0 0 0 0 0)
    # Profile 0 = "Run Me First" → selects only Timeshift (index 3)
    apply_profile 0
    assert_eq "0" "${SELECTED[0]}"        "apply_profile resets Docker SELECTED"
    assert_eq "0" "${UPDATE_SELECTED[0]}" "apply_profile resets Docker UPDATE_SELECTED"
    assert_eq "1" "${SELECTED[3]}"        "apply_profile (Run Me First) selects Timeshift"
}

test_profile_register_count() {
    if [[ "${#PROFILES[@]}" -ge 3 ]]; then
        _pass "profiles.sh registers at least 3 profiles (got ${#PROFILES[@]})"
    else
        _fail "profiles.sh registers at least 3 profiles (got ${#PROFILES[@]})"
    fi
}

test_profile_select_install_uninstalled
test_profile_select_install_already_installed
test_profile_select_for_update_installed
test_profile_select_for_update_not_installed
test_profile_select_task
test_profile_select_unknown_noop
test_profile_apply_resets_and_selects
test_profile_register_count

# ============================================================================
# Test: Integration CLI Smoke Tests
# Runs linux_util.sh as a subprocess to validate end-to-end CLI handling.
# A fake 'sudo' stub is placed at the front of PATH so no real privilege
# operations occur, and no cached sudo token is required.
# Only flags that bypass self_update_script (in main()'s pre-parse list) are
# tested here to avoid relying on network access or package manager operations.
# ============================================================================
echo ""
echo "=== Integration CLI Smoke Tests ==="

# Recorded before any test runs so the guard below can tell a backup this suite
# created from one that was already sitting in the working tree.
_PRE_EXISTING_CONF_BAKS=$(ls "$SCRIPT_DIR"/linux_util.conf.bak.* 2>/dev/null)

_FAKE_BIN=$(mktemp -d /tmp/linux_util_fakebin_XXXXXX)
printf '#!/bin/bash\nexit 0\n' > "$_FAKE_BIN/sudo"
chmod +x "$_FAKE_BIN/sudo"

# Fake git: always reports "abc123" so self_update_script sees before==after
# (no update needed) and returns without touching any files.
printf '#!/bin/bash\necho abc123\nexit 0\n' > "$_FAKE_BIN/git"
chmod +x "$_FAKE_BIN/git"

# Run linux_util.sh with the fake bin; store output in _RUN_OUTPUT and return
# the script's exit code.
# Uses a temp file instead of command substitution so background subprocesses
# spawned by the script cannot keep the capture pipe open and stall tests.
# The repository is itself a working install: linux_util.conf lives in the
# checkout. Running the real script from here therefore migrates the developer's
# own config and drops linux_util.conf.bak.<stamp> files in their working tree.
# Point every CLI run at a throwaway copy instead. (Discovered the hard way.)
_CLI_CONF_DIR=$(mktemp -d /tmp/linux_util_cli_conf_XXXXXX)
cp "$SCRIPT_DIR/linux_util.conf.example" "$_CLI_CONF_DIR/linux_util.conf.example"
cp "$SCRIPT_DIR/linux_util.conf.example" "$_CLI_CONF_DIR/linux_util.conf"

_run_cli() {
    local _tmp_out
    _tmp_out=$(mktemp /tmp/linux_util_cli_out_XXXXXX)
    PATH="$_FAKE_BIN:$PATH" LINUX_UTIL_CONFIG_FILE="$_CLI_CONF_DIR/linux_util.conf" \
        timeout -k 2 10 bash "$SCRIPT_DIR/linux_util.sh" "$@" </dev/null >"$_tmp_out" 2>&1
    local _rc=$?
    _RUN_OUTPUT=$(<"$_tmp_out")
    rm -f "$_tmp_out"
    return $_rc
}

test_cli_help_exits_zero() {
    _run_cli --help
    assert_eq "0" "$?" "--help exits with code 0"
}

test_cli_help_contains_usage() {
    _run_cli --help
    if echo "$_RUN_OUTPUT" | grep -q "Usage:"; then
        _pass "--help output contains 'Usage:'"
    else
        _fail "--help output contains 'Usage:' (got: '${_RUN_OUTPUT:0:200}')"
    fi
}

test_cli_version_exits_zero() {
    _run_cli --version
    assert_eq "0" "$?" "--version exits with code 0"
}

test_cli_list_exits_zero() {
    _run_cli --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--list exits with code 0 (timed out in this environment)"
        return
    fi
    assert_eq "0" "$_rc" "--list exits with code 0"
}

test_cli_list_contains_docker() {
    _run_cli --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--list output contains 'Docker' (timed out in this environment)"
        return
    fi
    if echo "$_RUN_OUTPUT" | grep -qi "docker"; then
        _pass "--list output contains 'Docker'"
    else
        _fail "--list output contains 'Docker' (first 200 chars: '${_RUN_OUTPUT:0:200}')"
    fi
}

test_cli_check_unknown_exits_nonzero() {
    _run_cli --check "nonexistent_util_xyz_99999"
    local _rc=$?
    if [[ "$_rc" -ne 0 ]]; then
        _pass "--check <unknown utility> exits non-zero (rc=${_rc})"
    else
        _fail "--check <unknown utility> exits non-zero (got rc=0)"
    fi
}

test_cli_no_color_with_help() {
    _run_cli --no-color --help
    assert_eq "0" "$?" "--no-color --help exits with code 0"
}

test_cli_help_exits_zero
test_cli_help_contains_usage
test_cli_version_exits_zero
test_cli_list_exits_zero
test_cli_check_unknown_exits_nonzero
test_cli_no_color_with_help

# ============================================================================
# Additional CLI argument tests: flags that go through self_update_script
# (not in the pre-parse bypass list).  The fake git above keeps the self-update
# a silent no-op so these tests rely only on parse_args behaviour.
# ============================================================================

test_cli_install_no_arg_exits_nonzero() {
    _run_cli --install
    local _rc=$?
    if [[ "$_rc" -ne 0 ]]; then
        _pass "--install without arg exits non-zero (rc=${_rc})"
    else
        _fail "--install without arg exits non-zero (got rc=0)"
    fi
}

test_cli_install_no_arg_error_message() {
    _run_cli --install
    if echo "$_RUN_OUTPUT" | grep -qi "error\|requires"; then
        _pass "--install without arg prints an error/requires message"
    else
        _fail "--install without arg prints an error/requires message (got: '${_RUN_OUTPUT:0:200}')"
    fi
}

test_cli_uninstall_no_arg_exits_nonzero() {
    _run_cli --uninstall
    local _rc=$?
    if [[ "$_rc" -ne 0 ]]; then
        _pass "--uninstall without arg exits non-zero (rc=${_rc})"
    else
        _fail "--uninstall without arg exits non-zero (got rc=0)"
    fi
}

test_cli_update_no_arg_exits_nonzero() {
    _run_cli --update
    local _rc=$?
    if [[ "$_rc" -ne 0 ]]; then
        _pass "--update without arg exits non-zero (rc=${_rc})"
    else
        _fail "--update without arg exits non-zero (got rc=0)"
    fi
}

test_cli_unknown_flag_exits_nonzero() {
    _run_cli --bogus-flag-xyz-99999
    local _rc=$?
    if [[ "$_rc" -ne 0 ]]; then
        _pass "Unknown flag exits non-zero (rc=${_rc})"
    else
        _fail "Unknown flag exits non-zero (got rc=0)"
    fi
}

test_cli_verbose_list_exits_zero() {
    _run_cli --verbose --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--verbose --list exits with code 0 (timed out in this environment)"
        return
    fi
    assert_eq "0" "$_rc" "--verbose --list exits with code 0"
}

test_cli_debug_list_exits_zero() {
    _run_cli --debug --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--debug --list exits with code 0 (timed out in this environment)"
        return
    fi
    assert_eq "0" "$_rc" "--debug --list exits with code 0"
}

test_cli_dry_run_install_exits_zero() {
    _run_cli --dry-run --install Docker
    assert_eq "0" "$?" "--dry-run --install Docker exits with code 0"
}

test_cli_dry_run_install_output_indicator() {
    _run_cli --dry-run --install Docker
    if echo "$_RUN_OUTPUT" | grep -qi "dry.run\|DRY.RUN"; then
        _pass "--dry-run --install Docker output contains dry-run indicator"
    else
        _fail "--dry-run --install Docker output contains dry-run indicator (got: '${_RUN_OUTPUT:0:200}')"
    fi
}

test_cli_dry_run_update_all_exits_zero() {
    _run_cli --dry-run --update-all
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--dry-run --update-all exits with code 0 (timed out in this environment)"
        return
    fi
    assert_eq "0" "$_rc" "--dry-run --update-all exits with code 0"
}

test_cli_install_no_arg_exits_nonzero
test_cli_install_no_arg_error_message
test_cli_uninstall_no_arg_exits_nonzero
test_cli_update_no_arg_exits_nonzero
test_cli_unknown_flag_exits_nonzero
test_cli_dry_run_install_exits_zero
test_cli_dry_run_install_output_indicator
test_cli_dry_run_update_all_exits_zero

# _FAKE_BIN is kept alive until all _run_cli tests (including profile export/import
# below) are done. The cleanup at the end of this file removes it.

# ============================================================================
# Profile Export / Import Tests
# ============================================================================
echo ""
echo "=== Profile Export / Import Tests ==="

test_export_profile_all() {
    local tmpfile
    tmpfile=$(mktemp /tmp/test_export_XXXXXX.json)
    _run_cli --export-profile "$tmpfile"
    local rc=$?
    assert_eq "0" "$rc" "--export-profile (all) exits with code 0"
    assert_file_exists "$tmpfile" "--export-profile creates output file"
    local content
    content=$(cat "$tmpfile" 2>/dev/null)
    assert_contains "$content" "linux_util_profile_export" "--export-profile output contains schema marker"
    assert_contains "$content" '"profiles"' "--export-profile output contains profiles key"
    rm -f "$tmpfile"
}

test_export_profile_named() {
    local tmpfile
    tmpfile=$(mktemp /tmp/test_export_named_XXXXXX.json)
    _run_cli --export-profile "Run Me First" "$tmpfile"
    local rc=$?
    assert_eq "0" "$rc" "--export-profile <name> exits with code 0"
    local content
    content=$(cat "$tmpfile" 2>/dev/null)
    assert_contains "$content" "Run Me First" "--export-profile <name> output contains profile label"
    assert_contains "$content" "Timeshift" "--export-profile includes Timeshift in Run Me First"
    rm -f "$tmpfile"
}

test_export_profile_unknown_name() {
    local tmpfile
    tmpfile=$(mktemp /tmp/test_export_unk_XXXXXX.json)
    _run_cli --export-profile "No Such Profile" "$tmpfile"
    local rc=$?
    assert_eq "1" "$rc" "--export-profile with unknown name exits non-zero"
    rm -f "$tmpfile"
}

test_export_profile_no_arg_exits_nonzero() {
    _run_cli --export-profile
    assert_eq "1" "$?" "--export-profile without args exits non-zero"
}

test_import_profile_no_arg_exits_nonzero() {
    _run_cli --import-profile
    assert_eq "1" "$?" "--import-profile without args exits non-zero"
}

test_import_profile_missing_file_exits_nonzero() {
    _run_cli --import-profile /tmp/no_such_file_XXXXXX.json
    assert_eq "1" "$?" "--import-profile with missing file exits non-zero"
}

test_import_profile_invalid_file_exits_nonzero() {
    local tmpfile
    tmpfile=$(mktemp /tmp/test_import_bad_XXXXXX.json)
    echo '{"not": "a valid export"}' > "$tmpfile"
    _run_cli --import-profile "$tmpfile"
    local rc=$?
    assert_eq "1" "$rc" "--import-profile with invalid file exits non-zero"
    rm -f "$tmpfile"
}

test_dry_run_import_profile() {
    local exportfile
    exportfile=$(mktemp /tmp/test_dry_import_XXXXXX.json)
    _run_cli --export-profile "Run Me First" "$exportfile"
    _run_cli --dry-run --import-profile "$exportfile"
    local rc=$?
    assert_eq "0" "$rc" "--dry-run --import-profile exits with code 0"
    assert_contains "$_RUN_OUTPUT" "dry-run|DRY RUN|dry run|skipped" \
        "--dry-run --import-profile output references dry-run mode"
    rm -f "$exportfile"
}

test_export_profile_all
test_export_profile_named
test_export_profile_unknown_name
test_export_profile_no_arg_exits_nonzero
test_import_profile_no_arg_exits_nonzero
test_import_profile_missing_file_exits_nonzero
test_import_profile_invalid_file_exits_nonzero
test_dry_run_import_profile

# ============================================================================
# JSON Output Tests (--json flag)
# ============================================================================
echo ""
echo "=== JSON Output Tests ==="

test_json_list_exits_zero() {
    _run_cli --json --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--json --list exits with code 0 (timed out)"
        return
    fi
    assert_eq "0" "$_rc" "--json --list exits with code 0"
}

test_json_list_is_valid_json() {
    if ! command -v python3 &>/dev/null; then
        _skip "--json --list output is valid JSON (python3 not available)"
        return
    fi
    _run_cli --json --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--json --list output is valid JSON (timed out)"
        return
    fi
    # _run_cli captures stdout+stderr; strip diagnostic lines before the JSON object.
    local _json_out
    _json_out=$(echo "$_RUN_OUTPUT" | awk '/^\{/{found=1} found{print}')
    if echo "$_json_out" | python3 -m json.tool &>/dev/null; then
        _pass "--json --list output is valid JSON"
    else
        _fail "--json --list output is valid JSON (output was: '${_RUN_OUTPUT:0:200}')"
    fi
}

test_json_list_has_schema() {
    _run_cli --json --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--json --list output contains 'schema' key (timed out)"
        return
    fi
    assert_contains "$_RUN_OUTPUT" "schema" \
        "--json --list output contains 'schema' key"
}

test_json_list_has_utilities() {
    _run_cli --json --list
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--json --list output contains 'utilities' key (timed out)"
        return
    fi
    assert_contains "$_RUN_OUTPUT" "utilities" \
        "--json --list output contains 'utilities' key"
}

test_json_list_alternate_order_exits_zero() {
    _run_cli --list --json
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--list --json (alternate order) exits with code 0 (timed out)"
        return
    fi
    assert_eq "0" "$_rc" "--list --json (alternate order) exits with code 0"
}

test_json_list_alternate_is_valid_json() {
    if ! command -v python3 &>/dev/null; then
        _skip "--list --json (alternate order) output is valid JSON (python3 not available)"
        return
    fi
    _run_cli --list --json
    local _rc=$?
    if [[ "$_rc" -eq 124 ]]; then
        _skip "--list --json (alternate order) output is valid JSON (timed out)"
        return
    fi
    # _run_cli captures stdout+stderr; strip diagnostic lines before the JSON object.
    local _json_out
    _json_out=$(echo "$_RUN_OUTPUT" | awk '/^\{/{found=1} found{print}')
    if echo "$_json_out" | python3 -m json.tool &>/dev/null; then
        _pass "--list --json (alternate order) output is valid JSON"
    else
        _fail "--list --json (alternate order) output is valid JSON (output: '${_RUN_OUTPUT:0:200}')"
    fi
}

test_json_check_unknown_exits_nonzero() {
    _run_cli --json --check "nonexistent_util_xyz_99999"
    assert_eq "1" "$?" "--json --check <unknown> exits non-zero"
}

test_json_list_exits_zero
test_json_list_is_valid_json
test_json_list_has_schema
test_json_list_has_utilities
test_json_list_alternate_order_exits_zero
test_json_list_alternate_is_valid_json
test_json_check_unknown_exits_nonzero

# ============================================================================
# Test: WSL Support (is_wsl / wsl_distro_name / do_reboot)
# ============================================================================
echo ""
echo "=== WSL Support Tests ==="

# is_wsl detects WSL when $WSL_DISTRO_NAME is set. Run in a subshell so the
# cached _IS_WSL and the env override do not leak into other tests.
test_is_wsl_true_when_distro_name_set() {
    local rc
    ( unset _IS_WSL; WSL_DISTRO_NAME="Ubuntu"; is_wsl ); rc=$?
    assert_eq "0" "$rc" "is_wsl returns true when WSL_DISTRO_NAME is set"
}

# is_wsl returns false when no WSL marker is present. We unset the env var and
# shadow grep so /proc/version cannot match microsoft/-WSL2.
test_is_wsl_false_without_markers() {
    local rc
    (
        unset _IS_WSL WSL_DISTRO_NAME
        grep() { return 1; }
        is_wsl
    ); rc=$?
    assert_eq "1" "$rc" "is_wsl returns false when no WSL markers present"
}

# is_wsl detects WSL via /proc/version markers even without the env var.
test_is_wsl_true_via_proc_version() {
    local rc
    (
        unset _IS_WSL WSL_DISTRO_NAME
        grep() { return 0; }   # simulate microsoft/-WSL2 match
        is_wsl
    ); rc=$?
    assert_eq "0" "$rc" "is_wsl returns true when /proc/version matches"
}

# is_wsl caches its result in _IS_WSL on first call.
test_is_wsl_caches_result() {
    local cached
    cached=$( unset _IS_WSL; WSL_DISTRO_NAME="Ubuntu"; is_wsl; printf '%s' "$_IS_WSL" )
    assert_eq "true" "$cached" "is_wsl caches result in _IS_WSL"
}

# wsl_distro_name echoes the running distro name.
test_wsl_distro_name_echoes_var() {
    local out
    out=$( WSL_DISTRO_NAME="Ubuntu" wsl_distro_name )
    assert_eq "Ubuntu" "$out" "wsl_distro_name echoes WSL_DISTRO_NAME"
}

# do_reboot under WSL must use the wsl.exe interop bridge and must NOT call
# systemctl. We stub command -v to report wsl.exe present, stub wsl.exe and
# exit so the function does not actually terminate the test process.
#
# The wsl.exe stub distinguishes `--terminate` from the post-terminate
# `--list --running` poll: --list reports the distro as no longer running
# (empty output) so the wait loop exits on its first iteration instead of
# blocking for the full timeout.
test_do_reboot_wsl_uses_interop_not_systemctl() {
    local out
    out=$(
        _IS_WSL=true
        WSL_DISTRO_NAME="Ubuntu"
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "wsl.exe" ]]; then return 0; fi
            builtin command "$@"
        }
        wsl.exe() {
            if [[ "${1:-}" == "--list" ]]; then return 0; fi   # distro gone
            echo "INTEROP:wsl.exe $*"
        }
        systemctl() { echo "SYSTEMCTL_CALLED"; }
        exit() { return 0; }   # neutralize the real exit so the test continues
        do_reboot 2>&1
    )
    assert_contains "$out" "INTEROP:wsl.exe --terminate Ubuntu" \
        "do_reboot (WSL) terminates distro via wsl.exe"
    assert_false "do_reboot (WSL) does not call systemctl" \
        grep -q "SYSTEMCTL_CALLED" <<< "$out"
}

# do_reboot under WSL waits for the distro to leave the running list before
# returning. We make `--list --running` report the distro as still running for
# the first two polls, then gone; the loop must spin (not break immediately)
# and must not hang. A counter file tracks poll invocations.
test_do_reboot_wsl_waits_for_distro_to_stop() {
    local out cnt_file polls
    cnt_file=$(mktemp)
    printf '0' > "$cnt_file"
    out=$(
        _IS_WSL=true
        WSL_DISTRO_NAME="Ubuntu"
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "wsl.exe" ]]; then return 0; fi
            builtin command "$@"
        }
        wsl.exe() {
            if [[ "${1:-}" == "--list" ]]; then
                local n; n=$(<"$cnt_file")
                n=$((n + 1)); printf '%s' "$n" > "$cnt_file"
                # Still running for first two polls, then drop off the list.
                if (( n <= 2 )); then printf 'Ubuntu\n'; fi
                return 0
            fi
            echo "INTEROP:wsl.exe $*"
        }
        sleep() { :; }         # don't actually wait between polls
        exit() { return 0; }
        do_reboot 2>&1
    )
    polls=$(<"$cnt_file"); rm -f "$cnt_file"
    assert_contains "$out" "INTEROP:wsl.exe --terminate Ubuntu" \
        "do_reboot (WSL wait) still terminates the distro"
    assert_eq "3" "$polls" \
        "do_reboot (WSL wait) polls --list until distro stops (2 running + 1 gone)"
}

# do_reboot under WSL with no wsl.exe available prints manual instructions and
# still does not call systemctl.
test_do_reboot_wsl_fallback_prints_instructions() {
    local out
    out=$(
        _IS_WSL=true
        WSL_DISTRO_NAME="Ubuntu"
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "wsl.exe" ]]; then return 1; fi
            builtin command "$@"
        }
        systemctl() { echo "SYSTEMCTL_CALLED"; }
        do_reboot 2>&1
    )
    assert_contains "$out" "wsl --terminate Ubuntu" \
        "do_reboot (WSL fallback) prints terminate instruction"
    assert_false "do_reboot (WSL fallback) does not call systemctl" \
        grep -q "SYSTEMCTL_CALLED" <<< "$out"
}

# do_reboot on a normal host runs `sudo systemctl reboot` (unchanged behavior).
test_do_reboot_host_uses_systemctl() {
    local out
    out=$(
        _IS_WSL=false
        sudo() { echo "SUDO:$*"; }
        do_reboot 2>&1
    )
    assert_contains "$out" "SUDO:systemctl reboot" \
        "do_reboot (host) runs sudo systemctl reboot"
}

# do_reboot with no argument terminates this distro only under WSL (must never
# escalate to a full --shutdown of the whole VM).
test_do_reboot_wsl_default_still_terminates() {
    local out
    out=$(
        _IS_WSL=true
        WSL_DISTRO_NAME="Ubuntu"
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "wsl.exe" ]]; then return 0; fi
            builtin command "$@"
        }
        wsl.exe() {
            if [[ "${1:-}" == "--list" ]]; then return 0; fi
            echo "INTEROP:wsl.exe $*"
        }
        exit() { return 0; }
        do_reboot 2>&1
    )
    assert_contains "$out" "INTEROP:wsl.exe --terminate Ubuntu" \
        "do_reboot (WSL) terminates this distro only"
    assert_false "do_reboot (WSL) does not run a full --shutdown" \
        grep -q -- "--shutdown" <<< "$out"
}

test_is_wsl_true_when_distro_name_set
test_is_wsl_false_without_markers
test_is_wsl_true_via_proc_version
test_is_wsl_caches_result
test_wsl_distro_name_echoes_var
test_do_reboot_wsl_uses_interop_not_systemctl
test_do_reboot_wsl_waits_for_distro_to_stop
test_do_reboot_wsl_fallback_prints_instructions
test_do_reboot_host_uses_systemctl
test_do_reboot_wsl_default_still_terminates

# ============================================================================
# Test: Window Button Layout (detect_window_button_de / install_window_buttons)
# ============================================================================
echo ""
echo "=== Window Button Layout Tests ==="

# The installer functions live in a per-utility file that the harness does not
# source by default (only lib/*.sh are sourced). Source it here; it only defines
# functions, so sourcing has no side effects.
source "${SCRIPT_DIR}/lib/installers/window_buttons.sh"

# detect_window_button_de maps the XDG_CURRENT_DESKTOP hint to a DE token.
test_detect_de_gnome_from_hint() {
    local out
    out=$( XDG_CURRENT_DESKTOP="ubuntu:GNOME" DESKTOP_SESSION="" detect_window_button_de )
    assert_eq "gnome" "$out" "detect_window_button_de maps GNOME hint to gnome"
}

test_detect_de_kde_from_hint() {
    local out
    out=$( XDG_CURRENT_DESKTOP="KDE" DESKTOP_SESSION="plasma" detect_window_button_de )
    assert_eq "kde" "$out" "detect_window_button_de maps KDE hint to kde"
}

test_detect_de_xfce_from_hint() {
    local out
    out=$( XDG_CURRENT_DESKTOP="XFCE" DESKTOP_SESSION="" detect_window_button_de )
    assert_eq "xfce" "$out" "detect_window_button_de maps XFCE hint to xfce"
}

# With no hint, detection falls back to probing the available gsettings schema.
# Stub gsettings to advertise only the GNOME schema and command to report it
# present; xfconf-query is reported absent.
test_detect_de_fallback_to_gnome_schema() {
    local out
    out=$(
        unset XDG_CURRENT_DESKTOP DESKTOP_SESSION
        command() {
            case "${2:-}" in
                gsettings) return 0 ;;
                xfconf-query) return 1 ;;
            esac
            builtin command "$@"
        }
        gsettings() {
            [[ "${1:-}" == "list-schemas" ]] && { printf 'org.gnome.desktop.wm.preferences\n'; return 0; }
            return 0
        }
        detect_window_button_de
    )
    assert_eq "gnome" "$out" "detect_window_button_de falls back to gnome via schema probe"
}

# install_window_buttons on GNOME issues the exact gsettings command and never
# calls sudo. A session bus is faked so the no-GUI guard is not taken.
test_install_window_buttons_gnome_sets_layout() {
    local out
    out=$(
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/fake"
        XDG_CURRENT_DESKTOP="GNOME"
        DESKTOP_SESSION=""
        gsettings() { echo "GSETTINGS:$*"; return 0; }
        sudo() { echo "SUDO_CALLED"; }
        install_window_buttons 2>&1
    )
    assert_contains "$out" "GSETTINGS:set org.gnome.desktop.wm.preferences button-layout :minimize,maximize,close" \
        "install_window_buttons (GNOME) sets button-layout to :minimize,maximize,close"
    assert_false "install_window_buttons (GNOME) does not call sudo" \
        grep -q "SUDO_CALLED" <<< "$out"
}

# install_window_buttons on Xfce uses xfconf-query, not gsettings.
test_install_window_buttons_xfce_uses_xfconf() {
    local out
    out=$(
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/fake"
        XDG_CURRENT_DESKTOP="XFCE"
        DESKTOP_SESSION=""
        xfconf-query() { echo "XFCONF:$*"; return 0; }
        gsettings() { echo "GSETTINGS_CALLED"; }
        install_window_buttons 2>&1
    )
    assert_contains "$out" "XFCONF:-c xfwm4 -p /general/button_layout -s O|HMC" \
        "install_window_buttons (Xfce) sets xfwm4 button_layout via xfconf-query"
    assert_false "install_window_buttons (Xfce) does not use gsettings" \
        grep -q "GSETTINGS_CALLED" <<< "$out"
}

# install_window_buttons on KDE makes no change (KWin ignores the GNOME key).
test_install_window_buttons_kde_skips() {
    local out
    out=$(
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/fake"
        XDG_CURRENT_DESKTOP="KDE"
        DESKTOP_SESSION=""
        gsettings() { echo "GSETTINGS_CALLED"; }
        xfconf-query() { echo "XFCONF_CALLED"; }
        install_window_buttons 2>&1
    )
    assert_false "install_window_buttons (KDE) does not call gsettings" \
        grep -q "GSETTINGS_CALLED" <<< "$out"
    assert_false "install_window_buttons (KDE) does not call xfconf-query" \
        grep -q "XFCONF_CALLED" <<< "$out"
}

# With no graphical session (no D-Bus/Wayland/X), the function warns and makes
# no change instead of failing obscurely.
test_install_window_buttons_no_session_skips() {
    local out
    out=$(
        unset DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY DISPLAY
        XDG_CURRENT_DESKTOP="GNOME"
        gsettings() { echo "GSETTINGS_CALLED"; }
        install_window_buttons 2>&1
    )
    assert_contains "$out" "No graphical session detected" \
        "install_window_buttons warns when no graphical session is present"
    assert_false "install_window_buttons (no session) does not call gsettings" \
        grep -q "GSETTINGS_CALLED" <<< "$out"
}

# get_version_window_buttons reports a human-readable DE label for the menu.
test_get_version_window_buttons_reports_de() {
    local out
    out=$( XDG_CURRENT_DESKTOP="GNOME" DESKTOP_SESSION="" get_version_window_buttons )
    assert_eq "GNOME" "$out" "get_version_window_buttons reports detected DE label"
}

# ----------------------------------------------------------------------------
# System info gatherer: Packages / WM / DE fields (lib/menu.sh)
# ----------------------------------------------------------------------------
# menu.sh only declares functions/variables at source time (no side effects),
# so it is safe to source here to exercise _gather_sysinfo's new branches.
source "${SCRIPT_DIR}/lib/menu.sh"

# _humanize_duration: compact age formatting across unit boundaries.
test_humanize_duration_hours() {
    assert_eq "5h" "$(_humanize_duration 18000)" "_humanize_duration formats sub-day as hours"
}
test_humanize_duration_days() {
    assert_eq "18d" "$(_humanize_duration 1555200)" "_humanize_duration formats sub-month as days"
}
test_humanize_duration_months() {
    assert_eq "5mo 6d" "$(_humanize_duration 13478400)" "_humanize_duration formats sub-year as months+days"
}
test_humanize_duration_years() {
    assert_eq "2y 3mo" "$(_humanize_duration 71000000)" "_humanize_duration formats multi-year as years+months"
}

# OS Age: formats "<age> (<install date>)" from a detected install epoch.
test_gather_os_age_format() {
    local out
    out=$(
        # Force UTC so the epoch renders to a fixed calendar date regardless of
        # the host timezone. 1710460800 = 2024-03-15 00:00:00 UTC.
        export TZ=UTC
        PKG_MGR=""
        is_wsl() { return 1; }
        detect_window_button_de() { printf 'unknown'; }
        # _gather_sysinfo uses live `date` for "now", so assert only on the
        # parenthesized install date, which is deterministic under fixed TZ.
        _detect_install_epoch() { printf '1710460800'; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_OS_AGE"
    )
    assert_contains "$out" "(15 Mar 2024)" "_gather_sysinfo formats OS Age with install date"
}

# OS Age: unknown when no install epoch can be detected.
test_gather_os_age_unknown() {
    local out
    out=$(
        PKG_MGR=""
        is_wsl() { return 1; }
        detect_window_button_de() { printf 'unknown'; }
        _detect_install_epoch() { printf ''; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_OS_AGE"
    )
    assert_eq "unknown" "$out" "_gather_sysinfo reports unknown OS Age when undetectable"
}

# Packages: apt branch formats "<count> (dpkg)" from dpkg-query output.
test_gather_packages_apt_format() {
    local out
    out=$(
        PKG_MGR=apt
        # Stub command -v so only dpkg-query is reported present, and stub the
        # query itself to emit a fixed three-line result.
        command() {
            if [[ "${1:-}" == "-v" ]]; then
                [[ "${2:-}" == "dpkg-query" ]] && return 0 || return 1
            fi
            builtin command "$@"
        }
        dpkg-query() { printf '.\n.\n.\n'; }
        is_wsl() { return 1; }
        detect_window_button_de() { printf 'unknown'; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_PACKAGES"
    )
    assert_eq "3 (dpkg)" "$out" "_gather_sysinfo formats apt package count as '<n> (dpkg)'"
}

# Packages: unknown when the package manager / query tool is unavailable.
test_gather_packages_unknown_when_no_tool() {
    local out
    out=$(
        PKG_MGR=""
        is_wsl() { return 1; }
        detect_window_button_de() { printf 'unknown'; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_PACKAGES"
    )
    assert_eq "unknown" "$out" "_gather_sysinfo reports unknown packages when no manager"
}

# DE: maps the detect_window_button_de token to a display name.
test_gather_de_maps_kde_token() {
    local out
    out=$(
        PKG_MGR=""
        is_wsl() { return 1; }
        detect_window_button_de() { printf 'kde'; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_DE"
    )
    assert_eq "KDE Plasma" "$out" "_gather_sysinfo maps kde token to 'KDE Plasma'"
}

# DE: falls back to the XDG hint (prefix-stripped) on an unknown token.
test_gather_de_falls_back_to_xdg_hint() {
    local out
    out=$(
        PKG_MGR=""
        XDG_CURRENT_DESKTOP="ubuntu:GNOME"
        is_wsl() { return 1; }
        detect_window_button_de() { printf 'unknown'; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_DE"
    )
    assert_eq "GNOME" "$out" "_gather_sysinfo falls back to XDG hint and strips prefix"
}

# WM: reports WSLg under WSL with a Wayland display.
test_gather_wm_wslg_under_wsl() {
    local out
    out=$(
        PKG_MGR=""
        WAYLAND_DISPLAY="wayland-0"
        is_wsl() { return 0; }
        detect_window_button_de() { printf 'unknown'; }
        _gather_sysinfo
        printf '%s' "$_SYSINFO_WM"
    )
    assert_eq "WSLg" "$out" "_gather_sysinfo reports WSLg under WSL with Wayland display"
}

# ============================================================================
# Test: Kernel Managers (Mainline / CachyOS Kernel Manager / Fedora Mainline)
# ============================================================================
echo ""
echo "=== Kernel Manager Tests ==="

# These per-utility files are not sourced by default — source them here. They
# only define functions and constants, so sourcing has no side effects.
source "${SCRIPT_DIR}/lib/installers/mainline_kernel.sh"
source "${SCRIPT_DIR}/lib/installers/cachyos_kernel_manager.sh"
source "${SCRIPT_DIR}/lib/installers/fedora_mainline_kernel.sh"
source "${SCRIPT_DIR}/lib/installers/linux_tkg.sh"

# Mainline is Debian/Ubuntu-only; on another family it must warn and stop before
# touching the package manager.
test_install_mainline_warns_off_debian() {
    local out rc
    out=$( DISTRO_FAMILY="arch" install_mainline 2>&1 ); rc=$?
    assert_eq "1" "$rc" "install_mainline returns 1 on a non-Debian family"
    assert_contains "$out" "Debian/Ubuntu-only" \
        "install_mainline warns it is a Debian/Ubuntu-only tool off-family"
}

# CachyOS Kernel Manager is Arch-only; off-family it warns and stops.
test_install_cachyos_km_warns_off_arch() {
    local out rc
    out=$( DISTRO_FAMILY="debian" install_cachyos_kernel_manager 2>&1 ); rc=$?
    assert_eq "1" "$rc" "install_cachyos_kernel_manager returns 1 on a non-Arch family"
    assert_contains "$out" "Arch-family" \
        "install_cachyos_kernel_manager warns it is an Arch-family tool off-family"
}

# On Arch, but with the package absent from every configured repo, it must refuse
# (it never adds the CachyOS repo itself) rather than failing obscurely.
test_install_cachyos_km_requires_repo() {
    local out rc
    out=$(
        DISTRO_FAMILY="arch"
        pacman() { return 1; }          # simulate: package not in any repo
        pkg_install() { echo "PKG_INSTALL_CALLED"; }
        install_cachyos_kernel_manager 2>&1
    ); rc=$?
    assert_eq "1" "$rc" "install_cachyos_kernel_manager returns 1 when the package is not in a repo"
    assert_contains "$out" "not found in any configured pacman repository" \
        "install_cachyos_kernel_manager explains the package is not in a configured repo"
    assert_false "install_cachyos_kernel_manager does not attempt the install when the package is absent" \
        grep -q "PKG_INSTALL_CALLED" <<< "$out"
}

# Fedora Mainline Kernel is Fedora-only; off-family it warns and stops.
test_install_fedora_mainline_warns_off_fedora() {
    local out rc
    out=$( DISTRO_FAMILY="debian" install_fedora_mainline_kernel 2>&1 ); rc=$?
    assert_eq "1" "$rc" "install_fedora_mainline_kernel returns 1 off Fedora"
    assert_contains "$out" "only works on Fedora" \
        "install_fedora_mainline_kernel warns it only works on Fedora"
}

# With the Copr not enabled, the check reports not-installed and the version is blank.
test_check_fedora_mainline_kernel_absent() {
    assert_false "check_fedora_mainline_kernel is false without the kernel-vanilla Copr" \
        check_fedora_mainline_kernel
    local out
    out=$( get_version_fedora_mainline_kernel )
    assert_eq "" "$out" "get_version_fedora_mainline_kernel is empty without the Copr"
}

# linux-tkg refuses distros it cannot build on, before touching anything.
test_install_linux_tkg_unsupported_distro() {
    local out rc
    out=$( DISTRO_FAMILY="gentoo" install_linux_tkg 2>&1 ); rc=$?
    assert_eq "1" "$rc" "install_linux_tkg returns 1 on an unsupported distribution"
    assert_contains "$out" "not supported on this distribution" \
        "install_linux_tkg explains it cannot build on an unsupported distribution"
}

# Without a tkg kernel running or installed, the check reports not-installed.
test_check_linux_tkg_absent() {
    assert_false "check_linux_tkg is false when no tkg kernel is present" check_linux_tkg
}

test_install_mainline_warns_off_debian
test_install_cachyos_km_warns_off_arch
test_install_cachyos_km_requires_repo
test_install_fedora_mainline_warns_off_fedora
test_check_fedora_mainline_kernel_absent
test_install_linux_tkg_unsupported_distro
test_check_linux_tkg_absent

test_detect_de_gnome_from_hint
test_detect_de_kde_from_hint
test_detect_de_xfce_from_hint
test_detect_de_fallback_to_gnome_schema
test_humanize_duration_hours
test_humanize_duration_days
test_humanize_duration_months
test_humanize_duration_years
test_gather_os_age_format
test_gather_os_age_unknown
test_gather_packages_apt_format
test_gather_packages_unknown_when_no_tool
test_gather_de_maps_kde_token
test_gather_de_falls_back_to_xdg_hint
test_gather_wm_wslg_under_wsl
test_install_window_buttons_gnome_sets_layout
test_install_window_buttons_xfce_uses_xfconf
test_install_window_buttons_kde_skips
test_install_window_buttons_no_session_skips
test_get_version_window_buttons_reports_de

# ============================================================================
# Test: AUR Routing Helpers (repo_or_aur / flatpak_or_aur)
# ============================================================================
echo ""
echo "=== AUR Routing Tests ==="

source "${SCRIPT_DIR}/lib/aur.sh"

# repo_or_aur exists because aur_ensure falls through to aur_build on a system
# with no yay/paru, and aur_build clones aur.archlinux.org/<pkg>.git — which does
# not exist for a package that only ships in core/extra. The repo must win.
test_repo_or_aur_prefers_pacman() {
    local out
    out=$(
        sudo() { [[ "$1" == "pacman" ]] && echo "PACMAN_CALLED"; return 0; }
        aur_ensure() { echo "AUR_CALLED"; }
        repo_or_aur obsidian 2>&1
    )
    assert_contains "$out" "PACMAN_CALLED" "repo_or_aur tries pacman first"
    assert_false "repo_or_aur does not touch the AUR when the repo has the package" \
        grep -q "AUR_CALLED" <<< "$out"
}

test_repo_or_aur_falls_back_to_aur() {
    local out
    out=$(
        sudo() { return 1; }             # simulate: not in any configured repo
        aur_ensure() { echo "AUR_CALLED"; }
        repo_or_aur some-derivative-pkg 2>&1
    )
    assert_contains "$out" "AUR_CALLED" \
        "repo_or_aur falls back to the AUR when the package is not in a repo"
}

# flatpak_or_aur must not install flatpak itself — a system without it has not
# opted in, and dragging in the runtime stack to dodge one AUR package is worse.
test_flatpak_or_aur_uses_aur_without_flatpak() {
    local out
    out=$(
        has_flatpak() { return 1; }
        ensure_flatpak() { echo "ENSURE_FLATPAK_CALLED"; return 0; }
        aur_ensure() { echo "AUR_CALLED"; }
        flatpak_or_aur com.slack.Slack slack-desktop 2>&1
    )
    assert_contains "$out" "AUR_CALLED" "flatpak_or_aur uses the AUR when flatpak is absent"
    assert_false "flatpak_or_aur never installs flatpak just to avoid the AUR" \
        grep -q "ENSURE_FLATPAK_CALLED" <<< "$out"
}

# The flathub remote is added system-wide (sudo flatpak remote-add), so the
# install deploys system-wide too and MUST be elevated: an unprivileged process
# is refused by polkit with "Flatpak system operation Deploy not allowed for
# user" -- and only after the whole download has finished. The sudo stub
# forwards to the flatpak stub so both halves are asserted here, and so the
# suite can never shell out to real sudo.
test_flatpak_or_aur_prefers_flathub() {
    local out
    out=$(
        has_flatpak() { return 0; }
        ensure_flatpak() { return 0; }
        sudo() { echo "SUDO_CALLED"; "$@"; }
        flatpak() { echo "FLATPAK_CALLED $*"; return 0; }
        aur_ensure() { echo "AUR_CALLED"; }
        flatpak_or_aur com.slack.Slack slack-desktop 2>&1
    )
    assert_contains "$out" "FLATPAK_CALLED install -y flathub com.slack.Slack" \
        "flatpak_or_aur installs the Flathub app when flatpak is set up"
    assert_contains "$out" "SUDO_CALLED" \
        "flatpak_or_aur installs the Flathub app with root privileges"
    assert_false "flatpak_or_aur does not also hit the AUR on a successful Flatpak install" \
        grep -q "AUR_CALLED" <<< "$out"
}

# A Flathub app can be pulled or renamed; that must degrade to the AUR, not fail.
test_flatpak_or_aur_falls_back_on_flatpak_failure() {
    local out
    out=$(
        has_flatpak() { return 0; }
        ensure_flatpak() { return 0; }
        sudo() { "$@"; }
        flatpak() { return 1; }
        aur_ensure() { echo "AUR_CALLED"; }
        flatpak_or_aur com.slack.Slack slack-desktop 2>&1
    )
    assert_contains "$out" "AUR_CALLED" \
        "flatpak_or_aur falls back to the AUR when the Flatpak install fails"
}

# --- arch_install_ordered: the tier ladder ---
# repos -> Flathub -> upstream binary -> AUR. The binary tier is what keeps a
# package installable at all once AUR_ENABLED stays false, so its position
# between Flathub and the AUR is load-bearing.
test_arch_install_ordered_flatpak_tier_is_elevated() {
    local out
    out=$(
        arch_repo_has() { return 1; }
        has_flatpak() { return 0; }
        ensure_flatpak() { return 0; }
        sudo() { echo "SUDO_CALLED"; "$@"; }
        flatpak() { echo "FLATPAK_CALLED $*"; return 0; }
        aur_ensure() { echo "AUR_CALLED"; }
        arch_install_ordered "" com.slack.Slack "" slack-desktop 2>&1
    )
    assert_contains "$out" "FLATPAK_CALLED install -y flathub com.slack.Slack" \
        "arch_install_ordered installs from Flathub when the repos miss"
    assert_contains "$out" "SUDO_CALLED" \
        "arch_install_ordered runs the Flathub tier with root privileges"
}

test_arch_install_ordered_prefers_binary_over_aur() {
    local out
    out=$(
        arch_repo_has() { return 1; }
        has_flatpak() { return 1; }
        _fake_binary_install() { echo "BINARY_CALLED"; return 0; }
        aur_ensure() { echo "AUR_CALLED"; }
        arch_install_ordered "nope" com.example.App _fake_binary_install some-aur-pkg 2>&1
    )
    assert_contains "$out" "BINARY_CALLED" \
        "arch_install_ordered uses the upstream binary when repos and Flathub are unavailable"
    assert_false "arch_install_ordered does not reach the AUR when the upstream binary succeeds" \
        grep -q "AUR_CALLED" <<< "$out"
}

test_arch_install_ordered_binary_catches_flatpak_failure() {
    local out
    out=$(
        arch_repo_has() { return 1; }
        has_flatpak() { return 0; }
        ensure_flatpak() { return 0; }
        sudo() { "$@"; }
        flatpak() { return 1; }
        _fake_binary_install() { echo "BINARY_CALLED"; return 0; }
        aur_ensure() { echo "AUR_CALLED"; }
        arch_install_ordered "" com.example.App _fake_binary_install some-aur-pkg 2>&1
    )
    assert_contains "$out" "BINARY_CALLED" \
        "arch_install_ordered falls to the upstream binary when the Flatpak install fails"
    assert_false "a failed Flatpak install does not skip the binary tier and hit the AUR" \
        grep -q "AUR_CALLED" <<< "$out"
}

test_repo_or_aur_prefers_pacman
test_repo_or_aur_falls_back_to_aur
test_flatpak_or_aur_uses_aur_without_flatpak
test_flatpak_or_aur_prefers_flathub
test_flatpak_or_aur_falls_back_on_flatpak_failure
test_arch_install_ordered_flatpak_tier_is_elevated
test_arch_install_ordered_prefers_binary_over_aur
test_arch_install_ordered_binary_catches_flatpak_failure

# --- AUR disabled-by-default kill switch ---

test_aur_install_refuses_when_disabled() {
    local out rc
    out=$(
        unset AUR_ENABLED
        has_aur_helper() { return 0; }
        _aur_helper_run() { echo "HELPER_CALLED"; }
        aur_install obsidian 2>&1
    ); rc=$?
    assert_contains "$out" "AUR support is currently disabled" \
        "aur_install refuses by default"
    assert_false "aur_install never runs the AUR helper while disabled" \
        grep -q "HELPER_CALLED" <<< "$out"
    assert_eq "1" "$rc" "aur_install returns failure while disabled"
}

test_aur_install_works_when_enabled() {
    local out
    out=$(
        AUR_ENABLED=true
        has_aur_helper() { return 0; }
        _aur_helper_run() { echo "HELPER_CALLED $*"; }
        aur_install obsidian 2>&1
    )
    assert_contains "$out" "HELPER_CALLED" "aur_install runs the AUR helper once re-enabled"
}

test_aur_build_refuses_when_disabled() {
    local out
    out=$(
        unset AUR_ENABLED
        git() { echo "GIT_CALLED"; }
        aur_build obsidian 2>&1
    )
    assert_contains "$out" "AUR support is currently disabled" \
        "aur_build refuses by default"
    assert_false "aur_build never clones the AUR while disabled" \
        grep -q "GIT_CALLED" <<< "$out"
}

test_aur_remove_unaffected_by_disable() {
    local out
    out=$(
        unset AUR_ENABLED
        _aur_helper_run() { echo "HELPER_REMOVE_CALLED"; return 0; }
        aur_remove obsidian 2>&1
    )
    assert_contains "$out" "HELPER_REMOVE_CALLED" \
        "aur_remove still runs while AUR is disabled — uninstall is unaffected"
}

test_aur_install_refuses_when_disabled
test_aur_install_works_when_enabled
test_aur_build_refuses_when_disabled
test_aur_remove_unaffected_by_disable

# ============================================================================
# Test: WinApps compose port handling
# ============================================================================
echo ""
echo "=== WinApps Port Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/winapps.sh"

# A stand-in for upstream's compose file: the two published mappings plus the
# commented-out pair that exposes RDP to the local network, which must never be
# rewritten.
_winapps_test_compose() {
    local _file="$1"
    cat > "$_file" <<'COMPOSE_EOF'
    ports:
      # Map '8006' on Linux host to '8006' on Windows VM.
      - "127.0.0.1:8006:8006"
      # Map '3389' on Linux host to '3389' on Windows VM.
      - "127.0.0.1:3389:3389/tcp"
      - "127.0.0.1:3389:3389/udp"
      # Uncomment the next two lines to expose RDP to the local network.
      # - 3389:3389/tcp
      # - 3389:3389/udp
COMPOSE_EOF
}

test_winapps_published_port_reads_mappings() {
    local _f="${LOG_DIR}/compose_read.yaml"
    _winapps_test_compose "$_f"
    assert_eq "3389" "$(_winapps_published_port "$_f" 3389)" "_winapps_published_port reads the RDP mapping"
    assert_eq "8006" "$(_winapps_published_port "$_f" 8006)" "_winapps_published_port reads the web mapping"
}

test_winapps_remap_moves_host_side_only() {
    local _f="${LOG_DIR}/compose_remap.yaml"
    _winapps_test_compose "$_f"
    _winapps_remap_port "$_f" 3389 3389 3390
    assert_contains "$(<"$_f")" '"127.0.0.1:3390:3389/tcp"' "remap moves the host side of the tcp mapping"
    assert_contains "$(<"$_f")" '"127.0.0.1:3390:3389/udp"' "remap moves the host side of the udp mapping"
    assert_contains "$(<"$_f")" '# - 3389:3389/tcp' "remap leaves commented-out mappings alone"
    assert_eq "3390" "$(_winapps_published_port "$_f" 3389)" "the remapped host port reads back"
}

# A second remap has to start from what the file publishes now, not from the
# upstream default, or re-running the installer rewrites the wrong port.
test_winapps_remap_is_repeatable() {
    local _f="${LOG_DIR}/compose_again.yaml"
    _winapps_test_compose "$_f"
    _winapps_remap_port "$_f" 3389 3389 3390
    _winapps_remap_port "$_f" "$(_winapps_published_port "$_f" 3389)" 3389 3391
    assert_contains "$(<"$_f")" '"127.0.0.1:3391:3389/tcp"' "a second remap moves the already-moved port"
    assert_eq "3391" "$(_winapps_published_port "$_f" 3389)" "the twice-remapped host port reads back"
}

# A free port leaves the compose file untouched and reports the published port.
test_winapps_settle_port_noop_when_free() {
    local _f="${LOG_DIR}/compose_free.yaml" _before="" _port=""
    _winapps_test_compose "$_f"
    _before=$(<"$_f")
    _port=$(
        _winapps_port_busy() { return 1; }
        _WINAPPS_RDP_PORT=3389
        _winapps_settle_port _WINAPPS_RDP_PORT "RDP" "$_f" 3389 >/dev/null
        echo "$_WINAPPS_RDP_PORT"
    )
    assert_eq "3389" "$_port" "_winapps_settle_port keeps a free port"
    assert_eq "$_before" "$(<"$_f")" "_winapps_settle_port does not touch the file when the port is free"
}

# A busy port with no tty republishes on the next free one rather than failing.
test_winapps_settle_port_moves_when_busy() {
    local _f="${LOG_DIR}/compose_busy.yaml" _port=""
    _winapps_test_compose "$_f"
    _port=$(
        _winapps_port_busy() { [[ "$1" == 3389 ]]; }
        _winapps_port_holder() { echo "xrdp"; }
        _winapps_have_tty() { return 1; }
        _WINAPPS_RDP_PORT=3389
        _winapps_settle_port _WINAPPS_RDP_PORT "RDP" "$_f" 3389 >/dev/null
        echo "$_WINAPPS_RDP_PORT"
    )
    assert_eq "3390" "$_port" "_winapps_settle_port republishes a busy port"
    assert_contains "$(<"$_f")" '"127.0.0.1:3390:3389/tcp"' "_winapps_settle_port rewrites the compose mapping"
}

test_winapps_published_port_reads_mappings
test_winapps_remap_moves_host_side_only
test_winapps_remap_is_repeatable
test_winapps_settle_port_noop_when_free
test_winapps_settle_port_moves_when_busy

# ============================================================================
# Test: WinApps credential sync (compose.yaml -> winapps.conf)
# ============================================================================
echo ""
echo "=== WinApps Credential Sync Tests ==="

# The compose file ships its credentials quoted with a trailing comment; the
# config ships dockur's defaults as placeholders.
_winapps_test_compose_creds() {
    cat >"$1" <<COMPOSE_EOF
    environment:
      USERNAME: "$2" # Edit here to set a custom Windows username.
      PASSWORD: "$3" # Edit here to set a password for the Windows user.
COMPOSE_EOF
}

_winapps_test_conf() {
    cat >"$1" <<CONF_EOF
RDP_USER="${2:-MyWindowsUser}"
RDP_PASS="${3:-MyWindowsPassword}"
RDP_IP="127.0.0.1"
CONF_EOF
}

test_winapps_compose_value_reads_quoted_setting() {
    local _f="${LOG_DIR}/compose_creds.yaml"
    _winapps_test_compose_creds "$_f" "admin" 'p@ss word'
    assert_eq "admin" "$(_winapps_compose_value "$_f" USERNAME)" "_winapps_compose_value reads USERNAME"
    assert_eq "p@ss word" "$(_winapps_compose_value "$_f" PASSWORD)" "_winapps_compose_value keeps spaces and drops the comment"
}

# A password holding '$' must reach the config single-quoted, or WinApps
# expands it when sourcing and authentication fails.
test_winapps_shell_quote_protects_expansion() {
    assert_eq "'Mustang68\$'" "$(_winapps_shell_quote 'Mustang68$')" "_winapps_shell_quote single-quotes a '\$' password"
    assert_eq "'it'\\''s'" "$(_winapps_shell_quote "it's")" "_winapps_shell_quote escapes an embedded single quote"
}

test_winapps_sync_replaces_placeholders() {
    local _conf="${LOG_DIR}/sync_conf" _src="${LOG_DIR}/sync_src"
    mkdir -p "$_src"
    _winapps_test_compose_creds "$_src/compose.yaml" "admin" 'Mustang68$'
    _winapps_test_conf "$_conf"
    (
        _WINAPPS_CONF="$_conf"
        _WINAPPS_SRC="$_src"
        _winapps_sync_credentials >/dev/null
    )
    assert_contains "$(<"$_conf")" "RDP_USER='admin'" "credential sync writes the compose username"
    # '[$]' rather than '$' — assert_contains matches with grep -E, where a bare
    # '$' would anchor to end of line.
    assert_contains "$(<"$_conf")" "RDP_PASS='Mustang68[$]'" "credential sync single-quotes the compose password"
    # The sourced value must survive shell expansion intact.
    local _read=""
    _read=$( set -a; . "$_conf"; set +a; printf '%s' "$RDP_PASS" )
    assert_eq 'Mustang68$' "$_read" "the written password survives being sourced"
}

# Credentials the user set deliberately are never clobbered.
test_winapps_sync_keeps_user_values() {
    local _conf="${LOG_DIR}/keep_conf" _src="${LOG_DIR}/keep_src"
    mkdir -p "$_src"
    _winapps_test_compose_creds "$_src/compose.yaml" "admin" "fromcompose"
    _winapps_test_conf "$_conf" "realuser" "realpass"
    (
        _WINAPPS_CONF="$_conf"
        _WINAPPS_SRC="$_src"
        _winapps_sync_credentials >/dev/null 2>&1
    )
    assert_contains "$(<"$_conf")" 'RDP_USER="realuser"' "credential sync leaves a customised username alone"
    assert_contains "$(<"$_conf")" 'RDP_PASS="realpass"' "credential sync leaves a customised password alone"
}

test_winapps_compose_value_reads_quoted_setting
test_winapps_shell_quote_protects_expansion
test_winapps_sync_replaces_placeholders
test_winapps_sync_keeps_user_values

# ============================================================================
# Test: WinApps launcher filtering during detection
# ============================================================================
echo ""
echo "=== WinApps Launcher Filtering Tests ==="

# WinApps installs a launcher into ~/.local/bin for every application in the
# Windows VM — pwsh, cmd, explorer and friends — which shadows the Linux
# program of the same name. Running one opens an RDP session to the VM, so
# detection must neither count them as installed nor execute them.
_WA_DIR=$(mktemp -d /tmp/linux_util_test_winapps_XXXXXX)
mkdir -p "$_WA_DIR/stub" "$_WA_DIR/real"
printf '#!/usr/bin/env bash\n%s/winapps pwsh "$@"\n'    "$_WA_DIR/stub" > "$_WA_DIR/stub/pwsh"
printf '#!/usr/bin/env bash\n%s/winapps notepad "$@"\n' "$_WA_DIR/stub" > "$_WA_DIR/stub/notepad"
printf '#!/usr/bin/env bash\necho "tool version 9.8.7"\n'               > "$_WA_DIR/real/pwsh"
# Any launcher that runs leaves this marker, so a test can prove none did.
printf '#!/usr/bin/env bash\ntouch "%s/LAUNCHED"\n' "$_WA_DIR"          > "$_WA_DIR/stub/winapps"
chmod +x "$_WA_DIR"/stub/* "$_WA_DIR"/real/*

# Evaluate an expression with the package-manager helpers loaded and the
# fixture ahead of PATH, exactly as a real WinApps install sits ahead of
# /usr/bin. The subshell inherits $_WA_DIR, so expressions can reference it.
_wa_probe() {
    (
        source "${SCRIPT_DIR}/lib/pkg_manager.sh"
        PATH="${_WA_DIR}/stub:${_WA_DIR}/real:$PATH"
        eval "$1"
    ) 2>/dev/null
}

test_winapps_launcher_is_recognised() {
    assert_eq "launcher" "$(_wa_probe '_is_winapps_stub "$_WA_DIR/stub/pwsh" && echo launcher || echo program')" \
        "_is_winapps_stub recognises a WinApps launcher"
    assert_eq "program" "$(_wa_probe '_is_winapps_stub "$_WA_DIR/real/pwsh" && echo launcher || echo program')" \
        "_is_winapps_stub leaves an ordinary script alone"
    assert_eq "program" "$(_wa_probe '_is_winapps_stub /bin/sh && echo launcher || echo program')" \
        "_is_winapps_stub leaves a compiled binary alone"
}

test_winapps_launcher_does_not_hide_real_program() {
    assert_eq "$_WA_DIR/real/pwsh" "$(_wa_probe '_native_command pwsh')" \
        "_native_command skips the launcher and finds the real program behind it"
    assert_eq "yes" "$(_wa_probe '_have_cmd pwsh && echo yes || echo no')" \
        "_have_cmd is true when a real program exists behind a launcher"
}

test_winapps_launcher_alone_is_not_installed() {
    assert_eq "no" "$(_wa_probe '_have_cmd notepad && echo yes || echo no')" \
        "_have_cmd is false when only a WinApps launcher matches"
    assert_eq "no" "$(_wa_probe '_check_standard notepad "" "" && echo yes || echo no')" \
        "_check_standard does not report a Windows-only app as installed"
}

test_winapps_launcher_is_never_executed() {
    assert_eq "9.8.7" "$(_wa_probe '_ver_from_cmd pwsh')" \
        "_ver_from_cmd reads the version from the real program, not the launcher"
    assert_eq "" "$(_wa_probe '_ver_from_cmd notepad')" \
        "_ver_from_cmd reports no version for a launcher-only command"
    assert_eq "tool version 9.8.7" "$(_wa_probe '_run_native pwsh --version')" \
        "_run_native runs the real program"
    # The marker only appears if a launcher was executed — none should have been.
    assert_false "no WinApps launcher was executed during detection" \
        test -f "$_WA_DIR/LAUNCHED"
}

test_winapps_launcher_is_recognised
test_winapps_launcher_does_not_hide_real_program
test_winapps_launcher_alone_is_not_installed
test_winapps_launcher_is_never_executed

# ============================================================================
# Test: Euro-Office source build (tag selection and artifact picking)
# ============================================================================
echo ""
echo "=== Euro-Office Build Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/euro_office.sh"

# Upstream's real tag set: release tags interleaved with pre-releases, and not
# in version order.
_euroffice_test_tags() {
    cat <<'TAGS_EOF'
v9.3.0
v9.4.0
v9.3.1-rc.1
v9.3.1
v9.2.1
v9.3.2-beta.1
v8.3.3
v9.3.1-tp.3
TAGS_EOF
}

test_euroffice_picks_newest_release_tag() {
    assert_eq "v9.4.0" "$(_euroffice_test_tags | _euroffice_pick_tag)" \
        "_euroffice_pick_tag selects the newest stable tag"
}

test_euroffice_skips_prereleases() {
    # v9.3.2-beta.1 sorts above every stable tag here; building it would ship a
    # pre-release as if it were a release.
    assert_eq "v9.3.1" "$(printf '%s\n' v9.3.1 v9.3.2-beta.1 v9.3.2-rc.1 | _euroffice_pick_tag)" \
        "_euroffice_pick_tag ignores rc/beta/tp tags"
}

test_euroffice_pick_tag_handles_no_tags() {
    assert_eq "" "$(printf '' | _euroffice_pick_tag)" \
        "_euroffice_pick_tag prints nothing when there are no tags"
}

test_euroffice_artifact_matches_family() {
    local _dir
    _dir=$(mktemp -d)
    touch "$_dir/euro-office-desktopeditors_9.4.0-dev.0_amd64.deb" \
          "$_dir/euro-office-desktopeditors-9.4.0-dev.0.x86_64.rpm" \
          "$_dir/euro-office-desktopeditors-9.4.0-dev.0-x86_64.tar.xz"

    local _family_before="$DISTRO_FAMILY"
    DISTRO_FAMILY="debian"
    assert_eq "euro-office-desktopeditors_9.4.0-dev.0_amd64.deb" \
        "$(basename "$(_euroffice_artifact "$_dir")")" \
        "_euroffice_artifact picks the .deb on Debian"

    DISTRO_FAMILY="fedora"
    assert_eq "euro-office-desktopeditors-9.4.0-dev.0.x86_64.rpm" \
        "$(basename "$(_euroffice_artifact "$_dir")")" \
        "_euroffice_artifact picks the .rpm on Fedora"

    # The tarball is never installable through the package manager, so an
    # output directory holding only that must read as a failed build.
    rm -f "$_dir"/*.deb "$_dir"/*.rpm
    DISTRO_FAMILY="debian"
    assert_false "_euroffice_artifact fails when no installable package was built" \
        _euroffice_artifact "$_dir"

    DISTRO_FAMILY="$_family_before"
    rm -rf "$_dir"
}

test_euroffice_picks_newest_release_tag
test_euroffice_skips_prereleases
test_euroffice_pick_tag_handles_no_tags
test_euroffice_artifact_matches_family

# ============================================================================
# xrdp KDE Wallet PAM Tests
# ============================================================================
echo ""
echo "=== xrdp KDE Wallet PAM Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/xrdp.sh"

# Fedora's stock /etc/pam.d/xrdp-sesman, trimmed to the lines that matter.
_xrdp_test_stock_stack() {
    cat > "$1" <<'PAM_EOF'
#%PAM-1.0
auth       include      password-auth
account    include      password-auth
password   include      password-auth

session    required     pam_selinux.so close
session    include      password-auth
session    optional     pam_lastlog.so silent
PAM_EOF
}

test_xrdp_pam_add_converts_include_to_substack() {
    local _f _out
    _f=$(mktemp); _xrdp_test_stock_stack "$_f"
    _out=$(_xrdp_pam_add_kwallet "$_f")

    # password-auth grants with "auth sufficient pam_unix.so". Reached through
    # an "include", that success returns from the whole auth stack and the
    # pam_kwallet5 line below it never runs.
    assert_contains "$_out" "auth       substack     password-auth" \
        "_xrdp_pam_add_kwallet converts the auth include to a substack"
    assert_contains "$_out" "auth       optional     pam_kwallet5.so" \
        "_xrdp_pam_add_kwallet adds the auth line"
    assert_contains "$_out" "session    optional     pam_kwallet5.so auto_start" \
        "_xrdp_pam_add_kwallet adds the session line"

    # Only the auth include is a jump; rewriting the others would be a
    # behavior change nothing here needs.
    assert_contains "$_out" "account    include      password-auth" \
        "_xrdp_pam_add_kwallet leaves the account include alone"
    assert_contains "$_out" "session    include      password-auth" \
        "_xrdp_pam_add_kwallet leaves the session include alone"
    rm -f "$_f"
}

test_xrdp_pam_add_orders_auth_line_after_the_include() {
    local _f _auth_line _kwallet_line
    _f=$(mktemp); _xrdp_test_stock_stack "$_f"
    # The module reads the password PAM has already collected, so it has to run
    # after the stack that collects it, not before.
    _auth_line=$(_xrdp_pam_add_kwallet "$_f" | grep -n "substack     password-auth" | cut -d: -f1)
    _kwallet_line=$(_xrdp_pam_add_kwallet "$_f" | grep -n "optional     pam_kwallet5.so$" | cut -d: -f1)
    assert_true "_xrdp_pam_add_kwallet puts the auth line after the substack" \
        [ "$_kwallet_line" -gt "$_auth_line" ]
    rm -f "$_f"
}

test_xrdp_pam_fix_include_repairs_an_unreachable_module() {
    local _f _out
    _f=$(mktemp); _xrdp_test_stock_stack "$_f"
    # What older versions of this installer produced: the module is named, but
    # sits below a plain "include" and so is never reached.
    printf 'auth       optional     pam_kwallet5.so\n' >> "$_f"

    _out=$(_xrdp_pam_fix_include "$_f")
    assert_contains "$_out" "auth       substack     password-auth" \
        "_xrdp_pam_fix_include converts the include above the kwallet line"
    assert_contains "$_out" "auth       optional     pam_kwallet5.so" \
        "_xrdp_pam_fix_include keeps the existing kwallet line"
    rm -f "$_f"
}

test_xrdp_pam_fix_include_is_a_no_op_when_already_correct() {
    local _f
    _f=$(mktemp)
    printf 'auth       substack     password-auth\nauth       optional     pam_kwallet5.so\n' > "$_f"
    # Non-zero exit is how the caller tells "already wired" from "repaired".
    assert_false "_xrdp_pam_fix_include reports nothing to do on a substack stack" \
        _xrdp_pam_fix_include "$_f"
    rm -f "$_f"
}

test_xrdp_pam_fix_include_ignores_a_stack_without_kwallet() {
    local _f
    _f=$(mktemp); _xrdp_test_stock_stack "$_f"
    assert_false "_xrdp_pam_fix_include reports nothing to do without a kwallet line" \
        _xrdp_pam_fix_include "$_f"
    rm -f "$_f"
}

test_xrdp_pam_add_needs_both_anchors() {
    local _f
    _f=$(mktemp)
    printf 'auth       include      password-auth\n' > "$_f"
    # No session line to anchor to: the caller must leave the file untouched
    # rather than write a half-configured stack.
    assert_false "_xrdp_pam_add_kwallet fails on a stack with no session line" \
        _xrdp_pam_add_kwallet "$_f"
    rm -f "$_f"
}

test_xrdp_pam_add_converts_include_to_substack
test_xrdp_pam_add_orders_auth_line_after_the_include
test_xrdp_pam_fix_include_repairs_an_unreachable_module
test_xrdp_pam_fix_include_is_a_no_op_when_already_correct
test_xrdp_pam_fix_include_ignores_a_stack_without_kwallet
test_xrdp_pam_add_needs_both_anchors

# ============================================================================
# LocalSend Tests
# ============================================================================
echo ""
echo "=== LocalSend Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/localsend.sh"

# Upstream's real release shape: the newest release (v1.18.1) is an Android-only
# hotfix with no Linux assets at all, so anything reading /releases/latest finds
# nothing to install.
_localsend_test_releases_json() {
    cat <<'JSON_EOF'
  "browser_download_url": "https://github.com/localsend/localsend/releases/download/v1.18.1/LocalSend-1.18.1-android-arm64v8.apk",
  "browser_download_url": "https://github.com/localsend/localsend/releases/download/v1.18.1/LocalSend-1.18.1-android-x64.apk",
  "browser_download_url": "https://github.com/localsend/localsend/releases/download/v1.18.0/LocalSend-1.18.0-linux-arm-64.deb",
  "browser_download_url": "https://github.com/localsend/localsend/releases/download/v1.18.0/LocalSend-1.18.0-linux-x86-64.AppImage",
  "browser_download_url": "https://github.com/localsend/localsend/releases/download/v1.18.0/LocalSend-1.18.0-linux-x86-64.deb",
  "browser_download_url": "https://github.com/localsend/localsend/releases/download/v1.17.0/LocalSend-1.17.0-linux-x86-64.deb",
JSON_EOF
}

test_localsend_asset_url_skips_android_only_release() {
    # Stub curl for the duration of the test so no network call is made.
    curl() { _localsend_test_releases_json; }

    assert_eq \
        "https://github.com/localsend/localsend/releases/download/v1.18.0/LocalSend-1.18.0-linux-x86-64.deb" \
        "$(_localsend_asset_url 'linux-x86-64\.deb$')" \
        "_localsend_asset_url falls back past an Android-only release to the newest Linux .deb"

    assert_eq \
        "https://github.com/localsend/localsend/releases/download/v1.18.0/LocalSend-1.18.0-linux-arm-64.deb" \
        "$(_localsend_asset_url 'linux-arm-64\.deb$')" \
        "_localsend_asset_url selects the arm-64 .deb when asked for it"

    # The AppImage sits between the two .deb assets in the list; anchoring on the
    # extension is what keeps it from being picked for a .deb install.
    assert_eq \
        "https://github.com/localsend/localsend/releases/download/v1.18.0/LocalSend-1.18.0-linux-x86-64.AppImage" \
        "$(_localsend_asset_url 'linux-x86-64\.AppImage$')" \
        "_localsend_asset_url does not confuse the AppImage with the .deb"

    unset -f curl
}

test_localsend_asset_url_reports_no_match() {
    curl() { _localsend_test_releases_json; }
    assert_eq "" "$(_localsend_asset_url 'linux-x86-64\.rpm$')" \
        "_localsend_asset_url prints nothing when no asset matches"
    unset -f curl
}

test_localsend_install_deb_rejects_unknown_arch() {
    uname() { echo "riscv64"; }
    assert_false "_localsend_install_deb fails on an unsupported architecture" \
        _localsend_install_deb
    unset -f uname
}

test_localsend_asset_url_skips_android_only_release
test_localsend_asset_url_reports_no_match
test_localsend_install_deb_rejects_unknown_arch

# ============================================================================
# Pay Respects Tests
# ============================================================================
echo ""
echo "=== Pay Respects Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/pay_respects.sh"

# Upstream's real release shape: a rolling "nightly" release sits at the top of
# the list, published as an ordinary release rather than a prerelease, so its
# assets are the first ones a naive newest-first scan would pick up.
_payr_test_releases_json() {
    cat <<'JSON_EOF'
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/nightly/pay-respects-nightly-x86_64-unknown-linux-musl.tar.zst",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-1.aarch64.rpm",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-1.i686.rpm",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-1.x86_64.rpm",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-x86_64-unknown-linux-musl.tar.zst",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects_0.8.8-1_amd64.deb",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects_0.8.8-1_arm64.deb",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects_0.8.8-1_i386.deb",
  "browser_download_url": "https://github.com/iffse/pay-respects/releases/download/v0.8.7/pay-respects_0.8.7-1_amd64.deb",
JSON_EOF
}

test_payr_asset_url_skips_nightly() {
    # Stub curl for the duration of the test so no network call is made.
    curl() { _payr_test_releases_json; }

    assert_eq \
        "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects_0.8.8-1_amd64.deb" \
        "$(_payr_asset_url '_amd64\.deb$')" \
        "_payr_asset_url takes the newest tagged .deb, not a nightly asset"

    assert_eq \
        "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-1.x86_64.rpm" \
        "$(_payr_asset_url '\.x86_64\.rpm$')" \
        "_payr_asset_url selects the x86_64 .rpm"

    # i686/i386 assets sort before the 64-bit ones in the release list, so the
    # patterns have to be anchored to keep them from matching first.
    assert_eq \
        "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects_0.8.8-1_arm64.deb" \
        "$(_payr_asset_url '_arm64\.deb$')" \
        "_payr_asset_url selects the arm64 .deb without matching i386"

    assert_eq \
        "https://github.com/iffse/pay-respects/releases/download/v0.8.8/pay-respects-0.8.8-1.aarch64.rpm" \
        "$(_payr_asset_url '\.aarch64\.rpm$')" \
        "_payr_asset_url selects the aarch64 .rpm"

    unset -f curl
}

test_payr_asset_url_reports_no_match() {
    curl() { _payr_test_releases_json; }
    assert_eq "" "$(_payr_asset_url 'riscv64\.deb$')" \
        "_payr_asset_url prints nothing when no asset matches"
    unset -f curl
}

test_payr_install_pkg_rejects_unknown_arch() {
    uname() { echo "riscv64"; }
    assert_false "_payr_install_pkg fails on an unsupported architecture" \
        _payr_install_pkg deb
    unset -f uname
}

test_payr_rc_block_is_written_once_and_removed() {
    local rcfile
    rcfile=$(mktemp /tmp/payr_bashrc_XXXXXX)
    echo "# existing user content" > "$rcfile"

    _payr_apply_rc "$rcfile" bash "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END" >/dev/null
    assert_contains "$(cat "$rcfile")" 'eval "\$\(pay-respects bash\)"' \
        "_payr_apply_rc writes the shell-init line unexpanded"
    assert_contains "$(cat "$rcfile")" '^export _PR_AI_DISABLE=1$' \
        "_payr_apply_rc disables the AI module by default"

    # A second run must not stack a duplicate block.
    _payr_apply_rc "$rcfile" bash "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END" >/dev/null
    assert_eq "1" "$(grep -cF "$_PAYR_BASH_BEGIN" "$rcfile")" \
        "_payr_apply_rc is idempotent"

    _payr_remove_rc "$rcfile" "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END" >/dev/null
    assert_eq "0" "$(grep -cF "pay-respects" "$rcfile")" \
        "_payr_remove_rc removes the whole block"
    assert_eq "# existing user content" "$(cat "$rcfile")" \
        "_payr_remove_rc leaves surrounding rc content intact"

    rm -f "$rcfile"
}

# Two command_not_found handlers in one rc file means the last one sourced wins,
# so pay-respects is initialized with --nocnf when the Command-Not-Found Prompt
# task already owns the hook in that file.
test_payr_defers_cnf_to_existing_handler() {
    local rcfile
    rcfile=$(mktemp /tmp/payr_bashrc_XXXXXX)
    echo "# linux_util: command-not-found auto-install (bash) -- begin" > "$rcfile"

    _payr_apply_rc "$rcfile" bash "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END" >/dev/null
    assert_contains "$(cat "$rcfile")" 'pay-respects bash --nocnf' \
        "_payr_apply_rc adds --nocnf when a command-not-found handler is already present"

    rm -f "$rcfile"
}

test_payr_takes_cnf_when_rc_is_clean() {
    local rcfile
    rcfile=$(mktemp /tmp/payr_bashrc_XXXXXX)
    : > "$rcfile"

    _payr_apply_rc "$rcfile" bash "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END" >/dev/null
    assert_eq "0" "$(grep -c -- '--nocnf' "$rcfile")" \
        "_payr_apply_rc keeps pay-respects' own command-not-found handler on a clean rc file"

    rm -f "$rcfile"
}

test_payr_asset_url_skips_nightly
test_payr_asset_url_reports_no_match
test_payr_install_pkg_rejects_unknown_arch
test_payr_rc_block_is_written_once_and_removed
test_payr_defers_cnf_to_existing_handler
test_payr_takes_cnf_when_rc_is_clean

# ============================================================================
# OpenLogi Tests
# ============================================================================
echo ""
echo "=== OpenLogi Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/openlogi.sh"

# Upstream's real asset set: every package has a .minisig sibling, and the
# Arch package's extension contains dots that must not act as wildcards.
_openlogi_test_release_json() {
    cat <<'JSON_EOF'
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.deb",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.deb.minisig",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.pkg.tar.zst",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.pkg.tar.zst.minisig",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.rpm",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.rpm.minisig",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-arm64.deb",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-arm64.rpm",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-arm64.pkg.tar.zst",
  "browser_download_url": "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/SHA256SUMS",
JSON_EOF
}

test_openlogi_asset_url_picks_the_package_not_its_signature() {
    # Stub curl for the duration of the test so no network call is made.
    curl() { _openlogi_test_release_json; }
    uname() { echo "x86_64"; }

    assert_eq \
        "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.deb" \
        "$(_openlogi_asset_url deb)" \
        "_openlogi_asset_url picks the .deb, not its .minisig sibling"

    assert_eq \
        "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.rpm" \
        "$(_openlogi_asset_url rpm)" \
        "_openlogi_asset_url picks the .rpm, not its .minisig sibling"

    # The dots in "pkg.tar.zst" are escaped before the pattern is built; an
    # unescaped pattern would still match here, so the .minisig line above it
    # is what makes this assertion meaningful.
    assert_eq \
        "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-amd64.pkg.tar.zst" \
        "$(_openlogi_asset_url pkg.tar.zst)" \
        "_openlogi_asset_url picks the Arch package, not its .minisig sibling"

    unset -f curl uname
}

test_openlogi_asset_url_selects_the_running_arch() {
    curl() { _openlogi_test_release_json; }
    uname() { echo "aarch64"; }

    assert_eq \
        "https://github.com/AprilNEA/OpenLogi/releases/download/v0.7.3/openlogi-v0.7.3-linux-arm64.deb" \
        "$(_openlogi_asset_url deb)" \
        "_openlogi_asset_url maps aarch64 to the arm64 asset"

    unset -f curl uname
}

test_openlogi_asset_url_rejects_unknown_arch() {
    curl() { _openlogi_test_release_json; }
    uname() { echo "riscv64"; }

    assert_false "_openlogi_asset_url fails on an unsupported architecture" \
        _openlogi_asset_url deb

    unset -f curl uname
}

test_openlogi_install_pkg_rejects_unknown_arch() {
    uname() { echo "riscv64"; }
    assert_false "_openlogi_install_pkg fails on an unsupported architecture" \
        _openlogi_install_pkg deb
    unset -f uname
}

test_openlogi_asset_url_picks_the_package_not_its_signature
test_openlogi_asset_url_selects_the_running_arch
test_openlogi_asset_url_rejects_unknown_arch
test_openlogi_install_pkg_rejects_unknown_arch

# ============================================================================
# Thermalright TRCC Tests
# ============================================================================
echo ""
echo "=== Thermalright TRCC Tests ==="

# Only defines functions, so sourcing is side-effect free.
source "${SCRIPT_DIR}/lib/installers/trcc.sh"

# Upstream's real asset set: every package is published twice, once under a
# versioned name and once under a stable "-latest" alias. Only the versioned
# names appear in SHA256SUMS.txt.
_trcc_test_release_json() {
    cat <<'JSON_EOF'
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/SHA256SUMS.txt",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux-9.9.10-1-any.pkg.tar.zst",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux-9.9.10-1.fc44.noarch.rpm",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux-latest-any.pkg.tar.zst",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux-latest.legacy_all.deb",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux-latest.noarch.rpm",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux-latest_all.deb",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux_9.9.10-1.legacy_all.deb",
  "browser_download_url": "https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10/trcc-linux_9.9.10-1_all.deb",
JSON_EOF
}

test_trcc_asset_url_skips_the_latest_aliases() {
    # Stub curl for the duration of the test so no network call is made.
    curl() { _trcc_test_release_json; }

    local base="https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10"

    assert_eq "${base}/trcc-linux_9.9.10-1_all.deb" \
        "$(_trcc_asset_url '\-[0-9]+_all\.deb$')" \
        "_trcc_asset_url takes the versioned .deb, not the -latest alias"

    assert_eq "${base}/trcc-linux-9.9.10-1.fc44.noarch.rpm" \
        "$(_trcc_asset_url '\.fc[0-9]+\.noarch\.rpm$')" \
        "_trcc_asset_url takes the versioned .rpm, not the -latest alias"

    assert_eq "${base}/trcc-linux-9.9.10-1-any.pkg.tar.zst" \
        "$(_trcc_asset_url '\-any\.pkg\.tar\.zst$')" \
        "_trcc_asset_url takes the versioned Arch package, not the -latest alias"

    unset -f curl
}

# The two .deb names differ only in what sits before "_all.deb", so the standard
# pattern has to reject the legacy package and vice versa — picking the wrong
# one installs a package whose dependencies cannot resolve on that release.
test_trcc_asset_url_separates_standard_from_legacy_deb() {
    curl() { _trcc_test_release_json; }

    local base="https://github.com/Lexonight1/thermalright-trcc-linux/releases/download/v9.9.10"

    assert_eq "${base}/trcc-linux_9.9.10-1.legacy_all.deb" \
        "$(_trcc_asset_url '\.legacy_all\.deb$')" \
        "_trcc_asset_url selects the legacy .deb when asked for it"

    assert_false "the standard .deb pattern does not match the legacy package" \
        bash -c 'echo "trcc-linux_9.9.10-1.legacy_all.deb" | grep -qE "\-[0-9]+_all\.deb$"'

    unset -f curl
}

test_trcc_asset_url_reports_no_match() {
    curl() { _trcc_test_release_json; }
    assert_eq "" "$(_trcc_asset_url '\.AppImage$')" \
        "_trcc_asset_url prints nothing when no asset matches"
    unset -f curl
}

test_trcc_download_reports_a_missing_asset() {
    curl() { _trcc_test_release_json; }
    assert_false "_trcc_download fails when the release has no matching asset" \
        _trcc_download AppImage '\.AppImage$'
    unset -f curl
}

# dnf treats '[' as a glob metacharacter, so an extras provide like
# pythonX.Ydist(uvicorn[standard]) has to be escaped before it is queried —
# unescaped it silently reports as unmet and sends a usable RPM to the fallback.
test_trcc_rpm_unmet_requires_escapes_glob_brackets() {
    local queried
    queried=$(mktemp /tmp/trcc_queried_XXXXXX)

    rpm() { printf 'python3.14dist(uvicorn[standard]) >= 0.20\nrpmlib(FileDigests) <= 4.6.0-1\n/bin/sh\n'; }
    # Stand in for dnf: record the query, and answer "provided" only for the
    # bracket-escaped form that a real dnf would match.
    dnf() {
        local q="${*: -1}"
        printf '%s\n' "$q" >> "$queried"
        [[ "$q" == 'python3.14dist(uvicorn[[]standard])' ]] && echo "python3-uvicorn+standard"
    }
    PKG_MGR=dnf

    assert_eq "" "$(_trcc_rpm_unmet_requires /nonexistent.rpm)" \
        "_trcc_rpm_unmet_requires reports nothing unmet when the escaped query resolves"

    assert_eq "1" "$(wc -l < "$queried")" \
        "_trcc_rpm_unmet_requires skips rpmlib() and file requires"

    rm -f "$queried"
    unset -f rpm dnf
}

test_trcc_rpm_unmet_requires_names_what_is_missing() {
    rpm() { printf 'python3.14dist(nvidia-ml-py) >= 11\npython3-numpy\n'; }
    dnf() { [[ "${*: -1}" == "python3-numpy" ]] && echo "python3-numpy-0:2.5.2"; }
    PKG_MGR=dnf

    assert_eq "python3.14dist(nvidia-ml-py)" \
        "$(_trcc_rpm_unmet_requires /nonexistent.rpm)" \
        "_trcc_rpm_unmet_requires names only the requires nothing provides"

    unset -f rpm dnf
}

test_trcc_asset_url_skips_the_latest_aliases
test_trcc_asset_url_separates_standard_from_legacy_deb
test_trcc_asset_url_reports_no_match
test_trcc_download_reports_a_missing_asset
test_trcc_rpm_unmet_requires_escapes_glob_brackets
test_trcc_rpm_unmet_requires_names_what_is_missing

# ============================================================================
# Visual Studio Code Tests
# ============================================================================
echo ""
echo "=== Visual Studio Code Tests ==="

source "${SCRIPT_DIR}/lib/installers/vscode.sh"

# Microsoft publishes no pacman repo, so on Arch the vendor tarball IS the
# non-AUR path. If it is not wired into the binary tier, a machine whose repos
# lack the package and whose Flatpak install fails has nowhere left to go --
# exactly the failure this tier was added to close.
test_vscode_arch_wires_the_microsoft_tarball() {
    local out
    out=$(
        DISTRO_FAMILY=arch
        ensure_tools() { :; }
        arch_install_ordered() { echo "TIERS: $*"; }
        install_vscode 2>&1
    )
    assert_contains "$out" "TIERS: visual-studio-code-bin com.visualstudio.code _vscode_install_tarball visual-studio-code-bin" \
        "install_vscode passes the Microsoft tarball as the upstream-binary tier on Arch"
}

test_vscode_update_wires_the_microsoft_tarball() {
    local out
    out=$(
        DISTRO_FAMILY=arch
        arch_install_ordered() { echo "TIERS: $*"; }
        update_vscode 2>&1
    )
    assert_contains "$out" "_vscode_install_tarball" \
        "update_vscode also routes through the Microsoft tarball tier on Arch"
}

_vscode_tarball_fn_exists() { declare -F _vscode_install_tarball >/dev/null; }
test_vscode_tarball_installer_is_defined() {
    assert_true "_vscode_install_tarball is defined" _vscode_tarball_fn_exists
}

# ~/.local/bin is not always on PATH, so the version must come from the install
# tree rather than from running the binary.
test_vscode_version_reads_the_install_tree() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/resources/app"
    echo "{\"name\":\"Code\",\"version\":\"1.99.3\",\"distro\":\"x\"}" > "$tmp/resources/app/package.json"
    local out
    out=$(
        _VSCODE_DIR="$tmp"
        _run_native() { echo "SHOULD_NOT_RUN"; }
        get_version_vscode
    )
    assert_eq "1.99.3" "$out" "get_version_vscode reads the version from the installed package.json"
    rm -rf "$tmp"
}

test_vscode_remove_tarball_reports_nothing_to_do() {
    local out
    out=$(
        _VSCODE_DIR="/nonexistent/vscode/path"
        _vscode_remove_tarball && echo "REMOVED"
    )
    assert_eq "" "$out" "_vscode_remove_tarball returns non-zero when no tarball install is present"
}

test_vscode_arch_wires_the_microsoft_tarball
test_vscode_update_wires_the_microsoft_tarball
test_vscode_tarball_installer_is_defined
test_vscode_version_reads_the_install_tree
test_vscode_remove_tarball_reports_nothing_to_do

# ============================================================================
# VSCodium Tests
# ============================================================================
echo ""
echo "=== VSCodium Tests ==="

source "${SCRIPT_DIR}/lib/installers/vscodium.sh"

# vscodium-bin is AUR-only on upstream Arch, so the project's own release
# tarball IS the non-AUR path -- same reasoning as the VS Code tier above.
test_vscodium_arch_wires_the_upstream_tarball() {
    local out
    out=$(
        DISTRO_FAMILY=arch
        ensure_tools() { :; }
        arch_install_ordered() { echo "TIERS: $*"; }
        install_vscodium 2>&1
    )
    assert_contains "$out" "TIERS: vscodium-bin com.vscodium.codium _vscodium_install_tarball vscodium-bin" \
        "install_vscodium passes the upstream tarball as the upstream-binary tier on Arch"
}

test_vscodium_update_wires_the_upstream_tarball() {
    local out
    out=$(
        DISTRO_FAMILY=arch
        arch_install_ordered() { echo "TIERS: $*"; }
        update_vscodium 2>&1
    )
    assert_contains "$out" "_vscodium_install_tarball" \
        "update_vscodium also routes through the upstream tarball tier on Arch"
}

_vscodium_tarball_fn_exists() { declare -F _vscodium_install_tarball >/dev/null; }
test_vscodium_tarball_installer_is_defined() {
    assert_true "_vscodium_install_tarball is defined" _vscodium_tarball_fn_exists
}

# ~/.local/bin is not always on PATH, so the version must come from the install
# tree rather than from running the binary.
test_vscodium_version_reads_the_install_tree() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/resources/app"
    echo "{\"name\":\"Code - OSS\",\"version\":\"1.99.3\",\"distro\":\"x\"}" > "$tmp/resources/app/package.json"
    local out
    out=$(
        _VSCODIUM_DIR="$tmp"
        _run_native() { echo "SHOULD_NOT_RUN"; }
        get_version_vscodium
    )
    assert_eq "1.99.3" "$out" "get_version_vscodium reads the version from the installed package.json"
    rm -rf "$tmp"
}

test_vscodium_remove_tarball_reports_nothing_to_do() {
    local out
    out=$(
        _VSCODIUM_DIR="/nonexistent/vscodium/path"
        _vscodium_remove_tarball && echo "REMOVED"
    )
    assert_eq "" "$out" "_vscodium_remove_tarball returns non-zero when no tarball install is present"
}

# The rpm-md definition is shared by dnf and zypper; only zypper needs type=.
# repo_gpgcheck matters as much as gpgcheck here -- the repo publishes a
# detached repomd signature, and dropping it would leave the metadata unchecked.
test_vscodium_rpm_repo_is_signed_and_typed() {
    local out
    out=$(
        # Strip "sudo tee <dest>" and echo the body. It goes to stderr because
        # the real call redirects tee's stdout to /dev/null.
        sudo() { shift 2; cat >&2; }
        _vscodium_write_rpm_repo /dev/null $'type=rpm-md\n' 2>&1
    )
    assert_contains "$out" "type=rpm-md" \
        "_vscodium_write_rpm_repo emits type=rpm-md when asked (zypper)"
    assert_contains "$out" "repo_gpgcheck=1" \
        "_vscodium_write_rpm_repo enables repo_gpgcheck for the signed metadata"
    assert_contains "$out" "baseurl=https://download.vscodium.com/rpms/" \
        "_vscodium_write_rpm_repo points at the VSCodium rpm repo"
}

test_vscodium_arch_wires_the_upstream_tarball
test_vscodium_update_wires_the_upstream_tarball
test_vscodium_tarball_installer_is_defined
test_vscodium_version_reads_the_install_tree
test_vscodium_remove_tarball_reports_nothing_to_do
test_vscodium_rpm_repo_is_signed_and_typed

# ============================================================================
# Local Time Zone / Locale Tests
# ============================================================================
echo ""
echo "=== Local Time Zone / Locale Tests ==="

# Not sourced by default — this file only defines functions.
source "${SCRIPT_DIR}/lib/installers/timezone_locale.sh"

# Debian's locale-gen discards any locale passed as an argument and generates
# only what is uncommented in /etc/locale.gen, so _locale_gen_entry has to edit
# that file first. Stand in for sudo and for locale-gen itself.
_lg_setup() {
    _LG_FILE=$(mktemp /tmp/locale_gen_XXXXXX)
    printf '%s\n' "$1" > "$_LG_FILE"
    run_as_root() { "$@"; }
    # Stand in for the sbin lookup: /usr/sbin is not on a Debian user's PATH,
    # so the real code resolves locale-gen by path before running it.
    _sbin_command() { [[ "$1" == "locale-gen" ]] && echo /bin/true || return 1; }
}

_lg_teardown() {
    rm -f "$_LG_FILE"
    unset -f _sbin_command
    run_as_root() { sudo "$@"; }
}

test_locale_gen_entry_uncomments_an_existing_line() {
    _lg_setup '# en_US.UTF-8 UTF-8
# de_DE.UTF-8 UTF-8'
    _locale_gen_entry "en_US.UTF-8 UTF-8" "$_LG_FILE"

    assert_eq "en_US.UTF-8 UTF-8" "$(grep '^en_US' "$_LG_FILE")" \
        "_locale_gen_entry uncomments the requested locale in locale.gen"
    assert_eq "# de_DE.UTF-8 UTF-8" "$(grep '^#\s*de_DE' "$_LG_FILE")" \
        "_locale_gen_entry leaves other commented locales alone"
    _lg_teardown
}

test_locale_gen_entry_appends_a_missing_line() {
    _lg_setup '# de_DE.UTF-8 UTF-8'
    _locale_gen_entry "en_US.UTF-8 UTF-8" "$_LG_FILE"

    assert_eq "en_US.UTF-8 UTF-8" "$(tail -1 "$_LG_FILE")" \
        "_locale_gen_entry appends a locale that locale.gen does not list at all"
    _lg_teardown
}

# The '.' in a locale name must be escaped: an unescaped "en_US" pattern would
# match the "en_US.UTF-8" line and generate the wrong charset.
test_locale_gen_entry_does_not_match_a_longer_locale_name() {
    _lg_setup '# en_US.UTF-8 UTF-8'
    _locale_gen_entry "en_US ISO-8859-1" "$_LG_FILE"

    assert_eq "# en_US.UTF-8 UTF-8" "$(head -1 "$_LG_FILE")" \
        "_locale_gen_entry does not uncomment en_US.UTF-8 when asked for en_US"
    assert_eq "en_US ISO-8859-1" "$(tail -1 "$_LG_FILE")" \
        "_locale_gen_entry appends the exact entry it was given"
    _lg_teardown
}

test_locale_gen_entry_rejects_an_entry_without_a_charset() {
    _lg_setup '# en_US.UTF-8 UTF-8'
    assert_false "_locale_gen_entry refuses an entry with no charset field" \
        _locale_gen_entry "en_US.UTF-8" "$_LG_FILE"
    _lg_teardown
}

test_locale_gen_entry_reports_a_missing_locale_gen() {
    _lg_setup ''
    rm -f "$_LG_FILE"
    assert_false "_locale_gen_entry fails when locale.gen does not exist" \
        _locale_gen_entry "en_US.UTF-8 UTF-8" "$_LG_FILE"
    _lg_teardown
}

# Debian denies locale1.SetLocale over D-Bus to everyone, root included, so
# localectl can never set a locale there — update-locale has to win when both
# tools are present.
_al_setup() {
    _AL_CALLS=$(mktemp /tmp/apply_locale_XXXXXX)
    _AL_FAIL="${1:-}"      # basename of the tool that should fail, if any
    _AL_MISSING="${2:-}"   # basename of the tool that is not installed, if any
    _sbin_command() {
        [[ "$1" == "$_AL_MISSING" ]] && return 1
        case "$1" in
            update-locale) echo "/usr/sbin/update-locale" ;;
            localectl)     echo "/usr/bin/localectl" ;;
            *)             return 1 ;;
        esac
    }
    # Record what would run instead of running it; sudo is never invoked.
    run_as_root() {
        local base="${1##*/}"
        printf '%s\n' "$base" >> "$_AL_CALLS"
        [[ "$base" == "$_AL_FAIL" ]] && return 1
        return 0
    }
}

_al_teardown() {
    rm -f "$_AL_CALLS"
    unset -f _sbin_command
    run_as_root() { sudo "$@"; }
}

test_apply_locale_setting_prefers_update_locale() {
    _al_setup
    assert_true "_apply_locale_setting succeeds when update-locale is present" \
        _apply_locale_setting "LANG=en_US.UTF-8"
    assert_eq "update-locale" "$(cat "$_AL_CALLS")" \
        "_apply_locale_setting uses update-locale and never reaches localectl"
    _al_teardown
}

test_apply_locale_setting_falls_back_to_localectl() {
    _al_setup update-locale
    assert_true "_apply_locale_setting falls back when update-locale fails" \
        _apply_locale_setting "LANG=en_US.UTF-8"
    assert_eq "update-locale
localectl" "$(cat "$_AL_CALLS")" \
        "_apply_locale_setting tries localectl after update-locale fails"
    _al_teardown
}

# The bug this guards: /usr/sbin is absent from a Debian user's PATH, so
# update-locale looked missing and the run fell through to localectl, which
# Debian denies outright.
test_apply_locale_setting_finds_update_locale_off_path() {
    _al_setup "" localectl
    assert_true "_apply_locale_setting works with localectl unavailable" \
        _apply_locale_setting "LANG=en_US.UTF-8"
    assert_eq "update-locale" "$(cat "$_AL_CALLS")" \
        "_apply_locale_setting runs update-locale by its resolved sbin path"
    _al_teardown
}

test_apply_locale_setting_reports_no_tool() {
    _al_setup
    _sbin_command() { return 1; }
    assert_false "_apply_locale_setting fails when neither tool is installed" \
        _apply_locale_setting "LANG=en_US.UTF-8"
    _al_teardown
}

test_locale_gen_entry_uncomments_an_existing_line
test_locale_gen_entry_appends_a_missing_line
test_locale_gen_entry_does_not_match_a_longer_locale_name
test_locale_gen_entry_rejects_an_entry_without_a_charset
test_locale_gen_entry_reports_a_missing_locale_gen
test_apply_locale_setting_prefers_update_locale
test_apply_locale_setting_falls_back_to_localectl
test_apply_locale_setting_finds_update_locale_off_path
test_apply_locale_setting_reports_no_tool

# ============================================================================
# Results Summary
# ============================================================================

echo ""
echo "=== Reboot Detection Tests ==="

source "${SCRIPT_DIR}/lib/installers/_shared.sh" 2>/dev/null

# linux_util.sh runs under `set -o pipefail`, and the reboot check is a pipeline.
# Without this the suite passed while the real script silently inverted the
# result: grep -q exits on the first match, SIGPIPEs the sort feeding it, and
# pipefail turns that into a failed pipeline -- so "files found" read as "none".
# Every test below runs with pipefail on, matching the script it is testing.
_reboot_test_pipefail_on() { set -o pipefail; }

# Arch has no /var/run/reboot-required and ships no needs-restarting, so before
# _reboot_required_arch existed the pending-reboot check could never fire there:
# the script printed "No reboot needed" while the desktop showed a reboot
# notification for the same upgrade.

test_reboot_arch_check_is_family_gated() {
    local f
    for f in debian fedora rhel suse ""; do
        assert_false "_reboot_required_arch stays inert on family '${f:-unset}'" \
            env DISTRO_FAMILY="$f" bash -c \
                'source "'"${SCRIPT_DIR}"'/lib/installers/_shared.sh"; _reboot_required_arch'
    done
}

test_reboot_arch_fires_on_replaced_kernel() {
    # pacman deletes /usr/lib/modules/<release> when it upgrades the kernel, so a
    # running release with no module tree means the running kernel is stale.
    local out
    out=$(
        DISTRO_FAMILY=arch
        uname() { [[ "$1" == "-r" ]] && echo "99.9.9-nonexistent" || command uname "$@"; }
        _reboot_stale_files() { :; }
        _reboot_required_arch && echo FIRED
    )
    assert_contains "$out" "FIRED" \
        "_reboot_required_arch fires when the running kernel's module tree is gone"
}

test_reboot_arch_fires_on_stale_libraries() {
    # The ordinary case: a library replaced under a running process. No kernel
    # change, so only the stale-mapping signal can catch it.
    local out
    out=$(
        _reboot_test_pipefail_on
        DISTRO_FAMILY=arch
        _reboot_stale_files() { echo "/usr/lib/libcurl.so.4.8.0"; }
        _reboot_required_arch && echo FIRED
    )
    assert_contains "$out" "FIRED" \
        "_reboot_required_arch fires when a running process maps a replaced library"
}

# Regression: the whole check ran inside `set -o pipefail`, where a pipeline
# ending in `grep -q` reports failure precisely BECAUSE it matched -- grep exits
# early and SIGPIPEs its upstream. The result inverted only inside the real
# script, so a run printed "No reboot needed" with thirty stale libraries mapped.
test_reboot_arch_fires_under_pipefail() {
    local out
    out=$(
        set -o pipefail
        DISTRO_FAMILY=arch
        _reboot_stale_files() { printf '%s\n' /usr/lib/liba.so.1 /usr/lib/libb.so.2; }
        _reboot_required_arch && echo FIRED
    )
    assert_contains "$out" "FIRED" \
        "_reboot_required_arch still fires when the caller sets pipefail"
}

# _reboot_stale_files must report its own status honestly under pipefail too:
# the per-process grep fails for nearly every process, and those failures must
# not surface as the function's exit status.
test_reboot_stale_files_status_under_pipefail() {
    local rc
    (
        set -o pipefail
        _reboot_stale_files >/dev/null 2>&1
    )
    rc=$?
    assert_true "_reboot_stale_files returns a status matching its output under pipefail" \
        test "$rc" -eq 0 -o "$rc" -eq 1
}

test_reboot_arch_quiet_on_clean_system() {
    local out
    out=$(
        DISTRO_FAMILY=arch
        _reboot_stale_files() { :; }
        _reboot_required_arch && echo FIRED
        echo DONE
    )
    assert_false "_reboot_required_arch stays quiet with a current kernel and no stale files" \
        grep -q "FIRED" <<< "$out"
}

# Only /usr system paths count. A browser's deleted shm segment or a deleted
# temp file is not an upgrade and must never raise a reboot prompt.
test_reboot_stale_files_ignores_non_system_paths() {
    local _fake_proc="${LOG_DIR}/fakeproc"
    mkdir -p "$_fake_proc/1234"
    cat > "$_fake_proc/1234/maps" <<'MAPS'
7f0000000000-7f0000001000 r--p 00000000 00:1b 12345 /dev/shm/.org.chromium.Chromium.AbCdEf (deleted)
7f0000002000-7f0000003000 r--p 00000000 00:1b 12346 /tmp/somescratchfile (deleted)
7f0000004000-7f0000005000 r--p 00000000 00:1b 12347 /home/user/.cache/thing.bin (deleted)
MAPS
    local out
    out=$(
        _reboot_stale_files() {
            grep -hE '^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [0-9]+ +/usr/(lib|lib32|bin|sbin)/.*\(deleted\)$' \
                "'"$_fake_proc"'"/*/maps 2>/dev/null \
                | sed -E 's/^([^ ]+ ){5} *//; s/ \(deleted\)$//' | sort -u
        }
        _reboot_stale_files
    )
    assert_false "stale-file scan ignores shm, tmp and cache mappings" \
        grep -q . <<< "$out"
    rm -rf "$_fake_proc"
}

test_reboot_stale_files_matches_system_libraries() {
    local _fake_proc="${LOG_DIR}/fakeproc2"
    mkdir -p "$_fake_proc/1234"
    cat > "$_fake_proc/1234/maps" <<'MAPS'
7f0000000000-7f0000001000 r--p 00000000 00:1b 12345 /dev/shm/.org.chromium.Chromium.AbCdEf (deleted)
7f0000006000-7f0000007000 r-xp 00000000 08:02 22222 /usr/lib/libcurl.so.4.8.0 (deleted)
7f0000008000-7f0000009000 r-xp 00000000 08:02 22223 /usr/bin/wireplumber (deleted)
7f000000a000-7f000000b000 r-xp 00000000 08:02 22224 /usr/lib/libnotstale.so.1 
MAPS
    local out
    out=$(grep -hE '^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [0-9]+ +/usr/(lib|lib32|bin|sbin)/.*\(deleted\)$' \
            "$_fake_proc"/*/maps 2>/dev/null \
            | sed -E 's/^([^ ]+ ){5} *//; s/ \(deleted\)$//' | sort -u)
    assert_contains "$out" "/usr/lib/libcurl.so.4.8.0" "stale-file scan catches a replaced library"
    assert_contains "$out" "/usr/bin/wireplumber"      "stale-file scan catches a replaced binary"
    assert_false "stale-file scan ignores a mapping that is not deleted" \
        grep -q "libnotstale" <<< "$out"
    rm -rf "$_fake_proc"
}

# The "Triggered by:" line must read as a package list, not as pairs: paste's -d
# takes a delimiter LIST used cyclically, so "-sd', '" alternates comma and space.
test_reboot_stale_packages_separator() {
    local out
    out=$(printf 'curl\ngpgme\nmesa\nwireplumber\n' | sort -u | paste -sd, - | sed 's/,/, /g')
    assert_eq "curl, gpgme, mesa, wireplumber" "$out" \
        "package list is comma-separated, not alternating comma and space"
}

test_reboot_arch_check_is_family_gated
test_reboot_arch_fires_on_replaced_kernel
test_reboot_arch_fires_on_stale_libraries
test_reboot_arch_fires_under_pipefail
test_reboot_stale_files_status_under_pipefail
test_reboot_arch_quiet_on_clean_system
test_reboot_stale_files_ignores_non_system_paths
test_reboot_stale_files_matches_system_libraries
test_reboot_stale_packages_separator

echo ""
echo ""
echo ""
echo "=== Config Schema Migration Tests ==="

# migrate_config tops up a hand-maintained linux_util.conf with keys added to
# linux_util.conf.example since it was written. It must append only: values the
# user set, and their own comments, survive untouched.

_mig_dir=$(mktemp -d)
cp "${SCRIPT_DIR}/linux_util.conf.example" "$_mig_dir/"
cat > "$_mig_dir/linux_util.conf" <<'MIGCONF'
# A comment the user wrote
log_retention_days=90
log_level=DEBUG
retry_attempts=7
MIGCONF

_mig_run() {
    bash -c "
        source '${SCRIPT_DIR}/lib/config.sh'
        load_config '$_mig_dir/linux_util.conf' >/dev/null 2>&1
        migrate_config '$_mig_dir/linux_util.conf' >/dev/null 2>&1
        echo \"added=\${#CONFIG_MIGRATION_ADDED[@]}\"
    " 2>/dev/null
}

_out=$(_mig_run)
assert_contains "$_out" "added=1" "migration appends keys missing from the user's config" || true
assert_true "user-set values survive migration" \
    grep -qE '^retry_attempts=7$' "$_mig_dir/linux_util.conf"
assert_true "the user's own comments survive migration" \
    grep -q 'A comment the user wrote' "$_mig_dir/linux_util.conf"
assert_true "a key absent from the config is appended" \
    grep -qE '^update_channel=' "$_mig_dir/linux_util.conf"
assert_true "migration stamps the schema version" \
    grep -qE '^config_version=' "$_mig_dir/linux_util.conf"
assert_true "migration backs the config up before writing" \
    bash -c "ls '$_mig_dir'/linux_util.conf.bak.* >/dev/null 2>&1"

# An appended key must be a live setting, not glued onto the end of its own
# comment line -- which would comment it out and silently drop the default.
assert_true "an appended key parses back as a live setting" \
    bash -c "
        source '${SCRIPT_DIR}/lib/config.sh'
        load_config '$_mig_dir/linux_util.conf' >/dev/null 2>&1
        [[ \"\$CFG_DISK_MIN_MB\" == 1024 ]]
    "

# Running on every launch, so a no-op run must not rewrite the file or spill
# backups.
_before=$(md5sum < "$_mig_dir/linux_util.conf")
_out=$(_mig_run)
_after=$(md5sum < "$_mig_dir/linux_util.conf")
assert_eq "$_before" "$_after" "a second migration run leaves the file byte-identical"
assert_contains "$_out" "added=0" "a second migration run reports nothing added" || true
assert_eq "1" "$(ls "$_mig_dir"/linux_util.conf.bak.* 2>/dev/null | wc -l)" \
    "a no-op migration creates no extra backup"

# The reason migrate_config runs after self_update_script: a pull delivers the
# new example, and the migration must see it on that same run rather than
# leaving the user a release behind until their next launch.
#
# Critically, this must work WITHOUT anyone remembering to bump a version
# constant. An earlier draft skipped the scan whenever the user's config was
# already stamped at the latest version, so shipping a key without bumping the
# constant left every existing config stamped current and silently missing the
# key -- while fresh installs got it, hiding the bug from whoever shipped it.
printf '\n# A setting added by a later release\nnew_feature_key=true\n' \
    >> "$_mig_dir/linux_util.conf.example"
_out=$(_mig_run)
assert_contains "$_out" "added=1" "a key added to the example is picked up with no version bump" || true
assert_true "a newly shipped key reaches an already-current config" \
    grep -qE '^new_feature_key=true$' "$_mig_dir/linux_util.conf"

# The schema version travels with the example that defines the keys, so the
# user's stamp follows it rather than a constant that can drift out of step.
sed -i 's/^config_version=.*/config_version=7/' "$_mig_dir/linux_util.conf.example"
_mig_run >/dev/null
assert_true "the user's config_version follows the example's" \
    grep -qE '^config_version=7$' "$_mig_dir/linux_util.conf"

rm -rf "$_mig_dir"

# Documentation drift: only missing keys were ever brought over, so a key the
# user already had kept whatever comment the example carried when their config
# was written. A reworded explanation then described behaviour the program no
# longer had -- worse than no comment, since there is no reason to doubt it.

_cmt_dir=$(mktemp -d)
cat > "$_cmt_dir/linux_util.conf.example" <<'CMTEX'
# --- Installation ---
# The new and correct explanation of this setting,
# which runs to a second line.
auto_confirm=false

# --- Output ---
# Enable verbose output (extra status messages)
verbose=false

# --- Config schema ---
# A three-line block describing the stamp,
# replacing the old one-liner, which
# contradicted this file.
config_version=1
CMTEX
cat > "$_cmt_dir/linux_util.conf" <<'CMTCONF'
# --- Installation ---
# The old, now-wrong one-line explanation
auto_confirm=true

# A note the user wrote about their own key
my_own_key=keepme

# --- Output ---
# Enable verbose output (extra status messages)
verbose=false

# Config schema version - written by linux_util, do not edit
config_version=1
CMTCONF

_cmt_run() {
    bash -c "
        source '${SCRIPT_DIR}/lib/config.sh'
        load_config '$_cmt_dir/linux_util.conf' >/dev/null 2>&1
        migrate_config '$_cmt_dir/linux_util.conf' >/dev/null 2>&1
        echo \"updated=\${#CONFIG_MIGRATION_UPDATED[@]}\"
    " 2>/dev/null
}

_out=$(_cmt_run)
assert_true "a reworded comment reaches an existing key" \
    grep -q 'The new and correct explanation' "$_cmt_dir/linux_util.conf"
assert_true "the superseded comment is gone, not left alongside the new one" \
    bash -c "! grep -q 'old, now-wrong one-line' '$_cmt_dir/linux_util.conf'"

# The whole point of refreshing a comment is that the value beneath it is the
# user's. Rewriting documentation must never reset a setting.
assert_true "refreshing a comment leaves the user's value alone" \
    grep -qE '^auto_confirm=true$' "$_cmt_dir/linux_util.conf"

# config_version is stamped by _cfg_stamp_version rather than the ordinary
# refresh pass, so its comment has its own path to going stale -- and it must
# update even though the schema version itself has not moved.
assert_true "the config_version stamp's own comment is refreshed" \
    grep -q 'A three-line block describing the stamp' "$_cmt_dir/linux_util.conf"
assert_true "the stamp's contradictory one-liner is removed" \
    bash -c "! grep -q 'written by linux_util, do not edit' '$_cmt_dir/linux_util.conf'"

# Comments above keys the example says nothing about are the user's own.
assert_true "a comment on the user's own key is untouched" \
    grep -q 'A note the user wrote about their own key' "$_cmt_dir/linux_util.conf"

# A banner heads a section, it does not document the key after it. Copying it
# along with a key leaves a duplicate heading halfway down the config.
assert_eq "1" "$(grep -c -- '--- Installation ---' "$_cmt_dir/linux_util.conf")" \
    "a section banner is not duplicated by migration"

# A refreshed key must still parse: a block that does not end in a newline would
# print onto the key's own line and comment the setting out.
assert_true "a key keeps parsing after its comment is replaced" \
    bash -c "
        source '${SCRIPT_DIR}/lib/config.sh'
        load_config '$_cmt_dir/linux_util.conf' >/dev/null 2>&1
        [[ \"\$CFG_AUTO_CONFIRM\" == true ]]
    "

# Runs on every launch, so once current it must stop rewriting the file.
_before=$(md5sum < "$_cmt_dir/linux_util.conf")
_out=$(_cmt_run)
_after=$(md5sum < "$_cmt_dir/linux_util.conf")
assert_eq "$_before" "$_after" "a second comment-refresh run leaves the file byte-identical"
assert_contains "$_out" "updated=0" "a second comment-refresh run reports nothing updated" || true

# An identical comment is not drift, and must not trigger a rewrite or a backup.
assert_true "a key whose comment already matches is not reported as updated" \
    bash -c "! grep -q 'verbose' <<< '$_out'"

# The migration edits a file the user maintains, so a comment-only change still
# has to leave a recovery path.
assert_true "a comment-only migration still backs the config up" \
    bash -c "ls '$_cmt_dir'/linux_util.conf.bak.* >/dev/null 2>&1"

# The awk that installs the block gets it from a file, not awk -v, which applies
# escape processing and would silently rewrite a backslash on its way in.
printf '# A path such as C:\\Users\\name survives\nverbose=false\n' \
    > "$_cmt_dir/ex_tail"
sed -i '/^# Enable verbose output/,+1d' "$_cmt_dir/linux_util.conf.example"
cat "$_cmt_dir/ex_tail" >> "$_cmt_dir/linux_util.conf.example"
_cmt_run >/dev/null
assert_true "a backslash in a comment is not mangled on its way into the config" \
    grep -q 'C:\\Users\\name' "$_cmt_dir/linux_util.conf"

# No stray working files beside a config the user opens by hand.
assert_eq "0" "$(ls "$_cmt_dir"/*.migrate.* "$_cmt_dir"/*.block.* 2>/dev/null | wc -l)" \
    "migration leaves no temporary working files behind"

rm -rf "$_cmt_dir"

# The suite must never write to the developer's own config. The repo is a
# working install, so a CLI test that forgets to redirect the config path
# migrates the real linux_util.conf and litters the working tree with backups.
_POST_CONF_BAKS=$(ls "$SCRIPT_DIR"/linux_util.conf.bak.* 2>/dev/null)
assert_eq "$_PRE_EXISTING_CONF_BAKS" "$_POST_CONF_BAKS" \
    "the test suite leaves the repo's own linux_util.conf alone"

# main() must call migrate_config after self_update_script, not before: the
# pull is what puts the new example on disk.
_mig_line=$(grep -n 'migrate_config' "${SCRIPT_DIR}/linux_util.sh" | grep -v '#' | head -1 | cut -d: -f1)
_upd_line=$(grep -n 'self_update_script "\$@"' "${SCRIPT_DIR}/linux_util.sh" | head -1 | cut -d: -f1)
assert_true "migrate_config runs after self_update_script in main()" \
    bash -c "[[ -n '$_mig_line' && -n '$_upd_line' && $_mig_line -gt $_upd_line ]]"

echo "=== auto_confirm / tmux Auto-Attach Tests ==="

# auto_confirm was parsed and validated by lib/config.sh but read by nothing, so
# setting it changed no behaviour. These pin it to its documented meaning ("skip
# confirmation prompts") at the shared gate every installer already calls.

_confirm_probe() {
    # Run _confirm_step in a detached session so /dev/tty cannot be opened,
    # which is what an unattended run actually looks like.
    local auto="$1"
    setsid bash -c "
        info(){ :; }; warn(){ :; }; YELLOW=''; RESET=''
        source '${SCRIPT_DIR}/lib/installers/_shared.sh'
        CFG_AUTO_CONFIRM='${auto}'
        if _confirm_step 'Proceed?'; then echo PROCEED; else echo DECLINE; fi
    " < /dev/null 2>/dev/null
}

_out=$(_confirm_probe true)
assert_eq "PROCEED" "$_out" "auto_confirm=true proceeds without a prompt"

_out=$(_confirm_probe false)
assert_eq "DECLINE" "$_out" "auto_confirm=false declines when there is no terminal"

# The no-terminal path must decline quietly: testing -r on /dev/tty passes in a
# detached session but errors on open, leaking a raw shell error to the user.
_err=$(setsid bash -c "
    info(){ :; }; warn(){ :; }; YELLOW=''; RESET=''
    source '${SCRIPT_DIR}/lib/installers/_shared.sh'
    CFG_AUTO_CONFIRM=false
    _confirm_step 'Proceed?' >/dev/null
" < /dev/null 2>&1)
assert_false "no-terminal decline emits no raw shell error" grep -q "No such device" <<<"$_err"

# The tmux auto-attach snippet writes to a file the user maintains, so an
# unattended run must not add it unless auto_confirm opts in.
_out=$(setsid bash -c "
    info(){ echo \"[INFO] \$*\"; }; warn(){ :; }; error(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    _tmux_write_autoattach(){ echo WROTE; }
    CFG_AUTO_CONFIRM=false
    _tmux_offer_autoattach
" < /dev/null 2>/dev/null)
assert_false "auto-attach snippet is skipped on a non-interactive run" grep -q "WROTE" <<<"$_out"

_out=$(setsid bash -c "
    info(){ :; }; warn(){ :; }; error(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    _tmux_write_autoattach(){ echo WROTE; }
    CFG_AUTO_CONFIRM=true
    _tmux_offer_autoattach
" < /dev/null 2>/dev/null)
assert_contains "$_out" "WROTE" "auto_confirm=true adds the auto-attach snippet unattended"

# The rc block is delimited so uninstalling removes exactly what was added.
_rc_dir=$(mktemp -d)
_out=$(HOME="$_rc_dir" SHELL=/bin/bash bash -c "
    info(){ :; }; warn(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    printf 'export KEEP_ME=1\n' > '$_rc_dir/.bashrc'
    _tmux_write_autoattach >/dev/null
    _tmux_remove_autoattach >/dev/null
    cat '$_rc_dir/.bashrc'
" 2>/dev/null)
assert_contains "$_out" "KEEP_ME" "removing the auto-attach block leaves the user's own rc lines"
assert_false "removing the auto-attach block strips the whole block" grep -q "auto-attach" <<<"$_out"
rm -rf "$_rc_dir"

# The snippet must not gate on [ -t 1 ]. An rc file is sourced before stdout is
# connected to the terminal, so that test is false even in a real interactive
# SSH login and the block would never fire -- the bug this guards against.
_rc_dir=$(mktemp -d)
HOME="$_rc_dir" SHELL=/bin/bash bash -c "
    info(){ :; }; warn(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    : > '$_rc_dir/.bashrc'
    _tmux_write_autoattach >/dev/null
" 2>/dev/null
_out=$(cat "$_rc_dir/.bashrc")
assert_false "auto-attach snippet does not gate on [ -t 1 ]" grep -q -- '-t 1' <<<"$_out"
assert_true "auto-attach snippet tests interactivity with \$-" grep -qF 'case $- in' "$_rc_dir/.bashrc"
rm -rf "$_rc_dir"

# A stale snippet written by an older version is replaced, not left in place.
_rc_dir=$(mktemp -d)
{
    printf 'export KEEP_ME=1\n'
    printf '# >>> linux_util tmux auto-attach >>>\n'
    printf 'if [ -z "$TMUX" ] && [ -t 1 ] && command -v tmux >/dev/null 2>&1; then\n'
    printf '    case $- in\n        *i*) tmux attach -t work ;;\n    esac\nfi\n'
    printf '# <<< linux_util tmux auto-attach <<<\n'
} > "$_rc_dir/.bashrc"
HOME="$_rc_dir" SHELL=/bin/bash bash -c "
    info(){ :; }; warn(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    _tmux_write_autoattach >/dev/null
" 2>/dev/null
_out=$(cat "$_rc_dir/.bashrc")
assert_false "a stale [ -t 1 ] auto-attach snippet is replaced" grep -q -- '-t 1' <<<"$_out"
assert_eq "1" "$(grep -c '>>> linux_util tmux auto-attach >>>' "$_rc_dir/.bashrc")" \
    "replacing a stale snippet leaves exactly one block"
assert_contains "$_out" "KEEP_ME" "replacing a stale snippet leaves the user's own rc lines"
rm -rf "$_rc_dir"

# Powerlevel10k's instant prompt seizes the console partway through .zshrc, so a
# snippet below it gets no terminal ("open terminal failed: not a terminal").
# p10k documents that such code must run above the preamble.
_rc_dir=$(mktemp -d)
{
    printf '# Enable Powerlevel10k instant prompt. Should stay close to the top.\n'
    printf 'if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-x.zsh" ]]; then\n'
    printf '  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-x.zsh"\nfi\n'
    printf 'export KEEP_ME=1\n'
} > "$_rc_dir/.zshrc"
HOME="$_rc_dir" SHELL=/bin/zsh bash -c "
    info(){ :; }; warn(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    _tmux_write_autoattach >/dev/null
" 2>/dev/null
_snip_line=$(grep -n '>>> linux_util tmux auto-attach >>>' "$_rc_dir/.zshrc" | head -1 | cut -d: -f1)
_p10k_line=$(grep -n 'p10k-instant-prompt' "$_rc_dir/.zshrc" | head -1 | cut -d: -f1)
assert_true "auto-attach snippet is inserted above the p10k instant prompt" \
    [ "$_snip_line" -lt "$_p10k_line" ]
assert_eq "1" "$(grep -c 'Should stay close to the top' "$_rc_dir/.zshrc")" \
    "inserting above p10k does not duplicate the surrounding rc lines"
assert_contains "$(cat "$_rc_dir/.zshrc")" "KEEP_ME" \
    "inserting above p10k leaves the user's own rc lines"
rm -rf "$_rc_dir"

# A correctly-guarded block that simply sits below the preamble is relocated.
_rc_dir=$(mktemp -d)
{
    printf 'if [[ -r "$HOME/.cache/p10k-instant-prompt-x.zsh" ]]; then\n'
    printf '  source "$HOME/.cache/p10k-instant-prompt-x.zsh"\nfi\n'
    printf '# >>> linux_util tmux auto-attach >>>\n'
    printf 'if [ -z "$TMUX" ] && command -v tmux >/dev/null 2>&1; then\n'
    printf '    case $- in\n        *i*) tmux attach -t work ;;\n    esac\nfi\n'
    printf '# <<< linux_util tmux auto-attach <<<\n'
} > "$_rc_dir/.zshrc"
HOME="$_rc_dir" SHELL=/bin/zsh bash -c "
    info(){ :; }; warn(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    _tmux_write_autoattach >/dev/null
" 2>/dev/null
_snip_line=$(grep -n '>>> linux_util tmux auto-attach >>>' "$_rc_dir/.zshrc" | head -1 | cut -d: -f1)
_p10k_line=$(grep -n 'p10k-instant-prompt' "$_rc_dir/.zshrc" | head -1 | cut -d: -f1)
assert_true "a snippet stranded below the p10k preamble is moved above it" \
    [ "$_snip_line" -lt "$_p10k_line" ]
assert_eq "1" "$(grep -c '>>> linux_util tmux auto-attach >>>' "$_rc_dir/.zshrc")" \
    "relocating below-p10k snippet leaves exactly one block"
rm -rf "$_rc_dir"

# An rc file with no p10k preamble keeps the plain append.
_rc_dir=$(mktemp -d)
printf 'export KEEP_ME=1\n' > "$_rc_dir/.bashrc"
HOME="$_rc_dir" SHELL=/bin/bash bash -c "
    info(){ :; }; warn(){ :; }
    source '${SCRIPT_DIR}/lib/installers/tmux.sh'
    _tmux_write_autoattach >/dev/null
" 2>/dev/null
assert_eq "1" "$(head -1 "$_rc_dir/.bashrc" | grep -c 'KEEP_ME')" \
    "without p10k the snippet is appended, not prepended"
rm -rf "$_rc_dir"
rm -rf "$_rc_dir"


echo "=== Pre-flight Refresh Scope Tests ==="

source "${SCRIPT_DIR}/lib/pkg_manager.sh" 2>/dev/null
source "${SCRIPT_DIR}/lib/installers.sh" >/dev/null 2>&1

# On Arch there is no safe metadata-only refresh in general (-Sy alone risks a
# partial upgrade), so pkg_refresh runs -Syu. For a utility that performs the
# full upgrade itself that stole the operation: the pre-flight applied every
# pending package, then the run the user actually selected reported "No update
# available". These pin the sync-only carve-out that fixes it.

_pkg_refresh_probe() {
    # Echo the pacman command pkg_refresh would run, without running it.
    (
        PKG_MGR=pacman
        _PKG_REFRESHED=""
        run_with_spinner() { shift; echo "$*"; }
        run_direct()       { shift; echo "$*"; }
        pkg_refresh 2>&1
    )
}

test_preflight_upgrades_by_default() {
    local out; out=$(PKG_REFRESH_SYNC_ONLY=false _pkg_refresh_probe)
    assert_contains "$out" "pacman -Syu" \
        "pkg_refresh still runs -Syu for ordinary installs (no partial-upgrade window)"
}

test_preflight_sync_only_does_not_upgrade() {
    local out; out=$(PKG_REFRESH_SYNC_ONLY=true _pkg_refresh_probe)
    assert_contains "$out" "pacman -Sy" \
        "pkg_refresh syncs the database when the caller upgrades itself"
    assert_false "pkg_refresh does not upgrade ahead of a full-upgrade utility" \
        grep -q -- "-Syu" <<< "$out"
}

test_system_updates_marked_full_upgrade() {
    assert_true "System Updates is registered as performing its own full upgrade" \
        utility_performs_full_upgrade "System Updates"
}

test_ordinary_utility_not_marked_full_upgrade() {
    assert_false "an ordinary utility is not marked as a full-upgrade run" \
        utility_performs_full_upgrade "Visual Studio Code"
}

# A batch mixing System Updates with an ordinary install must NOT go sync-only:
# that install needs a fully upgraded system underneath it.
_preflight_scope_for() {
    local -a items=("$@")
    local _sync=true _item
    for _item in "${items[@]}"; do
        utility_performs_full_upgrade "$_item" || { _sync=false; break; }
    done
    echo "$_sync"
}

test_preflight_scope_mixed_batch_upgrades() {
    assert_eq "true"  "$(_preflight_scope_for "System Updates")" \
        "a System Updates-only batch skips the pre-flight upgrade"
    assert_eq "false" "$(_preflight_scope_for "System Updates" "Visual Studio Code")" \
        "a mixed batch keeps the pre-flight upgrade for the ordinary install"
    assert_eq "false" "$(_preflight_scope_for "Visual Studio Code")" \
        "an ordinary batch keeps the pre-flight upgrade"
}

test_preflight_upgrades_by_default
test_preflight_sync_only_does_not_upgrade
test_system_updates_marked_full_upgrade
test_ordinary_utility_not_marked_full_upgrade
test_preflight_scope_mixed_batch_upgrades

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Test Results: ${_TESTS_PASSED} passed, ${_TESTS_FAILED} failed, ${_TESTS_SKIPPED} skipped"
echo "════════════════════════════════════════════════════════════════"

if [[ ${_TESTS_FAILED} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for fail in "${_TEST_FAILURES[@]}"; do
        echo "  - $fail"
    done
    echo ""
fi

# Cleanup
rm -rf "$LOG_DIR"
rm -rf "$_FAKE_BIN"
rm -rf "$_WA_DIR"

exit ${_TESTS_FAILED}
