#!/bin/bash
# Flatpak setup installer functions

# --- Flatpak Setup ---

check_flatpak_setup() {
    _have_cmd flatpak && \
        flatpak remotes 2>/dev/null | grep -q "flathub"
}

install_flatpak_setup() {
    info "Setting up Flatpak with Flathub..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y flatpak
            # Install GNOME or KDE Plasma integration plugin depending on DE
            if command -v plasmashell &>/dev/null; then
                sudo apt install -y plasma-discover-backend-flatpak 2>/dev/null || true
            else
                sudo apt install -y gnome-software-plugin-flatpak 2>/dev/null || true
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y flatpak
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y flatpak
            ;;
        arch)
            sudo pacman -S --noconfirm flatpak
            ;;
        suse)
            sudo zypper install -y flatpak
            ;;
    esac

    # Add Flathub remote (system-wide)
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    info "Flatpak installed and Flathub remote configured."
    info "A logout/reboot is recommended so Flatpak app paths are picked up by the shell."
}

uninstall_flatpak_setup() {
    info "Removing Flathub remote and Flatpak..."
    # Remove Flathub remote
    sudo flatpak remote-delete --force flathub 2>/dev/null || true

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y flatpak plasma-discover-backend-flatpak gnome-software-plugin-flatpak 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y flatpak
            ;;
        arch)
            sudo pacman -Rs --noconfirm flatpak
            ;;
        suse)
            sudo zypper remove -y flatpak
            ;;
    esac
    warn "Installed Flatpak apps were not removed. Remove them with 'flatpak uninstall --all' first if needed."
}

update_flatpak_setup() {
    info "Updating all installed Flatpak applications..."
    flatpak update -y
}

get_version_flatpak_setup() {
    _ver_from_cmd flatpak || echo ""
}
