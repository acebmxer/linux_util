#!/bin/bash
# Hyprland (Wayland) window manager installer functions

# --- Hyprland ---

check_hyprland() { _check_standard Hyprland hyprland ""; }

install_hyprland() {
    info "Installing Hyprland..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install hyprland 2>/dev/null || {
                warn "Hyprland not available in apt repos. Ubuntu 24.04+ ships it in universe; older releases require building from source."
                return 1
            }
            ;;
        fedora)      pkg_install hyprland ;;
        rhel)
            warn "Hyprland is not packaged for RHEL-based distros (no EPEL build available)."
            return 1
            ;;
        arch)        pkg_install hyprland ;;
        suse)
            pkg_install hyprland 2>/dev/null || {
                warn "Hyprland is only packaged for openSUSE Tumbleweed."
                return 1
            }
            ;;
    esac
    info "Hyprland installed. Log out and select Hyprland from your display manager."
}

uninstall_hyprland() {
    info "Uninstalling Hyprland..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove hyprland ;;
        fedora|rhel) pkg_remove hyprland ;;
        arch)        pkg_remove hyprland ;;
        suse)        pkg_remove hyprland ;;
    esac
}

update_hyprland() {
    info "Updating Hyprland..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade hyprland ;;
        fedora|rhel) pkg_upgrade hyprland ;;
        arch)        pkg_upgrade hyprland ;;
        suse)        pkg_upgrade hyprland ;;
    esac
}

get_version_hyprland() {
    _ver_from_cmd Hyprland --version || _ver_from_pkg hyprland || echo ""
}
