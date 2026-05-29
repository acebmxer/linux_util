#!/bin/bash
# GParted installer functions

# --- GParted ---

check_gparted() { _check_standard gparted gparted ""; }

install_gparted() {
    info "Installing GParted..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y gparted
            ;;
        fedora)
            sudo "$PKG_MGR" install -y gparted
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y gparted 2>/dev/null || {
                warn "gparted not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm gparted
            ;;
        suse)
            sudo zypper install -y gparted
            ;;
    esac
    info "GParted installed."
}

uninstall_gparted() {
    info "Uninstalling GParted..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y gparted ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y gparted ;;
        arch)        sudo pacman -Rs --noconfirm gparted ;;
        suse)        sudo zypper remove -y gparted ;;
    esac
}

update_gparted() {
    info "Updating GParted..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade gparted ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y gparted ;;
        arch)        sudo pacman -S --noconfirm gparted ;;
        suse)        sudo zypper update -y gparted ;;
    esac
}

get_version_gparted() {
    _ver_from_pkg gparted || echo ""
}
