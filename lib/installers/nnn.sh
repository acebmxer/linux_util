#!/bin/bash
# nnn installer functions

# --- nnn ---

check_nnn() { _check_standard nnn nnn ""; }

install_nnn() {
    info "Installing nnn..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install nnn ;;
        fedora)      pkg_install nnn ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install nnn 2>/dev/null || {
                warn "nnn not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install nnn ;;
        suse)        pkg_install nnn ;;
    esac
    info "nnn installed."
}

uninstall_nnn() {
    info "Uninstalling nnn..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove nnn ;;
        fedora|rhel) pkg_remove nnn ;;
        arch)        pkg_remove nnn ;;
        suse)        pkg_remove nnn ;;
    esac
}

update_nnn() {
    info "Updating nnn..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade nnn ;;
        fedora|rhel) pkg_upgrade nnn ;;
        arch)        pkg_upgrade nnn ;;
        suse)        pkg_upgrade nnn ;;
    esac
}

get_version_nnn() {
    _ver_from_pkg nnn || _ver_from_cmd nnn -V || echo ""
}
