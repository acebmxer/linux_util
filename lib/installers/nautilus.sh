#!/bin/bash
# Nautilus (GNOME Files) installer functions

# --- Nautilus ---

check_nautilus() { _check_standard nautilus nautilus ""; }

install_nautilus() {
    info "Installing Nautilus..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y nautilus ;;
        fedora)      sudo "$PKG_MGR" install -y nautilus ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y nautilus ;;
        arch)        sudo pacman -S --noconfirm nautilus ;;
        suse)        sudo zypper install -y nautilus ;;
    esac
    info "Nautilus installed."
}

uninstall_nautilus() {
    info "Uninstalling Nautilus..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y nautilus ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y nautilus ;;
        arch)        sudo pacman -Rs --noconfirm nautilus ;;
        suse)        sudo zypper remove -y nautilus ;;
    esac
}

update_nautilus() {
    info "Updating Nautilus..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade nautilus ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y nautilus ;;
        arch)        sudo pacman -S --noconfirm nautilus ;;
        suse)        sudo zypper update -y nautilus ;;
    esac
}

get_version_nautilus() {
    _ver_from_pkg nautilus || echo ""
}
