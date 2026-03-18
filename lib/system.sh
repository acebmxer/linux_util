#!/bin/bash

# ============================================================================
# Linux Utilities - System Module
# Provides system helper functions used across all modules
# ============================================================================

# Helper functions for system setup
# NOTE: run_as_root passes its arguments as a single string to sh -c.
# Arguments containing spaces, quotes, or special characters will be
# subject to word-splitting by sh. For commands with complex quoting,
# use 'sudo bash -c "..."' directly instead of this helper.
run_as_root() { sudo sh -c "$*"; }
info()  { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
error() { printf '\e[31m[ERROR]\e[0m %s\n' "$*" >&2; }

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
        ((checks_failed++))
    else
        local free_mb=$(( free_kb / 1024 ))
        verbose "Disk space OK: ${free_mb}MB available"
        ((checks_passed++))
    fi

    # 2. Internet connectivity
    if [[ "$CFG_DNS_CHECK_ENABLED" == "true" ]]; then
        if ! { curl -fsS --max-time "$CFG_DNS_TIMEOUT_SECONDS" https://1.1.1.1 || \
               ping -c1 -W"$CFG_DNS_TIMEOUT_SECONDS" 8.8.8.8; } &>/dev/null; then
            warn "Internet connectivity check failed. Downloads may not work."
            log_warning "Pre-flight: Internet connectivity check failed"
            ((checks_warned++))
        else
            verbose "Internet connectivity OK"
            ((checks_passed++))
        fi
    else
        verbose "DNS check disabled by config"
        ((checks_passed++))
    fi

    # 3. Conflicting package manager processes
    local pm_pattern=""
    case "$PKG_MGR" in
        apt)     pm_pattern="apt|dpkg" ;;
        dnf)     pm_pattern="dnf|rpm" ;;
        yum)     pm_pattern="yum|rpm" ;;
        pacman)  pm_pattern="pacman" ;;
        zypper)  pm_pattern="zypper|rpm" ;;
    esac
    if [[ -n "$pm_pattern" ]]; then
        # Exclude our own process and grep itself
        if pgrep -x -f "$pm_pattern" &>/dev/null 2>&1; then
            warn "Another package manager process may be running (${pm_pattern})"
            log_warning "Pre-flight: Conflicting package manager process detected"
            ((checks_warned++))
        else
            verbose "No conflicting package manager processes"
            ((checks_passed++))
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
        ((checks_passed++))
    else
        warn "Package repository check failed. Installs from repos may fail."
        log_warning "Pre-flight: Package repository check failed"
        ((checks_warned++))
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
    sudo sed "s|__LOG_DIR__|${LOG_DIR}|g; s|__USER__|${USER}|g" \
        "$logrotate_src" > /tmp/linux_util_logrotate.tmp
    sudo mv /tmp/linux_util_logrotate.tmp "$logrotate_dest"
    sudo chmod 644 "$logrotate_dest"

    info "Logrotate configuration installed to ${logrotate_dest}"
    return 0
}
