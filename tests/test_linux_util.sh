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

test_config_defaults
test_config_load_missing_file
test_config_load_from_file

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

    resolve_utility_name "docker" 2>/dev/null
    assert_eq "Docker" "$_RESOLVED" "resolve_utility_name matches case-insensitively"

    resolve_utility_name "brave" 2>/dev/null
    assert_eq "Brave Browser" "$_RESOLVED" "resolve_utility_name matches partial names"

    assert_false "resolve_utility_name rejects unknown names" resolve_utility_name "nonexistent"
}

test_register_utility
test_register_utility_no_version
test_resolve_utility_name

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

test_health_checks_init() {
    _init_health_checks
    assert_not_empty "${HEALTH_CHECK_CMDS[Docker]:-}" "Health check registered for Docker"
    assert_not_empty "${HEALTH_CHECK_CMDS[OpenSSH Server]:-}" "Health check registered for OpenSSH"
}

test_health_check_no_check() {
    HEALTH_CHECK_CMDS=()
    CHECK_FUNCS=()
    # No health check and no check func should succeed
    assert_true "health_check succeeds when no check available" health_check "Unknown App"
}

test_health_checks_init
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

exit ${_TESTS_FAILED}
