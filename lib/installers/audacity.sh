#!/bin/bash
# Audacity audio editor installer functions

# --- Audacity ---

check_audacity() { _check_standard audacity audacity org.audacityteam.Audacity; }

install_audacity() {
    info "Installing Audacity..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y audacity
            ;;
        fedora)
            sudo "$PKG_MGR" install -y audacity
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y audacity 2>/dev/null || {
                warn "audacity not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.audacityteam.Audacity
                    return $?
                fi
                error "Audacity requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm audacity
            ;;
        suse)
            sudo zypper install -y audacity 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub org.audacityteam.Audacity
                else
                    error "Audacity requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "Audacity installed."
}

uninstall_audacity() {
    info "Uninstalling Audacity..."
    if flatpak_is_installed "org.audacityteam.Audacity"; then
        flatpak uninstall -y org.audacityteam.Audacity
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y audacity ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y audacity ;;
            arch)        sudo pacman -Rs --noconfirm audacity ;;
            suse)        sudo zypper remove -y audacity ;;
        esac
    fi
    rm -rf "$HOME/.config/audacity"
}

update_audacity() {
    info "Updating Audacity..."
    if flatpak_is_installed "org.audacityteam.Audacity"; then
        flatpak update -y org.audacityteam.Audacity
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade audacity ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y audacity ;;
            arch)        sudo pacman -S --noconfirm audacity ;;
            suse)        sudo zypper update -y audacity ;;
        esac
    fi
}

get_version_audacity() {
    _ver_from_cmd audacity || _ver_from_flatpak org.audacityteam.Audacity || _ver_from_pkg audacity || echo ""
}
