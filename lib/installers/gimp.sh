#!/bin/bash
# GIMP installer functions

# --- GIMP ---

check_gimp() { _check_standard gimp gimp org.gimp.GIMP; }

install_gimp() {
    info "Installing GIMP..."
    case "$DISTRO_FAMILY" in
        debian)  pkg_install gimp ;;
        fedora)  pkg_install gimp ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install gimp
            ;;
        arch)    pkg_install gimp ;;
        suse)    pkg_install gimp ;;
    esac
    info "GIMP installed."
}

uninstall_gimp() {
    info "Uninstalling GIMP..."
    if flatpak_is_installed "org.gimp.GIMP"; then
        flatpak uninstall -y --user org.gimp.GIMP 2>/dev/null || \
            sudo flatpak uninstall -y --system org.gimp.GIMP
    else
        case "$DISTRO_FAMILY" in
            debian)  pkg_remove gimp ;;
            fedora|rhel) pkg_remove gimp ;;
            arch)    pkg_remove gimp ;;
            suse)    pkg_remove gimp ;;
        esac
    fi
    rm -rf "$HOME/.config/GIMP"
}

update_gimp() {
    info "Updating GIMP..."
    if flatpak_is_installed "org.gimp.GIMP"; then
        flatpak update -y --user org.gimp.GIMP 2>/dev/null || \
            sudo flatpak update -y --system org.gimp.GIMP
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y --only-upgrade gimp ;;
            fedora|rhel) pkg_upgrade gimp ;;
            arch)    pkg_upgrade gimp ;;
            suse)    pkg_upgrade gimp ;;
        esac
    fi
}

get_version_gimp() {
    _ver_from_cmd gimp || _ver_from_pkg gimp || echo ""
}
