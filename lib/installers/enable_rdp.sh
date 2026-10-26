#!/bin/bash
# Enable RDP — unified installer for xrdp and krdp
#
# xrdp:  traditional RDP server, X11-based, broad distro support. Cannot start
#        KDE on Plasma 6.8+, which removed the X11 session.
# krdp:  KDE-native RDP server, Wayland-based (KDE Plasma 6+; the choice on
#        Plasma 6.8+ and Kubuntu 26.04+)
#
# Note: running both simultaneously is not supported — they would conflict on port 3389.
# xrdp functions live in xrdp.sh and are called directly by this dispatcher.

# --- krdp ---

check_krdp() {
    pkg_check_installed krdp
}

install_krdp() {
    info "Installing krdp..."
    ensure_tools

    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt-get update
            run_as_root apt-get install -y krdp
            ;;
        fedora|rhel)
            run_as_root "$PKG_MGR" install -y krdp
            ;;
        arch)
            run_as_root pacman -S --noconfirm krdp
            ;;
        suse)
            run_as_root zypper install -y krdp
            ;;
        *)
            error "krdp is not available for ${DISTRO_ID}. Try xrdp instead."
            return 1
            ;;
    esac

    info "krdp installed. Configure it via System Settings > Remote Desktop."
    _krdp_resize_note info
    return 0
}

# krdp does not follow the client window's size yet (KDE bug 519498), and
# turning on a client's dynamic resolution makes the picture shake or go white
# until reconnecting. A fixed resolution set in the client works.
# $1 = the output function to print with (info, or echo for the menu).
_krdp_resize_note() {
    local out="${1:-info}"
    "$out" "krdp does not resize to the client window yet (KDE bug 519498). Set a fixed resolution in your RDP client"
    "$out" "instead (in Remmina: Resolution > Custom, sized to your window) and leave dynamic resolution off."
}

# krdp runs as a per-user systemd unit (app-org.kde.krdpserver.service), not a
# system one, so it must be stopped as the desktop user rather than via sudo.
stop_krdp_service() {
    local _user="${SUDO_USER:-${USER}}"
    [[ -z "$_user" || "$_user" == "root" ]] && return 0

    local _uid
    _uid=$(id -u "$_user" 2>/dev/null) || return 0

    run_as_user() {
        if [[ "$(id -un)" == "$_user" ]]; then
            "$@"
        else
            sudo -u "$_user" XDG_RUNTIME_DIR="/run/user/${_uid}" "$@"
        fi
    }

    run_as_user systemctl --user stop app-org.kde.krdpserver.service 2>/dev/null || true
    run_as_user systemctl --user disable app-org.kde.krdpserver.service 2>/dev/null || true
    unset -f run_as_user
}

uninstall_krdp() {
    info "Uninstalling krdp..."
    stop_krdp_service

    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt purge --autoremove -y krdp
            ;;
        fedora|rhel)
            run_as_root "$PKG_MGR" remove -y krdp
            ;;
        arch)
            run_as_root pacman -Rs --noconfirm krdp 2>/dev/null || true
            ;;
        suse)
            run_as_root zypper remove -y krdp
            ;;
        *)
            error "krdp uninstall not supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "krdp has been uninstalled."
}

update_krdp() {
    info "Updating krdp..."
    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt-get update
            run_as_root apt-get install -y --only-upgrade krdp
            ;;
        fedora|rhel)
            run_as_root "$PKG_MGR" upgrade -y krdp
            ;;
        arch)
            run_as_root pacman -S --noconfirm krdp
            ;;
        suse)
            run_as_root zypper update -y krdp
            ;;
        *)
            warn "krdp update not supported for ${DISTRO_ID}"
            return 1
            ;;
    esac
}

get_version_krdp() {
    local ver=""
    ver=$(dpkg-query -W -f='${Version}' krdp 2>/dev/null | grep -oP '[0-9]+\.[0-9]+[0-9.]*' | head -1)
    if [[ -n "$ver" ]]; then
        echo "$ver"
        return
    fi
    ver=$(rpm -q --qf '%{VERSION}' krdp 2>/dev/null)
    if [[ -n "$ver" ]]; then
        echo "$ver"
        return
    fi
    ver=$(pacman -Q krdp 2>/dev/null | awk '{print $2}')
    echo "${ver:-}"
}

# --- Enable RDP (unified dispatcher) ---

check_enable_rdp() {
    check_xrdp || check_krdp
}

install_enable_rdp() {
    # Styled menu output — intentionally uses echo, not info/warn
    echo ""
    echo "${BOLD}${CYAN}Select RDP Server to Install:${RESET}"
    echo ""
    if _xrdp_kde_without_x11; then
        # Plasma 6.8+ removed the X11 session xrdp needs; krdp is the only
        # server that can show this desktop. The numbers stay the same as on
        # other systems so typed answers mean the same everywhere.
        echo "  1) xrdp  — cannot start KDE here: Plasma 6.8 removed the X11 session it needs"
        echo "  2) krdp  — KDE-native, Wayland-based (recommended on Plasma 6.8+)"
        echo ""
        _krdp_resize_note echo
    else
        echo "  1) xrdp  — traditional, X11-based, works on most distros (currently recommended)"
        echo "  2) krdp  — KDE-native, Wayland-based (currently not recommended)"
    fi
    echo ""

    local choice
    while true; do
        read -rp "Choice [1-2, or q to cancel]: " choice < /dev/tty
        case "$choice" in
            1) install_xrdp; return $? ;;
            2) install_krdp; return $? ;;
            q|Q) return 2 ;;
            *) echo "Please enter 1, 2, or q to cancel." ;;
        esac
    done
}

# --- Switching servers from Uninstall ---
#
# Once either server is installed, the menu and the desktop app offer only
# Uninstall and Update for Enable RDP, never Install. So Uninstall is where
# the user can swap one server for the other without removing both first.

# Print the server Uninstall can switch to, or nothing. Offered only when one
# server is installed: krdp needs a KDE Plasma desktop, and xrdp needs one
# that still has an X11 session (see _xrdp_kde_without_x11).
_enable_rdp_switch_target() {
    local has_xrdp=false has_krdp=false
    check_xrdp && has_xrdp=true
    check_krdp && has_krdp=true
    if [[ "$has_xrdp" == "true" && "$has_krdp" == "false" ]]; then
        command -v plasmashell >/dev/null 2>&1 && echo "krdp"
    elif [[ "$has_krdp" == "true" && "$has_xrdp" == "false" ]]; then
        _xrdp_kde_without_x11 || echo "xrdp"
    fi
    return 0
}

# Set by _enable_rdp_uninstall_choice: remove, switch or cancel.
_ENABLE_RDP_CHOICE=""

# Ask whether Uninstall removes the server or switches to the other one.
# With no terminal to ask on, or with auto_confirm set, the answer is
# "remove": that is what Uninstall always did, so unattended runs still do it.
# $1 = installed server, $2 = the one to switch to.
_enable_rdp_uninstall_choice() {
    local current="$1" target="$2" choice
    _ENABLE_RDP_CHOICE="remove"
    [[ "${CFG_AUTO_CONFIRM:-false}" == "true" ]] && return 0
    { : < /dev/tty; } 2>/dev/null || return 0

    # Styled menu output — intentionally uses echo, like install_enable_rdp
    echo ""
    echo "${BOLD}${CYAN}${current} is installed. Choose what Uninstall does:${RESET}"
    echo ""
    if [[ "$current" == "xrdp" ]] && _xrdp_kde_without_x11; then
        echo "  xrdp cannot start KDE on Plasma 6.8+, which removed the X11 session. Switching to krdp is recommended."
        echo ""
    fi
    echo "  1) Remove ${current}"
    if [[ "$target" == "krdp" ]]; then
        echo "  2) Switch to krdp — installs krdp, then removes xrdp"
    else
        echo "  2) Switch to xrdp — removes krdp, then installs xrdp"
    fi
    echo ""

    while true; do
        read -rp "Choice [1-2, or q to cancel]: " choice < /dev/tty
        case "$choice" in
            1) _ENABLE_RDP_CHOICE="remove"; return 0 ;;
            2) _ENABLE_RDP_CHOICE="switch"; return 0 ;;
            q|Q) _ENABLE_RDP_CHOICE="cancel"; return 0 ;;
            *) echo "Please enter 1, 2, or q to cancel." ;;
        esac
    done
}

# Replace one server with the other. $1 = installed server, $2 = target.
_enable_rdp_switch() {
    local current="$1" target="$2"

    if [[ "$target" == "krdp" ]]; then
        # krdp goes in first, so a failed install leaves xrdp as it was. Both
        # can be installed at once: krdp only listens on port 3389 after it is
        # turned on in System Settings. uninstall_xrdp refuses while anyone is
        # connected, so check that before changing anything.
        if _xrdp_sessions_open; then
            error "RDP sessions are open. Switching removes xrdp, which ends them, including this one if you are connected over RDP."
            error "Log out of every RDP session, then run this again from a local login or over SSH."
            return 1
        fi
        install_krdp || true
        if ! check_krdp; then
            error "krdp could not be installed. xrdp has been left as it was."
            return 1
        fi
        if ! uninstall_xrdp; then
            error "krdp is installed, but xrdp could not be removed. Run Enable RDP's Uninstall again and choose Remove."
            return 1
        fi
        info "Switched from xrdp to krdp. Turn it on in System Settings > Remote Desktop."
        return 0
    fi

    # xrdp must claim port 3389 as soon as it starts, so krdp goes first.
    uninstall_krdp || return 1
    if ! install_xrdp; then
        error "krdp was removed, but xrdp could not be installed. Run Enable RDP again to install either server."
        return 1
    fi
    info "Switched from ${current} to xrdp."
    return 0
}

uninstall_enable_rdp() {
    local found=false rc=0 target
    target=$(_enable_rdp_switch_target)
    if [[ -n "$target" ]]; then
        local current="xrdp"
        [[ "$target" == "xrdp" ]] && current="krdp"
        _enable_rdp_uninstall_choice "$current" "$target"
        case "$_ENABLE_RDP_CHOICE" in
            switch) _enable_rdp_switch "$current" "$target"; return $? ;;
            cancel) return 2 ;;
        esac
    fi

    if check_xrdp; then
        found=true
        uninstall_xrdp || rc=1
    fi
    if check_krdp; then
        found=true
        uninstall_krdp || rc=1
    fi
    if [[ "$found" == "false" ]]; then
        info "No RDP server found to uninstall."
    fi
    return $rc
}

update_enable_rdp() {
    local updated=false
    if check_xrdp; then
        update_xrdp
        updated=true
    fi
    if check_krdp; then
        update_krdp
        updated=true
    fi
    if [[ "$updated" == "false" ]]; then
        info "No RDP server found to update."
    fi
}

get_version_enable_rdp() {
    if check_xrdp; then
        local v
        v=$(get_version_xrdp)
        echo "xrdp${v:+ v${v}}"
    elif check_krdp; then
        local v
        v=$(get_version_krdp)
        echo "krdp${v:+ v${v}}"
    fi
}
