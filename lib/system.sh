#!/bin/bash

# ============================================================================
# Linux Utilities - System Module
# Provides system helper functions used across all modules
# ============================================================================

# Helper functions for system setup
# run_as_root executes a command with sudo using argument-vector semantics.
# Each argument is passed directly to sudo without shell re-parsing.
# Usage: run_as_root command arg1 arg2 ...
run_as_root() { sudo "$@"; }

# run_as_root_sh passes its arguments as a single string to sh -c.
# Use this variant when the command requires shell features such as
# pipes (|), redirections (>), or compound operators (&& / ||).
# Arguments containing spaces, quotes, or special characters will be
# subject to word-splitting by sh.
# Usage: run_as_root_sh "cmd1 && cmd2" or run_as_root_sh "cmd | other"
run_as_root_sh() { sudo sh -c "$*"; }
info()  { printf '%s[INFO]%s %s\n' "${GREEN:-}" "${RESET:-}" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "${YELLOW:-}" "${RESET:-}" "$*"; }
error() { printf '%s[ERROR]%s %s\n' "${RED:-}" "${RESET:-}" "$*" >&2; }

# ============================================================================
# Pre-flight System Checks
# Validates system readiness before performing installations/updates.
# Returns 0 if all critical checks pass, 1 if any critical check fails.
# ============================================================================
preflight_checks() {
    local checks_passed=0
    local checks_failed=0
    local checks_warned=0

    echo ""
    echo "${BOLD:-}${CYAN:-}Running pre-flight checks...${RESET:-}"
    echo ""

    # 1. Disk space check
    local free_kb
    free_kb=$(df / 2>/dev/null | awk 'NR==2 {print $4}')
    local min_kb=$(( CFG_DISK_MIN_MB * 1024 ))
    if [[ -n "$free_kb" ]] && [[ "$free_kb" -lt "$min_kb" ]]; then
        local free_mb=$(( free_kb / 1024 ))
        warn "Low disk space: ${free_mb}MB available (minimum: ${CFG_DISK_MIN_MB}MB)"
        log_warning "Pre-flight: Low disk space: ${free_mb}MB (min ${CFG_DISK_MIN_MB}MB)"
        (( checks_failed += 1 ))
    else
        local free_mb=$(( free_kb / 1024 ))
        verbose "Disk space OK: ${free_mb}MB available"
        (( checks_passed += 1 ))
    fi

    # 2. Internet connectivity
    if [[ "$CFG_DNS_CHECK_ENABLED" == "true" ]]; then
        if ! { curl -fsS --max-time "$CFG_DNS_TIMEOUT_SECONDS" https://1.1.1.1 || \
               ping -c1 -W"$CFG_DNS_TIMEOUT_SECONDS" 8.8.8.8; } &>/dev/null; then
            warn "Internet connectivity check failed. Downloads may not work."
            log_warning "Pre-flight: Internet connectivity check failed"
            (( checks_warned += 1 ))
        else
            verbose "Internet connectivity OK"
            (( checks_passed += 1 ))
        fi
    else
        verbose "DNS check disabled by config"
        (( checks_passed += 1 ))
    fi

    # 3. Conflicting package manager processes
    local -a pm_names=()
    case "$PKG_MGR" in
        apt)     pm_names=(apt dpkg) ;;
        dnf)     pm_names=(dnf rpm) ;;
        yum)     pm_names=(yum rpm) ;;
        pacman)  pm_names=(pacman) ;;
        zypper)  pm_names=(zypper rpm) ;;
    esac
    if [[ ${#pm_names[@]} -gt 0 ]]; then
        local _pm_conflict=false
        for _pm in "${pm_names[@]}"; do
            if pgrep -x "$_pm" &>/dev/null; then
                _pm_conflict=true
                break
            fi
        done
        if [[ "$_pm_conflict" == "true" ]]; then
            warn "Another package manager process may be running (${pm_names[*]})"
            log_warning "Pre-flight: Conflicting package manager process detected"
            (( checks_warned += 1 ))
        else
            verbose "No conflicting package manager processes"
            (( checks_passed += 1 ))
        fi
    fi

    # 4. Repository availability (quick check)
    local repo_ok=false
    case "$PKG_MGR" in
        apt)
            if sudo apt-get update -qq 2>/dev/null; then
                repo_ok=true
            fi
            ;;
        dnf|yum)
            if sudo "$PKG_MGR" makecache -q 2>/dev/null; then
                repo_ok=true
            fi
            ;;
        pacman)
            # pacman -Sy would do a partial upgrade; just check if mirrorlist exists
            if [[ -f /etc/pacman.d/mirrorlist ]] && grep -q "^Server" /etc/pacman.d/mirrorlist 2>/dev/null; then
                repo_ok=true
            fi
            ;;
        zypper)
            if sudo zypper refresh -q 2>/dev/null; then
                repo_ok=true
            fi
            ;;
    esac
    if [[ "$repo_ok" == "true" ]]; then
        verbose "Package repositories accessible"
        (( checks_passed += 1 ))
    else
        warn "Package repository check failed. Installs from repos may fail."
        log_warning "Pre-flight: Package repository check failed"
        (( checks_warned += 1 ))
    fi

    # Summary
    echo "  Pre-flight: ${checks_passed} passed, ${checks_warned} warnings, ${checks_failed} failed"
    echo ""

    if [[ $checks_failed -gt 0 ]]; then
        error "Pre-flight checks failed. Resolve issues above before proceeding."
        log_error "Pre-flight checks failed: ${checks_failed} critical failure(s)"
        return 1
    fi

    log_info "Pre-flight checks passed: ${checks_passed} OK, ${checks_warned} warning(s)"
    return 0
}

# ============================================================================
# Log Rotation Setup
# Installs a logrotate configuration for linux_util log files.
# ============================================================================
setup_logrotate() {
    local logrotate_src="${SCRIPT_DIR}/linux_util.logrotate"
    local logrotate_dest="/etc/logrotate.d/linux_util"

    if [[ ! -f "$logrotate_src" ]]; then
        warn "Logrotate template not found at ${logrotate_src}"
        return 1
    fi

    # Substitute the actual log directory path into the template
    local tmp_file
    tmp_file=$(mktemp) || { error "Failed to create temp file"; return 1; }
    sed "s|__LOG_DIR__|${LOG_DIR}|g; s|__USER__|${USER}|g" \
        "$logrotate_src" > "$tmp_file"
    sudo install -m 644 -o root -g root "$tmp_file" "$logrotate_dest"
    rm -f "$tmp_file"

    info "Logrotate configuration installed to ${logrotate_dest}"
    return 0
}
