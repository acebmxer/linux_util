#!/bin/bash
# Dolphin (KDE) installer functions

# --- Dolphin ---

check_dolphin() { _check_standard dolphin dolphin ""; }

install_dolphin() {
    info "Installing Dolphin..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y dolphin ;;
        fedora)      sudo "$PKG_MGR" install -y dolphin ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y dolphin 2>/dev/null || {
                warn "dolphin not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm dolphin ;;
        suse)        sudo zypper install -y dolphin ;;
    esac
    info "Dolphin installed."
}

uninstall_dolphin() {
    info "Uninstalling Dolphin..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y dolphin ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y dolphin ;;
        arch)        sudo pacman -Rs --noconfirm dolphin ;;
        suse)        sudo zypper remove -y dolphin ;;
    esac
}

update_dolphin() {
    info "Updating Dolphin..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade dolphin ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y dolphin ;;
        arch)        sudo pacman -S --noconfirm dolphin ;;
        suse)        sudo zypper update -y dolphin ;;
    esac
}

get_version_dolphin() {
    _ver_from_pkg dolphin || echo ""
}
