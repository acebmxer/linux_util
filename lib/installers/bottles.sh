#!/bin/bash
# Bottles installer functions

# --- Bottles ---

check_bottles() {
    command -v bottles &>/dev/null || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "com.usebottles.bottles")
}

install_bottles() {
    info "Installing Bottles..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            if has_aur_helper; then
                aur_install bottles
            else
                sudo pacman -S --noconfirm bottles 2>/dev/null || aur_build bottles
            fi
            ;;
        *)
            # Flatpak is the officially supported distribution method
            if has_flatpak; then
                flatpak install -y flathub com.usebottles.bottles
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.usebottles.bottles"; then
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.usebottles.bottles"; then
        flatpak update -y com.usebottles.bottles
    else
        case "$DISTRO_FAMILY" in
            arch)
                if has_aur_helper; then
                    aur_upgrade bottles
                else
                    aur_build bottles
                fi
                ;;
        esac
    fi
}

get_version_bottles() {
    (has_flatpak && flatpak list 2>/dev/null | grep -i "com.usebottles.bottles" | awk -F'\t' '{print $3}') || \
    bottles --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    echo ""
}
