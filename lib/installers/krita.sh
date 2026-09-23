#!/bin/bash
# Krita digital painting application installer functions

# --- Krita ---

check_krita() { _check_standard krita krita org.kde.krita; }

install_krita() {
    info "Installing Krita..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install krita
            ;;
        fedora)
            pkg_install krita
            ;;
        rhel)
            if has_flatpak; then
                sudo flatpak install -y flathub org.kde.krita
            else
                error "Krita requires Flatpak on this RHEL-based system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            pkg_install krita
            ;;
        suse)
            pkg_install krita
            ;;
    esac
    info "Krita installed."
}

uninstall_krita() {
    info "Uninstalling Krita..."
    if flatpak_is_installed "org.kde.krita"; then
        flatpak uninstall -y --user org.kde.krita 2>/dev/null || \
            sudo flatpak uninstall -y --system org.kde.krita
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove krita ;;
            fedora|rhel) pkg_remove krita ;;
            arch)        pkg_remove krita ;;
            suse)        pkg_remove krita ;;
        esac
    fi
    rm -rf "$HOME/.config/kritarc" "$HOME/.local/share/krita"
}

update_krita() {
    info "Updating Krita..."
    if flatpak_is_installed "org.kde.krita"; then
        flatpak update -y --user org.kde.krita 2>/dev/null || \
            sudo flatpak update -y --system org.kde.krita
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade krita ;;
            fedora|rhel) pkg_upgrade krita ;;
            arch)        pkg_upgrade krita ;;
            suse)        pkg_upgrade krita ;;
        esac
    fi
}

get_version_krita() {
    _ver_from_snap krita || _ver_from_flatpak org.kde.krita || _ver_from_pkg krita || _ver_from_cmd krita || echo ""
}
