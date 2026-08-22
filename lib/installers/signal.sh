#!/bin/bash
# Signal Desktop installer functions

# --- Signal Desktop ---

check_signal() { _check_standard signal-desktop signal-desktop org.signal.Signal; }

install_signal() {
    info "Installing Signal Desktop..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official Signal apt repository
            _add_apt_repo \
                "https://updates.signal.org/desktop/apt/keys.asc" \
                "/etc/apt/keyrings/signal-desktop-keyring.gpg" \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" \
                "/etc/apt/sources.list.d/signal-xenial.list"
            sudo apt install -y signal-desktop
            ;;
        fedora|rhel|suse)
            if has_flatpak; then
                sudo flatpak install -y flathub org.signal.Signal
            else
                error "Signal requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            repo_or_aur signal-desktop
            ;;
    esac
    info "Signal Desktop installed."
}

uninstall_signal() {
    info "Uninstalling Signal Desktop..."
    if flatpak_is_installed "org.signal.Signal"; then
        flatpak uninstall -y org.signal.Signal
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y signal-desktop
                sudo rm -f /etc/apt/sources.list.d/signal-xenial.list
                sudo rm -f /etc/apt/keyrings/signal-desktop-keyring.gpg
                ;;
            arch)
                aur_remove signal-desktop 2>/dev/null || \
                    sudo pacman -Rs --noconfirm signal-desktop 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/Signal"
}

update_signal() {
    info "Updating Signal Desktop..."
    if flatpak_is_installed "org.signal.Signal"; then
        flatpak update -y org.signal.Signal
    else
        case "$DISTRO_FAMILY" in
            debian)   sudo apt-get install -y --only-upgrade signal-desktop ;;
            arch)
                repo_or_aur signal-desktop
                ;;
        esac
    fi
}

get_version_signal() {
    # Do NOT call signal-desktop --version — Electron apps launch a full GUI window.
    _ver_from_pkg signal-desktop || _ver_from_flatpak org.signal.Signal || echo ""
}
