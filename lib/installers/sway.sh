#!/bin/bash
# Sway (Wayland) window manager installer functions

# --- Sway ---

check_sway() { _check_standard sway sway ""; }

install_sway() {
    info "Installing Sway..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y sway ;;
        fedora)      sudo "$PKG_MGR" install -y sway ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y sway 2>/dev/null || {
                warn "Sway not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm sway ;;
        suse)        sudo zypper install -y sway ;;
    esac
    info "Sway installed. Log out and select Sway from your display manager."
}

uninstall_sway() {
    info "Uninstalling Sway..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y sway ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y sway ;;
        arch)        sudo pacman -Rs --noconfirm sway ;;
        suse)        sudo zypper remove -y sway ;;
    esac
}

update_sway() {
    info "Updating Sway..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade sway ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y sway ;;
        arch)        sudo pacman -S --noconfirm sway ;;
        suse)        sudo zypper update -y sway ;;
    esac
}

get_version_sway() {
    _ver_from_cmd sway --version || _ver_from_pkg sway || echo ""
}
