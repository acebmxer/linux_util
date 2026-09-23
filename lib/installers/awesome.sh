#!/bin/bash
# awesome window manager installer functions

# --- awesome ---

check_awesome() { _check_standard awesome awesome ""; }

install_awesome() {
    info "Installing awesome..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install awesome ;;
        fedora)      pkg_install awesome ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install awesome 2>/dev/null || {
                warn "awesome not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install awesome ;;
        suse)        pkg_install awesome ;;
    esac
    info "awesome installed. Log out and select awesome from your display manager."
}

uninstall_awesome() {
    info "Uninstalling awesome..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove awesome ;;
        fedora|rhel) pkg_remove awesome ;;
        arch)        pkg_remove awesome ;;
        suse)        pkg_remove awesome ;;
    esac
}

update_awesome() {
    info "Updating awesome..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade awesome ;;
        fedora|rhel) pkg_upgrade awesome ;;
        arch)        pkg_upgrade awesome ;;
        suse)        pkg_upgrade awesome ;;
    esac
}

get_version_awesome() {
    _ver_from_cmd awesome --version || _ver_from_pkg awesome || echo ""
}
