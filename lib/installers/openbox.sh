#!/bin/bash
# Openbox window manager installer functions

# --- Openbox ---

check_openbox() { _check_standard openbox openbox ""; }

install_openbox() {
    info "Installing Openbox..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install openbox obconf ;;
        fedora)      pkg_install openbox obconf ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install openbox 2>/dev/null || {
                warn "openbox not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install openbox obconf ;;
        suse)        pkg_install openbox obconf ;;
    esac
    info "Openbox installed. Log out and select Openbox from your display manager."
}

uninstall_openbox() {
    info "Uninstalling Openbox..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove openbox obconf ;;
        fedora|rhel) pkg_remove openbox obconf ;;
        arch)        pkg_remove openbox obconf ;;
        suse)        pkg_remove openbox obconf ;;
    esac
}

update_openbox() {
    info "Updating Openbox..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade openbox obconf ;;
        fedora|rhel) pkg_upgrade openbox obconf ;;
        arch)        pkg_upgrade openbox obconf ;;
        suse)        pkg_upgrade openbox obconf ;;
    esac
}

get_version_openbox() {
    _ver_from_cmd openbox --version || _ver_from_pkg openbox || echo ""
}
