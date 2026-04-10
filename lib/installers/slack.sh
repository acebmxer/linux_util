#!/bin/bash
# Slack team messaging installer functions

# --- Slack ---

check_slack() { _check_standard slack slack com.slack.Slack; }

install_slack() {
    info "Installing Slack..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmpfile
            tmpfile=$(mktemp /tmp/slack-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            # Fetch the latest Slack .deb download URL
            local url="https://downloads.slack-edge.com/desktop-releases/linux/x64/latest/slack-desktop-amd64.deb"
            if ! wget -qO "$tmpfile" "$url"; then
                warn "Direct .deb download failed. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.slack.Slack
                    return $?
                fi
                error "Slack installation failed. Install Flatpak and try again."
                return 1
            fi
            verify_download "$tmpfile" "deb" "Slack" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            if has_flatpak; then
                flatpak install -y flathub com.slack.Slack
            else
                error "Slack requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            aur_ensure slack-desktop
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.slack.Slack
            else
                error "Slack requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Slack installed."
}

uninstall_slack() {
    info "Uninstalling Slack..."
    if flatpak_is_installed "com.slack.Slack"; then
        flatpak uninstall -y com.slack.Slack
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y slack-desktop ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y slack 2>/dev/null || true ;;
            arch)
                aur_remove slack-desktop 2>/dev/null || \
                    sudo pacman -Rs --noconfirm slack-desktop 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/Slack"
}

update_slack() {
    info "Updating Slack..."
    if flatpak_is_installed "com.slack.Slack"; then
        flatpak update -y com.slack.Slack
    else
        case "$DISTRO_FAMILY" in
            debian)       install_slack ;;
            fedora|rhel)  install_slack ;;
            arch)         aur_ensure slack-desktop ;;
            suse)         install_slack ;;
        esac
    fi
}

get_version_slack() {
    _ver_from_pkg slack-desktop || _ver_from_flatpak com.slack.Slack || echo ""
}
