#!/bin/bash
# FileZilla installer functions

# --- FileZilla ---

check_filezilla() { _check_standard filezilla filezilla ""; }

install_filezilla() {
    info "Installing FileZilla..."
    case "$DISTRO_FAMILY" in
        debian)  pkg_install filezilla ;;
        fedora)  pkg_install filezilla ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install filezilla
            ;;
        arch)    pkg_install filezilla ;;
        suse)    pkg_install filezilla ;;
    esac
    info "FileZilla installed."
}

uninstall_filezilla() {
    info "Uninstalling FileZilla..."
    case "$DISTRO_FAMILY" in
        debian)  pkg_remove filezilla ;;
        fedora|rhel) pkg_remove filezilla ;;
        arch)    pkg_remove filezilla ;;
        suse)    pkg_remove filezilla ;;
    esac
    rm -rf "$HOME/.config/filezilla"
}

update_filezilla() {
    info "Updating FileZilla..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y --only-upgrade filezilla ;;
        fedora|rhel) pkg_upgrade filezilla ;;
        arch)    pkg_upgrade filezilla ;;
        suse)    pkg_upgrade filezilla ;;
    esac
}

get_version_filezilla() {
    _ver_from_cmd filezilla || _ver_from_pkg filezilla || echo ""
}
