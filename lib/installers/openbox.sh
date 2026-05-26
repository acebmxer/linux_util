#!/bin/bash
# Openbox window manager installer functions

# --- Openbox ---

check_openbox() { _check_standard openbox openbox ""; }

install_openbox() {
    info "Installing Openbox..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y openbox obconf ;;
        fedora)      sudo "$PKG_MGR" install -y openbox obconf ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y openbox 2>/dev/null || {
                warn "openbox not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm openbox obconf ;;
        suse)        sudo zypper install -y openbox obconf ;;
    esac
    info "Openbox installed. Log out and select Openbox from your display manager."
}

uninstall_openbox() {
    info "Uninstalling Openbox..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y openbox obconf ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y openbox obconf ;;
        arch)        sudo pacman -Rs --noconfirm openbox obconf ;;
        suse)        sudo zypper remove -y openbox obconf ;;
    esac
}

update_openbox() {
    info "Updating Openbox..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade openbox obconf ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y openbox obconf ;;
        arch)        sudo pacman -S --noconfirm openbox obconf ;;
        suse)        sudo zypper update -y openbox obconf ;;
    esac
}

get_version_openbox() {
    _ver_from_cmd openbox --version || _ver_from_pkg openbox || echo ""
}
