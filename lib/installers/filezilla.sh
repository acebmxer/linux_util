#!/bin/bash
# FileZilla installer functions

# --- FileZilla ---

check_filezilla() { _check_standard filezilla filezilla ""; }

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
        debian)  sudo apt-get install -y --only-upgrade filezilla ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y filezilla ;;
        arch)    sudo pacman -S --noconfirm filezilla ;;
        suse)    sudo zypper update -y filezilla ;;
    esac
}

get_version_filezilla() {
    _ver_from_cmd filezilla || _ver_from_pkg filezilla || echo ""
}
