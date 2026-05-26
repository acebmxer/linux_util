#!/bin/bash
# awesome window manager installer functions

# --- awesome ---

check_awesome() { _check_standard awesome awesome ""; }

install_awesome() {
    info "Installing awesome..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y awesome ;;
        fedora)      sudo "$PKG_MGR" install -y awesome ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y awesome 2>/dev/null || {
                warn "awesome not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm awesome ;;
        suse)        sudo zypper install -y awesome ;;
    esac
    info "awesome installed. Log out and select awesome from your display manager."
}

uninstall_awesome() {
    info "Uninstalling awesome..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y awesome ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y awesome ;;
        arch)        sudo pacman -Rs --noconfirm awesome ;;
        suse)        sudo zypper remove -y awesome ;;
    esac
}

update_awesome() {
    info "Updating awesome..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade awesome ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y awesome ;;
        arch)        sudo pacman -S --noconfirm awesome ;;
        suse)        sudo zypper update -y awesome ;;
    esac
}

get_version_awesome() {
    _ver_from_cmd awesome --version || _ver_from_pkg awesome || echo ""
}
