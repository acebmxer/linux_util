#!/bin/bash
# nnn installer functions

# --- nnn ---

check_nnn() { _check_standard nnn nnn ""; }

install_nnn() {
    info "Installing nnn..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y nnn ;;
        fedora)      sudo "$PKG_MGR" install -y nnn ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y nnn 2>/dev/null || {
                warn "nnn not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm nnn ;;
        suse)        sudo zypper install -y nnn ;;
    esac
    info "nnn installed."
}

uninstall_nnn() {
    info "Uninstalling nnn..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y nnn ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y nnn ;;
        arch)        sudo pacman -Rs --noconfirm nnn ;;
        suse)        sudo zypper remove -y nnn ;;
    esac
}

update_nnn() {
    info "Updating nnn..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade nnn ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y nnn ;;
        arch)        sudo pacman -S --noconfirm nnn ;;
        suse)        sudo zypper update -y nnn ;;
    esac
}

get_version_nnn() {
    _ver_from_pkg nnn || _ver_from_cmd nnn -V || echo ""
}
