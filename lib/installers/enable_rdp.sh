#!/bin/bash
# Enable RDP — unified installer for xrdp and krdp
#
# xrdp:  traditional RDP server, X11-based, broad distro support
# krdp:  KDE-native RDP server, Wayland-based (KDE Plasma 6+, recommended for Kubuntu 26.04+)
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
    return 0
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
    echo "  1) xrdp  — traditional, X11-based, works on most distros (currently recommended)"
    echo "  2) krdp  — KDE-native, Wayland-based (currently not recommended)"
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

uninstall_enable_rdp() {
    local found=false rc=0
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
