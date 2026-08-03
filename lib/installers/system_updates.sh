#!/bin/bash
# System Updates functions

# True when running on CachyOS or any Arch-family system with arch-update/cachy-update installed.
# These tools handle Arch-specific post-update tasks (Arch news, kernel reboot detection,
# service restarts, paccache cleanup) that this script does not replicate.
_system_updates_has_arch_update() {
    [[ "${DISTRO_FAMILY:-}" == "arch" ]] && \
        { command -v cachy-update &>/dev/null || command -v arch-update &>/dev/null; }
}

_system_updates_arch_update_cmd() {
    if command -v cachy-update &>/dev/null; then
        echo "cachy-update"
    else
        echo "arch-update"
    fi
}

# Refresh device firmware metadata and apply available updates via fwupd (LVFS).
# This is a separate subsystem from the native package manager and Flatpak, so
# neither of those update flows ever touches device firmware (BIOS/UEFI, SSDs,
# docks, UEFI dbx revocations, etc.). Kept fully interactive: fwupdmgr prompts
# per-device and asks to reboot when a capsule update needs it — we pass those
# prompts straight through to the user rather than forcing -y.
_system_updates_apply_firmware() {
    command -v fwupdmgr &>/dev/null || return 0

    info "Checking device firmware (fwupd/LVFS)..."
    # Refresh metadata; --force lets it refresh even if recently done. Non-fatal
    # on failure (e.g. offline server) — fall through to whatever is cached.
    sudo fwupdmgr refresh --force < /dev/tty || \
        warn "Firmware metadata refresh failed; continuing with cached data."

    # If nothing is pending, get-upgrades exits non-zero — skip quietly.
    if ! sudo fwupdmgr get-upgrades &>/dev/null; then
        info "No device firmware updates available."
        return 0
    fi

    info "Firmware updates are available. fwupd will prompt for each device."
    # No -y: user answers the per-device and reboot prompts interactively.
    sudo fwupdmgr update < /dev/tty || \
        warn "Firmware update did not complete for all devices (see output above)."
}

# --- System Updates ---
setup_system_updates() {
    if _system_updates_has_arch_update; then
        local _cmd
        _cmd=$(_system_updates_arch_update_cmd)
        info "Deferring to ${_cmd} for a complete Arch-family update..."
        info "(Includes Arch news, AUR, Flatpak, orphan removal, cache cleanup, kernel/service checks)"
        echo ""
        local _snap_before _snap_after
        _snap_before=$(pkg_snapshot)
        "$_cmd"
        local _rc=$?
        _snap_after=$(pkg_snapshot)
        [[ "$_snap_before" == "$_snap_after" ]] && return 3
        return $_rc
    fi

    info "Running system updates..."
    local _snap_before
    _snap_before=$(pkg_snapshot)
    pkg_refresh_interactive
    _pkg_cleanup_stale_releases direct
    pkg_full_upgrade_interactive || return $?
    # Flatpak apps/runtimes are a separate package system the native manager
    # never touches, so update them here too (Arch defers this to *-update above).
    if check_flatpak_setup; then
        info "Updating Flatpak applications and runtimes..."
        flatpak update -y
    fi
    # Device firmware is yet another separate subsystem the package manager and
    # Flatpak never touch (this is what fwupdmgr's MOTD notice refers to).
    _system_updates_apply_firmware
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

    # Count pending device firmware updates (fwupd/LVFS). Uses cached metadata
    # only — no sudo, no network — so it's safe/fast for the menu. Each device
    # that has a pending upgrade prints exactly one "New version:" line in the
    # get-upgrades tree output; devices with no update (which also use • bullets)
    # never print that line, so counting it is an accurate per-device tally.
    # Non-fatal and skipped entirely if fwupdmgr isn't installed.
    local firmware=0
    if _have_cmd fwupdmgr; then
        local _fw
        _fw=$(fwupdmgr get-upgrades 2>/dev/null) || true
        [[ -n "$_fw" ]] && firmware=$(echo "$_fw" | grep -cE '^[[:space:]]*New version:' || true)
    fi

    # Return empty if nothing pending at all (menu shows no status tag)
    [[ "$total" -le 0 && "$firmware" -le 0 ]] && return 0

    # Build display string
    local _out=""
    if [[ "$total" -gt 0 ]]; then
        _out="${total} updates"
        [[ "$security" -gt 0 ]] && _out+=", ${security} security"
        [[ "$kernel"   -gt 0 ]] && _out+=", ${kernel} kernel"
    fi
    if [[ "$firmware" -gt 0 ]]; then
        [[ -n "$_out" ]] && _out+=", "
        _out+="${firmware} firmware"
    fi
    echo "$_out"
}
