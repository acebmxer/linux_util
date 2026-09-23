#!/bin/bash
# Tor Browser installer functions (via torbrowser-launcher)

# --- Tor Browser ---

check_tor_browser() {
    _have_cmd torbrowser-launcher || \
        flatpak_is_installed "com.github.micahflee.torbrowser-launcher"
}

install_tor_browser() {
    info "Installing Tor Browser (via torbrowser-launcher)..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install torbrowser-launcher
            ;;
        fedora)
            pkg_install torbrowser-launcher
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install torbrowser-launcher 2>/dev/null || {
                warn "torbrowser-launcher not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub com.github.micahflee.torbrowser-launcher
                    return $?
                fi
                error "Tor Browser requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            repo_or_aur torbrowser-launcher
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub com.github.micahflee.torbrowser-launcher
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
        flatpak uninstall -y --user com.github.micahflee.torbrowser-launcher 2>/dev/null || \
            sudo flatpak uninstall -y --system com.github.micahflee.torbrowser-launcher
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove torbrowser-launcher ;;
            fedora|rhel) pkg_remove torbrowser-launcher ;;
            arch)
                aur_remove torbrowser-launcher 2>/dev/null || \
                    pkg_remove torbrowser-launcher 2>/dev/null || true
                ;;
            suse)        pkg_remove torbrowser-launcher 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.local/share/torbrowser" "$HOME/.config/torbrowser"
}

update_tor_browser() {
    info "Updating Tor Browser..."
    if flatpak_is_installed "com.github.micahflee.torbrowser-launcher"; then
        flatpak update -y --user com.github.micahflee.torbrowser-launcher 2>/dev/null || \
            sudo flatpak update -y --system com.github.micahflee.torbrowser-launcher
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade torbrowser-launcher ;;
            fedora|rhel) pkg_upgrade torbrowser-launcher ;;
            arch)        repo_or_aur torbrowser-launcher ;;
            suse)        pkg_upgrade torbrowser-launcher 2>/dev/null || true ;;
        esac
    fi
}

get_version_tor_browser() {
    _ver_from_cmd torbrowser-launcher || \
        _ver_from_flatpak com.github.micahflee.torbrowser-launcher || \
        _ver_from_pkg torbrowser-launcher || echo ""
}
