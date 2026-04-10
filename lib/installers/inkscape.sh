#!/bin/bash
# Inkscape vector graphics editor installer functions

# --- Inkscape ---

check_inkscape() { _check_standard inkscape inkscape org.inkscape.Inkscape; }

install_inkscape() {
    info "Installing Inkscape..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y inkscape
            ;;
        fedora)
            sudo "$PKG_MGR" install -y inkscape
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y inkscape 2>/dev/null || {
                warn "inkscape not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub org.inkscape.Inkscape
                    return $?
                fi
                error "Inkscape requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm inkscape
            ;;
        suse)
            sudo zypper install -y inkscape
            ;;
    esac
    info "Inkscape installed."
}

uninstall_inkscape() {
    info "Uninstalling Inkscape..."
    if flatpak_is_installed "org.inkscape.Inkscape"; then
        flatpak uninstall -y org.inkscape.Inkscape
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y inkscape ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y inkscape ;;
            arch)        sudo pacman -Rs --noconfirm inkscape ;;
            suse)        sudo zypper remove -y inkscape ;;
        esac
    fi
    rm -rf "$HOME/.config/inkscape"
}

update_inkscape() {
    info "Updating Inkscape..."
    if flatpak_is_installed "org.inkscape.Inkscape"; then
        flatpak update -y org.inkscape.Inkscape
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade inkscape ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y inkscape ;;
            arch)        sudo pacman -S --noconfirm inkscape ;;
            suse)        sudo zypper update -y inkscape ;;
        esac
    fi
}

get_version_inkscape() {
    _ver_from_cmd inkscape || _ver_from_flatpak org.inkscape.Inkscape || _ver_from_pkg inkscape || echo ""
}
