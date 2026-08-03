#!/bin/bash
# Snapper GUI installer functions (Debian/Ubuntu and Arch)

# --- Snapper GUI ---

check_snapper_gui() {
    _have_cmd snapper-gui
}

install_snapper_gui() {
    echo "Installing Snapper GUI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y snapper-gui || return 1
            ;;
        arch)
            aur_ensure snapper-gui || return 1
            ;;
        *)
            warn "Snapper GUI is not available for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Arch/Manjaro."
            return 1
            ;;
    esac
    echo "Snapper GUI installed successfully."
}

uninstall_snapper_gui() {
    echo "Uninstalling Snapper GUI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y snapper-gui
            sudo apt autoclean
            ;;
        arch)
            sudo pacman -Rs --noconfirm snapper-gui 2>/dev/null || true
            ;;
    esac
}

update_snapper_gui() {
    echo "Updating Snapper GUI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade snapper-gui
            ;;
        arch)
            pkg_upgrade snapper-gui
            ;;
    esac
}

get_version_snapper_gui() {
    _ver_from_pkg snapper-gui || echo ""
}
