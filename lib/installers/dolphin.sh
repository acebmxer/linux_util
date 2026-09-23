#!/bin/bash
# Dolphin (KDE) installer functions

# --- Dolphin ---

check_dolphin() { _check_standard dolphin dolphin ""; }

install_dolphin() {
    info "Installing Dolphin..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install dolphin ;;
        fedora)      pkg_install dolphin ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install dolphin 2>/dev/null || {
                warn "dolphin not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install dolphin ;;
        suse)        pkg_install dolphin ;;
    esac
    info "Dolphin installed."
}

uninstall_dolphin() {
    info "Uninstalling Dolphin..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove dolphin ;;
        fedora|rhel) pkg_remove dolphin ;;
        arch)        pkg_remove dolphin ;;
        suse)        pkg_remove dolphin ;;
    esac
}

update_dolphin() {
    info "Updating Dolphin..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade dolphin ;;
        fedora|rhel) pkg_upgrade dolphin ;;
        arch)        pkg_upgrade dolphin ;;
        suse)        pkg_upgrade dolphin ;;
    esac
}

get_version_dolphin() {
    _ver_from_pkg dolphin || echo ""
}
