#!/bin/bash
# Filelight installer functions

# --- Filelight ---

check_filelight() { _check_standard filelight filelight ""; }

install_filelight() {
    info "Installing Filelight..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install filelight
            ;;
        fedora)
            pkg_install filelight
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install filelight 2>/dev/null || {
                warn "filelight not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)
            pkg_install filelight
            ;;
        suse)
            pkg_install filelight
            ;;
    esac
    info "Filelight installed."
}

uninstall_filelight() {
    info "Uninstalling Filelight..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove filelight ;;
        fedora|rhel) pkg_remove filelight ;;
        arch)        pkg_remove filelight ;;
        suse)        pkg_remove filelight ;;
    esac
}

update_filelight() {
    info "Updating Filelight..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade filelight ;;
        fedora|rhel) pkg_upgrade filelight ;;
        arch)        pkg_upgrade filelight ;;
        suse)        pkg_upgrade filelight ;;
    esac
}

get_version_filelight() {
    _ver_from_pkg filelight || echo ""
}
