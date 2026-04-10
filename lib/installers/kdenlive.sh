#!/bin/bash
# Kdenlive video editor installer functions

# --- Kdenlive ---

check_kdenlive() { _check_standard kdenlive kdenlive org.kde.kdenlive; }

install_kdenlive() {
    info "Installing Kdenlive..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y kdenlive
            ;;
        fedora)
            sudo "$PKG_MGR" install -y kdenlive
            ;;
        rhel)
            if has_flatpak; then
                flatpak install -y flathub org.kde.kdenlive
            else
                error "Kdenlive requires Flatpak on this RHEL-based system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm kdenlive
            ;;
        suse)
            sudo zypper install -y kdenlive 2>/dev/null || {
                if has_flatpak; then
                    flatpak install -y flathub org.kde.kdenlive
                else
                    error "Kdenlive requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "Kdenlive installed."
}

uninstall_kdenlive() {
    info "Uninstalling Kdenlive..."
    if flatpak_is_installed "org.kde.kdenlive"; then
        flatpak uninstall -y org.kde.kdenlive
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y kdenlive ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y kdenlive ;;
            arch)        sudo pacman -Rs --noconfirm kdenlive ;;
            suse)        sudo zypper remove -y kdenlive ;;
        esac
    fi
    rm -rf "$HOME/.config/kdenliverc" "$HOME/.local/share/kdenlive"
}

update_kdenlive() {
    info "Updating Kdenlive..."
    if flatpak_is_installed "org.kde.kdenlive"; then
        flatpak update -y org.kde.kdenlive
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade kdenlive ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y kdenlive ;;
            arch)        sudo pacman -S --noconfirm kdenlive ;;
            suse)        sudo zypper update -y kdenlive ;;
        esac
    fi
}

get_version_kdenlive() {
    _ver_from_flatpak org.kde.kdenlive || _ver_from_pkg kdenlive || echo ""
}
