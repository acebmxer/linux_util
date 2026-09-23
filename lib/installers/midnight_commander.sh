#!/bin/bash
# Midnight Commander installer functions

# --- Midnight Commander ---

check_midnight_commander() { _check_standard mc mc ""; }

install_midnight_commander() {
    info "Installing Midnight Commander..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install mc ;;
        fedora|rhel) pkg_install mc ;;
        arch)        pkg_install mc ;;
        suse)        pkg_install mc ;;
    esac
    info "Midnight Commander installed."
}

uninstall_midnight_commander() {
    info "Uninstalling Midnight Commander..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove mc ;;
        fedora|rhel) pkg_remove mc ;;
        arch)        pkg_remove mc ;;
        suse)        pkg_remove mc ;;
    esac
}

update_midnight_commander() {
    info "Updating Midnight Commander..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade mc ;;
        fedora|rhel) pkg_upgrade mc ;;
        arch)        pkg_upgrade mc ;;
        suse)        pkg_upgrade mc ;;
    esac
}

get_version_midnight_commander() {
    _ver_from_pkg mc || _ver_from_cmd mc || echo ""
}
