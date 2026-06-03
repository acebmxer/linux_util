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
warn() {
    printf '%s[WARN]%s %s\n' "${YELLOW:-}" "${RESET:-}" "$*"
    if [[ -n "${ERROR_LOG:-}" ]]; then
        init_error_log
        printf '[%s] [WARNING] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$ERROR_LOG"
    fi
}
error() {
    printf '%s[ERROR]%s %s\n' "${RED:-}" "${RESET:-}" "$*" >&2
    if [[ -n "${ERROR_LOG:-}" ]]; then
        init_error_log
        printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$ERROR_LOG"
    fi
}

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
        local _check_host="${CFG_DNS_CHECK_HOST:-1.1.1.1}"
        # Try the configured host first, then fall back to 9.9.9.9 (Quad9) as a
        # secondary, so corporate/restricted networks that block Cloudflare still pass.
        if ! { curl -fsS --max-time "$CFG_DNS_TIMEOUT_SECONDS" "https://${_check_host}" || \
               curl -fsS --max-time "$CFG_DNS_TIMEOUT_SECONDS" "https://9.9.9.9"        || \
               ping -c1 -W"$CFG_DNS_TIMEOUT_SECONDS" "$_check_host"; } &>/dev/null; then
            warn "Internet connectivity check failed. Downloads may not work."
            warn "If on a corporate/restricted network, set dns_check_host in linux_util.conf."
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

    # 4. Repository configuration check (local only — avoids duplicating the
    #    pkg_refresh that process_selected runs immediately after preflight).
    local repo_ok=false
    case "$PKG_MGR" in
        apt)
            # Verify repos are configured in source lists (cache may not be
            # populated yet — pkg_refresh runs immediately after preflight).
            # Check both traditional format (deb ...) and deb822 format (Types: deb).
            if grep -rqh '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null \
               || grep -rqh '^Types:.*deb' /etc/apt/sources.list.d/*.sources 2>/dev/null; then
                repo_ok=true
            fi
            ;;
        dnf|yum)
            # Check that at least one enabled repo is configured.
            if "$PKG_MGR" repolist 2>/dev/null | grep -q '.'; then
                repo_ok=true
            fi
            ;;
        pacman)
            # Check if mirrorlist exists and has active servers.
            if [[ -f /etc/pacman.d/mirrorlist ]] && grep -q "^Server" /etc/pacman.d/mirrorlist 2>/dev/null; then
                repo_ok=true
            fi
            ;;
        zypper)
            # Check that at least one repo is registered.
            if zypper repos 2>/dev/null | grep -q 'http'; then
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

# ============================================================================
# WSL (Windows Subsystem for Linux) Support
# ============================================================================

# is_wsl returns 0 (true) when running inside a WSL distribution, 1 otherwise.
# The result is cached in _IS_WSL so detection runs at most once per process.
#
# Detection signals (any match → WSL):
#   - $WSL_DISTRO_NAME is set (present in WSL 0.0.something onward)
#   - /proc/version contains "microsoft" or the "-WSL2" kernel suffix
is_wsl() {
    if [[ -z "${_IS_WSL:-}" ]]; then
        if [[ -n "${WSL_DISTRO_NAME:-}" ]] \
           || grep -qiE 'microsoft|-WSL2' /proc/version 2>/dev/null; then
            _IS_WSL=true
        else
            _IS_WSL=false
        fi
    fi
    [[ "$_IS_WSL" == true ]]
}

# wsl_distro_name echoes the running WSL distribution name (e.g. "Ubuntu"),
# or an empty string when unknown/not under WSL.
wsl_distro_name() { printf '%s' "${WSL_DISTRO_NAME:-}"; }

# do_reboot performs a system reboot appropriate to the environment.
#
# On a normal Linux host/VM this runs the same `sudo systemctl reboot` the
# script has always used. Under WSL a real reboot is not possible from inside
# the distro: Windows owns the VM lifecycle and there is no bootloader. The
# correct equivalent is to terminate the distro from the Windows side (via the
# wsl.exe interop bridge) and relaunch it. Terminating ends this process, so
# the function does not return on the WSL interop path — it exits.
#
# Caller note: release any held lock fd (e.g. `exec 9>&-`) before invoking,
# because the process will be replaced/terminated.
do_reboot() {
    if is_wsl; then
        local distro
        distro="$(wsl_distro_name)"
        warn "Under WSL a reboot terminates and relaunches the distro from Windows (Windows itself is not affected)."
        # Preferred path: use the wsl.exe interop bridge to terminate just this
        # distro. The running session ends immediately and the distro auto-starts
        # on the next terminal/app, or via `wsl -d <distro>`.
        if command -v wsl.exe >/dev/null 2>&1 && [[ -n "$distro" ]]; then
            info "Terminating WSL distro '${distro}'. Relaunch with: wsl -d ${distro}"
            printf '\n\n'
            wsl.exe --terminate "$distro"
            # --terminate only *requests* shutdown; a systemd distro needs a
            # moment to drain its units. Relaunching before the old session is
            # gone races user@<uid>.service and can fail with "Device or
            # resource busy" (systemd ends up 'degraded', and `wsl -d` reports
            # "Failed to start the systemd user session"). Wait until the distro
            # no longer appears in the running list, bounded so we never hang.
            local i
            for i in $(seq 1 20); do
                # `wsl.exe --list` emits UTF-16LE; strip NULs before matching.
                if ! wsl.exe --list --running 2>/dev/null \
                     | tr -d '\000' \
                     | grep -qiE "(^|[[:space:]])${distro}([[:space:]]|\$)"; then
                    break
                fi
                sleep 0.5
            done
            exit 0
        fi
        # Fallback: interop unavailable or distro name unknown — print the exact
        # commands for the user to run from Windows PowerShell themselves.
        warn "Could not auto-terminate (wsl.exe not reachable or distro name unknown)."
        echo "  Run these in Windows PowerShell:"
        echo "    wsl --terminate ${distro:-<DistroName>}"
        echo "    wsl -d ${distro:-<DistroName>}"
        return 0
    fi
    # Normal Linux host/VM — unchanged behavior.
    sudo systemctl reboot
}
