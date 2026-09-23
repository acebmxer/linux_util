#!/bin/bash
# GParted installer functions

# --- GParted ---

check_gparted() { _check_standard gparted gparted ""; }

install_gparted() {
    info "Installing GParted..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install gparted
            ;;
        fedora)
            pkg_install gparted
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install gparted 2>/dev/null || {
                warn "gparted not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)
            pkg_install gparted
            ;;
        suse)
            pkg_install gparted
            ;;
    esac
    info "GParted installed."
}

uninstall_gparted() {
    info "Uninstalling GParted..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove gparted ;;
        fedora|rhel) pkg_remove gparted ;;
        arch)        pkg_remove gparted ;;
        suse)        pkg_remove gparted ;;
    esac
}

update_gparted() {
    info "Updating GParted..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade gparted ;;
        fedora|rhel) pkg_upgrade gparted ;;
        arch)        pkg_upgrade gparted ;;
        suse)        pkg_upgrade gparted ;;
    esac
}

get_version_gparted() {
    _ver_from_pkg gparted || echo ""
}
