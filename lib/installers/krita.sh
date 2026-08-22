#!/bin/bash
# Krita digital painting application installer functions

# --- Krita ---

check_krita() { _check_standard krita krita org.kde.krita; }

install_krita() {
    info "Installing Krita..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y krita
            ;;
        fedora)
            sudo "$PKG_MGR" install -y krita
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
            sudo pacman -S --noconfirm krita
            ;;
        suse)
            sudo zypper install -y krita
            ;;
    esac
    info "Krita installed."
}

uninstall_krita() {
    info "Uninstalling Krita..."
    if flatpak_is_installed "org.kde.krita"; then
        flatpak uninstall -y org.kde.krita
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y krita ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y krita ;;
            arch)        sudo pacman -Rs --noconfirm krita ;;
            suse)        sudo zypper remove -y krita ;;
        esac
    fi
    rm -rf "$HOME/.config/kritarc" "$HOME/.local/share/krita"
}

update_krita() {
    info "Updating Krita..."
    if flatpak_is_installed "org.kde.krita"; then
        flatpak update -y org.kde.krita
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade krita ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y krita ;;
            arch)        sudo pacman -S --noconfirm krita ;;
            suse)        sudo zypper update -y krita ;;
        esac
    fi
}

get_version_krita() {
    _ver_from_snap krita || _ver_from_flatpak org.kde.krita || _ver_from_pkg krita || _ver_from_cmd krita || echo ""
}
