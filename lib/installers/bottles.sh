#!/bin/bash
# Bottles installer functions

# --- Bottles ---

check_bottles() { _check_standard bottles "" com.usebottles.bottles; }

install_bottles() {
    info "Installing Bottles..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            repo_or_aur bottles
            ;;
        *)
            # Flatpak is the officially supported distribution method
            if has_flatpak; then
                sudo flatpak install -y flathub com.usebottles.bottles
            else
                error "Bottles requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Bottles installed."
}

uninstall_bottles() {
    info "Uninstalling Bottles..."
    if flatpak_is_installed "com.usebottles.bottles"; then
        flatpak uninstall -y com.usebottles.bottles
    else
        case "$DISTRO_FAMILY" in
            arch)
                aur_remove bottles 2>/dev/null || \
                    sudo pacman -Rs --noconfirm bottles 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.local/share/bottles"
}

update_bottles() {
    info "Updating Bottles..."
    if flatpak_is_installed "com.usebottles.bottles"; then
        flatpak update -y com.usebottles.bottles
    else
        case "$DISTRO_FAMILY" in
            arch)
                repo_or_aur bottles
                ;;
        esac
    fi
}

get_version_bottles() {
    _ver_from_flatpak com.usebottles.bottles || _ver_from_cmd bottles || echo ""
}
