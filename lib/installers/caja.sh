#!/bin/bash
# Caja (MATE) installer functions

# --- Caja ---

check_caja() { _check_standard caja caja ""; }

install_caja() {
    info "Installing Caja..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y caja ;;
        fedora)      sudo "$PKG_MGR" install -y caja ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y caja 2>/dev/null || {
                warn "caja not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm caja ;;
        suse)        sudo zypper install -y caja ;;
    esac
    info "Caja installed."
}

uninstall_caja() {
    info "Uninstalling Caja..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y caja ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y caja ;;
        arch)        sudo pacman -Rs --noconfirm caja ;;
        suse)        sudo zypper remove -y caja ;;
    esac
}

update_caja() {
    info "Updating Caja..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade caja ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y caja ;;
        arch)        sudo pacman -S --noconfirm caja ;;
        suse)        sudo zypper update -y caja ;;
    esac
}

get_version_caja() {
    _ver_from_pkg caja || echo ""
}
