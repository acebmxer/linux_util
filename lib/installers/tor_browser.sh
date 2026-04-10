#!/bin/bash
# Tor Browser installer functions (via torbrowser-launcher)

# --- Tor Browser ---

check_tor_browser() {
    command -v torbrowser-launcher &>/dev/null || \
        flatpak_is_installed "com.github.micahflee.torbrowser-launcher"
}

install_tor_browser() {
    info "Installing Tor Browser (via torbrowser-launcher)..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y torbrowser-launcher
            ;;
        fedora)
            sudo "$PKG_MGR" install -y torbrowser-launcher
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y torbrowser-launcher 2>/dev/null || {
                warn "torbrowser-launcher not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.github.micahflee.torbrowser-launcher
                    return $?
                fi
                error "Tor Browser requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            aur_ensure torbrowser-launcher
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.github.micahflee.torbrowser-launcher
            else
                error "Tor Browser requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Tor Browser launcher installed."
    info "Run 'torbrowser-launcher' to download and start Tor Browser."
}

uninstall_tor_browser() {
    info "Uninstalling Tor Browser..."
    if flatpak_is_installed "com.github.micahflee.torbrowser-launcher"; then
        flatpak uninstall -y com.github.micahflee.torbrowser-launcher
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y torbrowser-launcher ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y torbrowser-launcher ;;
            arch)
                aur_remove torbrowser-launcher 2>/dev/null || \
                    sudo pacman -Rs --noconfirm torbrowser-launcher 2>/dev/null || true
                ;;
            suse)        sudo zypper remove -y torbrowser-launcher 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.local/share/torbrowser" "$HOME/.config/torbrowser"
}

update_tor_browser() {
    info "Updating Tor Browser..."
    if flatpak_is_installed "com.github.micahflee.torbrowser-launcher"; then
        flatpak update -y com.github.micahflee.torbrowser-launcher
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade torbrowser-launcher ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y torbrowser-launcher ;;
            arch)        aur_ensure torbrowser-launcher ;;
            suse)        sudo zypper update -y torbrowser-launcher 2>/dev/null || true ;;
        esac
    fi
}

get_version_tor_browser() {
    _ver_from_cmd torbrowser-launcher || \
        _ver_from_flatpak com.github.micahflee.torbrowser-launcher || \
        _ver_from_pkg torbrowser-launcher || echo ""
}
