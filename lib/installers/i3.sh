#!/bin/bash
# i3 window manager installer functions

# --- i3 ---

check_i3() { _check_standard i3 i3 ""; }

install_i3() {
    info "Installing i3..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y i3 ;;
        fedora)      sudo "$PKG_MGR" install -y i3 ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y i3 2>/dev/null || {
                warn "i3 not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm i3-wm ;;
        suse)        sudo zypper install -y i3 ;;
    esac
    info "i3 installed. Log out and select i3 from your display manager."
}

uninstall_i3() {
    info "Uninstalling i3..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y i3 ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y i3 ;;
        arch)        sudo pacman -Rs --noconfirm i3-wm ;;
        suse)        sudo zypper remove -y i3 ;;
    esac
}

update_i3() {
    info "Updating i3..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade i3 ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y i3 ;;
        arch)        sudo pacman -S --noconfirm i3-wm ;;
        suse)        sudo zypper update -y i3 ;;
    esac
}

get_version_i3() {
    _ver_from_cmd i3 --version || _ver_from_pkg i3 || _ver_from_pkg i3-wm || echo ""
}
