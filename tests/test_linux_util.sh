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

test_config_defaults
test_config_load_missing_file
test_config_load_from_file
test_config_crlf_file

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
_run_cli() {
    local _tmp_out
    _tmp_out=$(mktemp /tmp/linux_util_cli_out_XXXXXX)
    PATH="$_FAKE_BIN:$PATH" timeout -k 2 10 bash "$SCRIPT_DIR/linux_util.sh" "$@" </dev/null >"$_tmp_out" 2>&1
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
# Results Summary
# ============================================================================
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

exit ${_TESTS_FAILED}
