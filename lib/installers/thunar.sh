#!/bin/bash
# Thunar (Xfce) installer functions

# --- Thunar ---

check_thunar() {
    # Fedora ships the package as "Thunar" (capital T); other distros use "thunar".
    _have_cmd thunar && return 0
    pkg_check_installed thunar && return 0
    pkg_check_installed Thunar && return 0
    return 1
}

install_thunar() {
    info "Installing Thunar..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install thunar ;;
        fedora)      pkg_install Thunar ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install Thunar 2>/dev/null || pkg_install thunar 2>/dev/null || {
                warn "thunar not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install thunar ;;
        suse)        pkg_install thunar ;;
    esac
    info "Thunar installed."
}

uninstall_thunar() {
    info "Uninstalling Thunar..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove thunar ;;
        fedora|rhel) pkg_remove Thunar 2>/dev/null || sudo "$PKG_MGR" remove -y thunar ;;
        arch)        pkg_remove thunar ;;
        suse)        pkg_remove thunar ;;
    esac
}

update_thunar() {
    info "Updating Thunar..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade thunar ;;
        fedora|rhel) pkg_upgrade Thunar 2>/dev/null || sudo "$PKG_MGR" upgrade -y thunar ;;
        arch)        pkg_upgrade thunar ;;
        suse)        pkg_upgrade thunar ;;
    esac
}

get_version_thunar() {
    _ver_from_pkg thunar || _ver_from_pkg Thunar || echo ""
}
