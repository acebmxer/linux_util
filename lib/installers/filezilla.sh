#!/bin/bash
# FileZilla installer functions

# --- FileZilla ---

check_filezilla() {
    command -v filezilla &>/dev/null || pkg_check_installed filezilla
}

install_filezilla() {
    info "Installing FileZilla..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt install -y filezilla ;;
        fedora)  sudo "$PKG_MGR" install -y filezilla ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y filezilla
            ;;
        arch)    sudo pacman -S --noconfirm filezilla ;;
        suse)    sudo zypper install -y filezilla ;;
    esac
    info "FileZilla installed."
}

uninstall_filezilla() {
    info "Uninstalling FileZilla..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y filezilla ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y filezilla ;;
        arch)    sudo pacman -Rs --noconfirm filezilla ;;
        suse)    sudo zypper remove -y filezilla ;;
    esac
    rm -rf "$HOME/.config/filezilla"
}

update_filezilla() {
    info "Updating FileZilla..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt update && sudo apt upgrade -y filezilla ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y filezilla ;;
        arch)    sudo pacman -S --noconfirm filezilla ;;
        suse)    sudo zypper update -y filezilla ;;
    esac
}

get_version_filezilla() {
    filezilla --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    pkg_get_version filezilla 2>/dev/null | sed 's/-.*//' || \
    echo ""
}
