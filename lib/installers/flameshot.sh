#!/bin/bash
# Flameshot screenshot tool installer functions

# --- Flameshot ---

check_flameshot() { _check_standard flameshot flameshot org.flameshot.Flameshot; }

install_flameshot() {
    info "Installing Flameshot..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y flameshot
            ;;
        fedora)
            sudo "$PKG_MGR" install -y flameshot
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y flameshot 2>/dev/null || {
                warn "flameshot not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.flameshot.Flameshot
                    return $?
                fi
                error "Flameshot requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm flameshot
            ;;
        suse)
            sudo zypper install -y flameshot
            ;;
    esac
    info "Flameshot installed."
    info "Tip: Bind 'flameshot gui' to a keyboard shortcut (e.g. Print Screen) for quick captures."
}

uninstall_flameshot() {
    info "Uninstalling Flameshot..."
    if flatpak_is_installed "org.flameshot.Flameshot"; then
        flatpak uninstall -y org.flameshot.Flameshot
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y flameshot ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y flameshot ;;
            arch)        sudo pacman -Rs --noconfirm flameshot ;;
            suse)        sudo zypper remove -y flameshot ;;
        esac
    fi
    rm -rf "$HOME/.config/flameshot"
}

update_flameshot() {
    info "Updating Flameshot..."
    if flatpak_is_installed "org.flameshot.Flameshot"; then
        flatpak update -y org.flameshot.Flameshot
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade flameshot ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y flameshot ;;
            arch)        sudo pacman -S --noconfirm flameshot ;;
            suse)        sudo zypper update -y flameshot ;;
        esac
    fi
}

get_version_flameshot() {
    _ver_from_cmd flameshot --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_flatpak org.flameshot.Flameshot || _ver_from_pkg flameshot || echo ""
}
