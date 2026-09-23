#!/bin/bash
# Nemo (Cinnamon) installer functions

# --- Nemo ---

check_nemo() { _check_standard nemo nemo ""; }

install_nemo() {
    info "Installing Nemo..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install nemo ;;
        fedora)      pkg_install nemo ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install nemo 2>/dev/null || {
                warn "nemo not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install nemo ;;
        suse)        pkg_install nemo ;;
    esac
    info "Nemo installed."
}

uninstall_nemo() {
    info "Uninstalling Nemo..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove nemo ;;
        fedora|rhel) pkg_remove nemo ;;
        arch)        pkg_remove nemo ;;
        suse)        pkg_remove nemo ;;
    esac
}

update_nemo() {
    info "Updating Nemo..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade nemo ;;
        fedora|rhel) pkg_upgrade nemo ;;
        arch)        pkg_upgrade nemo ;;
        suse)        pkg_upgrade nemo ;;
    esac
}

get_version_nemo() {
    _ver_from_pkg nemo || echo ""
}
