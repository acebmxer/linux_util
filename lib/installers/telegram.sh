#!/bin/bash
# Telegram Desktop installer functions

# --- Telegram Desktop ---

check_telegram() { _check_standard telegram-desktop telegram-desktop org.telegram.desktop; }

install_telegram() {
    info "Installing Telegram Desktop..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            if apt-cache show telegram-desktop &>/dev/null; then
                sudo apt install -y telegram-desktop
            elif has_snap; then
                info "telegram-desktop not in apt repos. Installing via snap..."
                sudo snap install telegram-desktop
            elif has_flatpak; then
                info "telegram-desktop not in apt repos. Installing via Flatpak..."
                sudo flatpak install -y flathub org.telegram.desktop
            else
                error "telegram-desktop not available via apt, snap, or Flatpak."
                return 1
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y telegram-desktop
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y telegram-desktop 2>/dev/null || {
                warn "telegram-desktop not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.telegram.desktop
                else
                    error "Telegram requires Flatpak on this system."
                    return 1
                fi
            }
            ;;
        arch)
            sudo pacman -S --noconfirm telegram-desktop
            ;;
        suse)
            sudo zypper install -y telegram-desktop 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub org.telegram.desktop
                else
                    error "Telegram requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "Telegram Desktop installed."
}

uninstall_telegram() {
    info "Uninstalling Telegram Desktop..."
    if flatpak_is_installed "org.telegram.desktop"; then
        flatpak uninstall -y --user org.telegram.desktop 2>/dev/null || \
            sudo flatpak uninstall -y --system org.telegram.desktop
    elif has_snap && snap list telegram-desktop &>/dev/null 2>&1; then
        sudo snap remove telegram-desktop
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y telegram-desktop ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y telegram-desktop ;;
            arch)    sudo pacman -Rs --noconfirm telegram-desktop ;;
            suse)    sudo zypper remove -y telegram-desktop ;;
        esac
    fi
    rm -rf "$HOME/.local/share/TelegramDesktop"
}

update_telegram() {
    info "Updating Telegram Desktop..."
    if flatpak_is_installed "org.telegram.desktop"; then
        flatpak update -y --user org.telegram.desktop 2>/dev/null || \
            sudo flatpak update -y --system org.telegram.desktop
    elif has_snap && snap list telegram-desktop &>/dev/null 2>&1; then
        sudo snap refresh telegram-desktop
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y --only-upgrade telegram-desktop ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y telegram-desktop ;;
            arch)    sudo pacman -S --noconfirm telegram-desktop ;;
            suse)    sudo zypper update -y telegram-desktop ;;
        esac
    fi
}

get_version_telegram() {
    # Do NOT call telegram-desktop --version — Qt GUI apps may launch a full window.
    _ver_from_pkg telegram-desktop || _ver_from_snap telegram-desktop || _ver_from_flatpak org.telegram.desktop || echo ""
}
