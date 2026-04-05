#!/bin/bash
# GIMP installer functions

# --- GIMP ---

check_gimp() {
    command -v gimp &>/dev/null || \
        pkg_check_installed gimp || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "org.gimp.GIMP")
}

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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "org.gimp.GIMP"; then
        flatpak uninstall -y org.gimp.GIMP
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "org.gimp.GIMP"; then
        flatpak update -y org.gimp.GIMP
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt update && sudo apt upgrade -y gimp ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y gimp ;;
            arch)    sudo pacman -S --noconfirm gimp ;;
            suse)    sudo zypper update -y gimp ;;
        esac
    fi
}

get_version_gimp() {
    gimp --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    pkg_get_version gimp 2>/dev/null | sed 's/-.*//' || \
    echo ""
}
