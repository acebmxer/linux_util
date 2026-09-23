#!/bin/bash
# Nautilus (GNOME Files) installer functions

# --- Nautilus ---

check_nautilus() { _check_standard nautilus nautilus ""; }

install_nautilus() {
    info "Installing Nautilus..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install nautilus ;;
        fedora)      pkg_install nautilus ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install nautilus ;;
        arch)        pkg_install nautilus ;;
        suse)        pkg_install nautilus ;;
    esac
    info "Nautilus installed."
}

uninstall_nautilus() {
    info "Uninstalling Nautilus..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove nautilus ;;
        fedora|rhel) pkg_remove nautilus ;;
        arch)        pkg_remove nautilus ;;
        suse)        pkg_remove nautilus ;;
    esac
}

update_nautilus() {
    info "Updating Nautilus..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade nautilus ;;
        fedora|rhel) pkg_upgrade nautilus ;;
        arch)        pkg_upgrade nautilus ;;
        suse)        pkg_upgrade nautilus ;;
    esac
}

get_version_nautilus() {
    _ver_from_pkg nautilus || echo ""
}
