#!/bin/bash
# GIMP installer functions

# --- GIMP ---

check_gimp() { _check_standard gimp gimp org.gimp.GIMP; }

install_gimp() {
    info "Installing GIMP..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt install -y gimp ;;
        fedora)  sudo "$PKG_MGR" install -y gimp ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y gimp
            ;;
        arch)    sudo pacman -S --noconfirm gimp ;;
        suse)    sudo zypper install -y gimp ;;
    esac
    info "GIMP installed."
}

uninstall_gimp() {
    info "Uninstalling GIMP..."
    if flatpak_is_installed "org.gimp.GIMP"; then
        flatpak uninstall -y --user org.gimp.GIMP 2>/dev/null || \
            sudo flatpak uninstall -y --system org.gimp.GIMP
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y gimp ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y gimp ;;
            arch)    sudo pacman -Rs --noconfirm gimp ;;
            suse)    sudo zypper remove -y gimp ;;
        esac
    fi
    rm -rf "$HOME/.config/GIMP"
}

update_gimp() {
    info "Updating GIMP..."
    if flatpak_is_installed "org.gimp.GIMP"; then
        flatpak update -y --user org.gimp.GIMP 2>/dev/null || \
            sudo flatpak update -y --system org.gimp.GIMP
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y --only-upgrade gimp ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y gimp ;;
            arch)    sudo pacman -S --noconfirm gimp ;;
            suse)    sudo zypper update -y gimp ;;
        esac
    fi
}

get_version_gimp() {
    _ver_from_cmd gimp || _ver_from_pkg gimp || echo ""
}
