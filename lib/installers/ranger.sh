#!/bin/bash
# Ranger installer functions

# --- Ranger ---

check_ranger() { _check_standard ranger ranger ""; }

install_ranger() {
    info "Installing Ranger..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y ranger ;;
        fedora)      sudo "$PKG_MGR" install -y ranger ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y ranger 2>/dev/null || {
                warn "ranger not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm ranger ;;
        suse)        sudo zypper install -y ranger ;;
    esac
    info "Ranger installed."
}

uninstall_ranger() {
    info "Uninstalling Ranger..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y ranger ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y ranger ;;
        arch)        sudo pacman -Rs --noconfirm ranger ;;
        suse)        sudo zypper remove -y ranger ;;
    esac
}

update_ranger() {
    info "Updating Ranger..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade ranger ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y ranger ;;
        arch)        sudo pacman -S --noconfirm ranger ;;
        suse)        sudo zypper update -y ranger ;;
    esac
}

get_version_ranger() {
    _ver_from_pkg ranger || _ver_from_cmd ranger || echo ""
}
