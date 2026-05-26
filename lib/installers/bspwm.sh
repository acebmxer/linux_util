#!/bin/bash
# bspwm window manager installer functions

# --- bspwm ---

check_bspwm() { _check_standard bspwm bspwm ""; }

install_bspwm() {
    info "Installing bspwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y bspwm sxhkd ;;
        fedora)      sudo "$PKG_MGR" install -y bspwm sxhkd ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y bspwm sxhkd 2>/dev/null || {
                warn "bspwm not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm bspwm sxhkd ;;
        suse)        sudo zypper install -y bspwm sxhkd ;;
    esac
    info "bspwm installed (with sxhkd for keybindings). Log out and select bspwm from your display manager."
}

uninstall_bspwm() {
    info "Uninstalling bspwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y bspwm sxhkd ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y bspwm sxhkd ;;
        arch)        sudo pacman -Rs --noconfirm bspwm sxhkd ;;
        suse)        sudo zypper remove -y bspwm sxhkd ;;
    esac
}

update_bspwm() {
    info "Updating bspwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade bspwm sxhkd ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y bspwm sxhkd ;;
        arch)        sudo pacman -S --noconfirm bspwm sxhkd ;;
        suse)        sudo zypper update -y bspwm sxhkd ;;
    esac
}

get_version_bspwm() {
    _ver_from_cmd bspwm -v || _ver_from_pkg bspwm || echo ""
}
