#!/bin/bash
# Filelight installer functions

# --- Filelight ---

check_filelight() { _check_standard filelight filelight ""; }

install_filelight() {
    info "Installing Filelight..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y filelight
            ;;
        fedora)
            sudo "$PKG_MGR" install -y filelight
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y filelight 2>/dev/null || {
                warn "filelight not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm filelight
            ;;
        suse)
            sudo zypper install -y filelight
            ;;
    esac
    info "Filelight installed."
}

uninstall_filelight() {
    info "Uninstalling Filelight..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y filelight ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y filelight ;;
        arch)        sudo pacman -Rs --noconfirm filelight ;;
        suse)        sudo zypper remove -y filelight ;;
    esac
}

update_filelight() {
    info "Updating Filelight..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade filelight ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y filelight ;;
        arch)        sudo pacman -S --noconfirm filelight ;;
        suse)        sudo zypper update -y filelight ;;
    esac
}

get_version_filelight() {
    _ver_from_pkg filelight || echo ""
}
