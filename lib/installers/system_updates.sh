#!/bin/bash
# System Updates functions

# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    local _snap_before
    _snap_before=$(pkg_snapshot)
    pkg_refresh_interactive
    _pkg_cleanup_stale_releases direct
    pkg_full_upgrade_interactive
    pkg_cleanup_thorough_interactive
    info "System updates completed."
    local _snap_after
    _snap_after=$(pkg_snapshot)
    if [[ "$_snap_before" == "$_snap_after" ]]; then
        info "No package changes were made."
        return 3
    fi
    return 0
}

# --- System Updates version/status ---
# Returns pending update count for display in the menu.
# Uses cached MOTD data on Ubuntu or package manager queries as fallback.
get_version_system_updates() {
    local total=0 security=0 kernel=0

    case "${PKG_MGR:-}" in
        apt)
            # Try Ubuntu/Debian cached MOTD update count (instant, no sudo)
            local _motd="/var/lib/update-notifier/updates-available"
            if [[ -f "$_motd" ]]; then
                local _line _sec_line
                _line=$(grep 'updates\? can be applied' "$_motd" 2>/dev/null | head -1 || true)
                [[ "$_line" =~ ^([0-9]+) ]] && total="${BASH_REMATCH[1]}"
                _sec_line=$(grep 'standard security updates' "$_motd" 2>/dev/null | head -1 || true)
                [[ "$_sec_line" =~ ^([0-9]+) ]] && security="${BASH_REMATCH[1]}"
            fi
            # Fallback: count from local apt cache
            if [[ "$total" -eq 0 ]]; then
                total=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
            fi
            # Check for kernel updates in the upgradable list
            if [[ "$total" -gt 0 ]]; then
                kernel=$(apt list --upgradable 2>/dev/null | grep -ci 'linux-image' || true)
            fi
            ;;
        dnf|yum)
            local _out
            _out=$("${PKG_MGR}" check-update 2>/dev/null) || true
            total=$(echo "$_out" | grep -cE '^\S+\.\S+\s' || true)
            ;;
        pacman)
            local _out
            _out=$(checkupdates 2>/dev/null || pacman -Qu 2>/dev/null) || true
            total=$(echo "$_out" | grep -c '.' || true)
            ;;
        zypper)
            total=$(zypper --non-interactive list-updates 2>/dev/null | grep -cE '^\s*v\s*\|' || true)
            ;;
    esac

    # Return empty if no updates (menu shows no status tag)
    [[ "$total" -le 0 ]] && return 0

    # Build display string
    local _out="${total} updates"
    [[ "$security" -gt 0 ]] && _out+=", ${security} security"
    [[ "$kernel"   -gt 0 ]] && _out+=", ${kernel} kernel"
    echo "$_out"
}
