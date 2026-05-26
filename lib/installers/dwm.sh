#!/bin/bash
# dwm (suckless) window manager installer functions

# --- dwm ---

check_dwm() { _check_standard dwm dwm ""; }

install_dwm() {
    info "Installing dwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y dwm ;;
        fedora)      sudo "$PKG_MGR" install -y dwm ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y dwm 2>/dev/null || {
                warn "dwm not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm dwm ;;
        suse)        sudo zypper install -y dwm ;;
    esac
    info "dwm installed. Log out and select dwm from your display manager."
    info "Note: dwm is configured by editing config.h and recompiling — the packaged binary uses upstream defaults."
}

uninstall_dwm() {
    info "Uninstalling dwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y dwm ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y dwm ;;
        arch)        sudo pacman -Rs --noconfirm dwm ;;
        suse)        sudo zypper remove -y dwm ;;
    esac
}

update_dwm() {
    info "Updating dwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade dwm ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y dwm ;;
        arch)        sudo pacman -S --noconfirm dwm ;;
        suse)        sudo zypper update -y dwm ;;
    esac
}

get_version_dwm() {
    _ver_from_cmd dwm -v || _ver_from_pkg dwm || echo ""
}
