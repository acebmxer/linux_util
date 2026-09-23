#!/bin/bash
# Sway (Wayland) window manager installer functions

# --- Sway ---

check_sway() { _check_standard sway sway ""; }

install_sway() {
    info "Installing Sway..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install sway ;;
        fedora)      pkg_install sway ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install sway 2>/dev/null || {
                warn "Sway not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install sway ;;
        suse)        pkg_install sway ;;
    esac
    info "Sway installed. Log out and select Sway from your display manager."
}

uninstall_sway() {
    info "Uninstalling Sway..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove sway ;;
        fedora|rhel) pkg_remove sway ;;
        arch)        pkg_remove sway ;;
        suse)        pkg_remove sway ;;
    esac
}

update_sway() {
    info "Updating Sway..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade sway ;;
        fedora|rhel) pkg_upgrade sway ;;
        arch)        pkg_upgrade sway ;;
        suse)        pkg_upgrade sway ;;
    esac
}

get_version_sway() {
    _ver_from_cmd sway --version || _ver_from_pkg sway || echo ""
}
