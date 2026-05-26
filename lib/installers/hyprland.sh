#!/bin/bash
# Hyprland (Wayland) window manager installer functions

# --- Hyprland ---

check_hyprland() { _check_standard Hyprland hyprland ""; }

install_hyprland() {
    info "Installing Hyprland..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y hyprland 2>/dev/null || {
                warn "Hyprland not available in apt repos. Ubuntu 24.04+ ships it in universe; older releases require building from source."
                return 1
            }
            ;;
        fedora)      sudo "$PKG_MGR" install -y hyprland ;;
        rhel)
            warn "Hyprland is not packaged for RHEL-based distros (no EPEL build available)."
            return 1
            ;;
        arch)        sudo pacman -S --noconfirm hyprland ;;
        suse)
            sudo zypper install -y hyprland 2>/dev/null || {
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
        debian)      sudo apt purge --autoremove -y hyprland ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y hyprland ;;
        arch)        sudo pacman -Rs --noconfirm hyprland ;;
        suse)        sudo zypper remove -y hyprland ;;
    esac
}

update_hyprland() {
    info "Updating Hyprland..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade hyprland ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y hyprland ;;
        arch)        sudo pacman -S --noconfirm hyprland ;;
        suse)        sudo zypper update -y hyprland ;;
    esac
}

get_version_hyprland() {
    _ver_from_cmd Hyprland --version || _ver_from_pkg hyprland || echo ""
}
