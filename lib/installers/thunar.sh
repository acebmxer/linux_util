#!/bin/bash
# Thunar (Xfce) installer functions

# --- Thunar ---

check_thunar() {
    # Fedora ships the package as "Thunar" (capital T); other distros use "thunar".
    _have_cmd thunar && return 0
    pkg_check_installed thunar && return 0
    pkg_check_installed Thunar && return 0
    return 1
}

install_thunar() {
    info "Installing Thunar..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y thunar ;;
        fedora)      sudo "$PKG_MGR" install -y Thunar ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y Thunar 2>/dev/null || \
                sudo "$PKG_MGR" install -y thunar 2>/dev/null || {
                warn "thunar not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm thunar ;;
        suse)        sudo zypper install -y thunar ;;
    esac
    info "Thunar installed."
}

uninstall_thunar() {
    info "Uninstalling Thunar..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y thunar ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y Thunar 2>/dev/null || sudo "$PKG_MGR" remove -y thunar ;;
        arch)        sudo pacman -Rs --noconfirm thunar ;;
        suse)        sudo zypper remove -y thunar ;;
    esac
}

update_thunar() {
    info "Updating Thunar..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade thunar ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y Thunar 2>/dev/null || sudo "$PKG_MGR" upgrade -y thunar ;;
        arch)        sudo pacman -S --noconfirm thunar ;;
        suse)        sudo zypper update -y thunar ;;
    esac
}

get_version_thunar() {
    _ver_from_pkg thunar || _ver_from_pkg Thunar || echo ""
}
