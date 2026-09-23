#!/bin/bash
# Ranger installer functions

# --- Ranger ---

check_ranger() { _check_standard ranger ranger ""; }

install_ranger() {
    info "Installing Ranger..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install ranger ;;
        fedora)      pkg_install ranger ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install ranger 2>/dev/null || {
                warn "ranger not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install ranger ;;
        suse)        pkg_install ranger ;;
    esac
    info "Ranger installed."
}

uninstall_ranger() {
    info "Uninstalling Ranger..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove ranger ;;
        fedora|rhel) pkg_remove ranger ;;
        arch)        pkg_remove ranger ;;
        suse)        pkg_remove ranger ;;
    esac
}

update_ranger() {
    info "Updating Ranger..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade ranger ;;
        fedora|rhel) pkg_upgrade ranger ;;
        arch)        pkg_upgrade ranger ;;
        suse)        pkg_upgrade ranger ;;
    esac
}

get_version_ranger() {
    _ver_from_pkg ranger || _ver_from_cmd ranger || echo ""
}
