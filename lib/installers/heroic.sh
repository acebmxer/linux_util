#!/bin/bash
# Heroic Games Launcher installer functions

# --- Heroic Games Launcher ---

check_heroic() { _check_standard heroic heroic com.heroicgameslauncher.hgl; }

_heroic_latest_url() {
    local ext="$1"  # deb or rpm
    curl -fsSL "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext"'(?=")' | head -1
}

install_heroic() {
    info "Installing Heroic Games Launcher..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_heroic_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find Heroic .deb release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/heroic-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Heroic .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Heroic" || return 1
            github_verify_checksum "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local url
            url=$(_heroic_latest_url "rpm")
            if [[ -z "$url" ]]; then
                error "Could not find Heroic .rpm release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/heroic-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Heroic .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Heroic" || return 1
            github_verify_checksum "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            flatpak_or_aur com.heroicgameslauncher.hgl heroic-games-launcher-bin
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.heroicgameslauncher.hgl
            else
                error "Heroic requires Flatpak on openSUSE. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Heroic Games Launcher installed."
}

uninstall_heroic() {
    info "Uninstalling Heroic Games Launcher..."
    if flatpak_is_installed "com.heroicgameslauncher.hgl"; then
        flatpak uninstall -y com.heroicgameslauncher.hgl
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y heroic
                ;;
            fedora|rhel)
                sudo "$PKG_MGR" remove -y heroic
                ;;
            arch)
                aur_remove heroic-games-launcher-bin 2>/dev/null || \
                    sudo pacman -Rs --noconfirm heroic 2>/dev/null || true
                ;;
            suse)
                flatpak uninstall -y com.heroicgameslauncher.hgl 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/heroic"
}

update_heroic() {
    info "Updating Heroic Games Launcher..."
    if flatpak_is_installed "com.heroicgameslauncher.hgl"; then
        flatpak update -y com.heroicgameslauncher.hgl
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_heroic ;;
            arch)
                aur_ensure heroic-games-launcher-bin
                ;;
        esac
    fi
}

get_version_heroic() {
    # Do NOT call heroic --version — Electron apps launch a full GUI window.
    _ver_from_pkg heroic || _ver_from_flatpak com.heroicgameslauncher.hgl || echo ""
}
