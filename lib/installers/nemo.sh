#!/bin/bash
# Nemo (Cinnamon) installer functions

# --- Nemo ---

check_nemo() { _check_standard nemo nemo ""; }

install_nemo() {
    info "Installing Nemo..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y nemo ;;
        fedora)      sudo "$PKG_MGR" install -y nemo ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y nemo 2>/dev/null || {
                warn "nemo not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm nemo ;;
        suse)        sudo zypper install -y nemo ;;
    esac
    info "Nemo installed."
}

uninstall_nemo() {
    info "Uninstalling Nemo..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y nemo ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y nemo ;;
        arch)        sudo pacman -Rs --noconfirm nemo ;;
        suse)        sudo zypper remove -y nemo ;;
    esac
}

update_nemo() {
    info "Updating Nemo..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade nemo ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y nemo ;;
        arch)        sudo pacman -S --noconfirm nemo ;;
        suse)        sudo zypper update -y nemo ;;
    esac
}

get_version_nemo() {
    _ver_from_pkg nemo || echo ""
}
