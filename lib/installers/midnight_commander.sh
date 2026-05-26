#!/bin/bash
# Midnight Commander installer functions

# --- Midnight Commander ---

check_midnight_commander() { _check_standard mc mc ""; }

install_midnight_commander() {
    info "Installing Midnight Commander..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y mc ;;
        fedora|rhel) sudo "$PKG_MGR" install -y mc ;;
        arch)        sudo pacman -S --noconfirm mc ;;
        suse)        sudo zypper install -y mc ;;
    esac
    info "Midnight Commander installed."
}

uninstall_midnight_commander() {
    info "Uninstalling Midnight Commander..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y mc ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y mc ;;
        arch)        sudo pacman -Rs --noconfirm mc ;;
        suse)        sudo zypper remove -y mc ;;
    esac
}

update_midnight_commander() {
    info "Updating Midnight Commander..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade mc ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y mc ;;
        arch)        sudo pacman -S --noconfirm mc ;;
        suse)        sudo zypper update -y mc ;;
    esac
}

get_version_midnight_commander() {
    _ver_from_pkg mc || _ver_from_cmd mc || echo ""
}
