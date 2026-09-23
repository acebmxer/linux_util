#!/bin/bash
# Kdenlive video editor installer functions

# --- Kdenlive ---

check_kdenlive() { _check_standard kdenlive kdenlive org.kde.kdenlive; }

install_kdenlive() {
    info "Installing Kdenlive..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install kdenlive
            ;;
        fedora)
            pkg_install kdenlive
            ;;
        rhel)
            if has_flatpak; then
                sudo flatpak install -y flathub org.kde.kdenlive
            else
                error "Kdenlive requires Flatpak on this RHEL-based system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            pkg_install kdenlive
            ;;
        suse)
            pkg_install kdenlive 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub org.kde.kdenlive
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
        flatpak uninstall -y --user org.kde.kdenlive 2>/dev/null || \
            sudo flatpak uninstall -y --system org.kde.kdenlive
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove kdenlive ;;
            fedora|rhel) pkg_remove kdenlive ;;
            arch)        pkg_remove kdenlive ;;
            suse)        pkg_remove kdenlive ;;
        esac
    fi
    rm -rf "$HOME/.config/kdenliverc" "$HOME/.local/share/kdenlive"
}

update_kdenlive() {
    info "Updating Kdenlive..."
    if flatpak_is_installed "org.kde.kdenlive"; then
        flatpak update -y --user org.kde.kdenlive 2>/dev/null || \
            sudo flatpak update -y --system org.kde.kdenlive
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade kdenlive ;;
            fedora|rhel) pkg_upgrade kdenlive ;;
            arch)        pkg_upgrade kdenlive ;;
            suse)        pkg_upgrade kdenlive ;;
        esac
    fi
}

get_version_kdenlive() {
    _ver_from_flatpak org.kde.kdenlive || _ver_from_pkg kdenlive || echo ""
}
