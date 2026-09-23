#!/bin/bash
# Caja (MATE) installer functions

# --- Caja ---

check_caja() { _check_standard caja caja ""; }

install_caja() {
    info "Installing Caja..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install caja ;;
        fedora)      pkg_install caja ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install caja 2>/dev/null || {
                warn "caja not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install caja ;;
        suse)        pkg_install caja ;;
    esac
    info "Caja installed."
}

uninstall_caja() {
    info "Uninstalling Caja..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove caja ;;
        fedora|rhel) pkg_remove caja ;;
        arch)        pkg_remove caja ;;
        suse)        pkg_remove caja ;;
    esac
}

update_caja() {
    info "Updating Caja..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade caja ;;
        fedora|rhel) pkg_upgrade caja ;;
        arch)        pkg_upgrade caja ;;
        suse)        pkg_upgrade caja ;;
    esac
}

get_version_caja() {
    _ver_from_pkg caja || echo ""
}
