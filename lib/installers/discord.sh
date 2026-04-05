#!/bin/bash
# Discord installer functions

# --- Discord ---

check_discord() { _check_standard discord discord com.discordapp.Discord; }

install_discord() {
    info "Installing Discord..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmpfile
            tmpfile=$(mktemp /tmp/discord-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://discord.com/api/download?platform=linux&format=deb"; then
                error "Failed to download Discord .deb package."
                return 1
            fi
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            if has_flatpak; then
                flatpak install -y flathub com.discordapp.Discord
            else
                local tmpfile
                tmpfile=$(mktemp /tmp/discord-XXXXXX.tar.gz)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "https://discord.com/api/download?platform=linux&format=tar.gz" || {
                    error "Failed to download Discord archive."
                    return 1
                }
                sudo mkdir -p /opt/discord
                sudo tar -xzf "$tmpfile" -C /opt/discord --strip-components=1
                sudo ln -sf /opt/discord/Discord /usr/local/bin/discord
                # Install desktop entry
                sudo cp /opt/discord/discord.desktop /usr/share/applications/ 2>/dev/null || true
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm discord
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.discordapp.Discord
            else
                error "Discord requires Flatpak on openSUSE. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Discord installed."
}

uninstall_discord() {
    info "Uninstalling Discord..."
    if flatpak_is_installed "com.discordapp.Discord"; then
        flatpak uninstall -y com.discordapp.Discord
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y discord
                ;;
            fedora|rhel)
                sudo rm -f /usr/local/bin/discord
                sudo rm -rf /opt/discord
                sudo rm -f /usr/share/applications/discord.desktop
                ;;
            arch)
                sudo pacman -Rs --noconfirm discord
                ;;
        esac
    fi
    rm -rf "$HOME/.config/discord"
}

update_discord() {
    info "Updating Discord..."
    if flatpak_is_installed "com.discordapp.Discord"; then
        flatpak update -y com.discordapp.Discord
    else
        case "$DISTRO_FAMILY" in
            debian)       install_discord ;;
            fedora|rhel)  install_discord ;;
            arch)         sudo pacman -S --noconfirm discord ;;
        esac
    fi
}

get_version_discord() {
    _ver_from_flatpak com.discordapp.Discord || _ver_from_pkg discord || echo ""
}
