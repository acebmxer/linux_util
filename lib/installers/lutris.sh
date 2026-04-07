#!/bin/bash
# Lutris installer functions

# --- Lutris ---

check_lutris() { _check_standard lutris lutris ""; }

install_lutris() {
    info "Installing Lutris..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" || "$DISTRO_ID" == "neon" ]]; then
                sudo add-apt-repository -y ppa:lutris-team/lutris
                sudo apt update
            fi
            sudo apt install -y lutris
            ;;
        fedora)
            # Lutris is available via RPM Fusion free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
                sudo "$PKG_MGR" makecache
            fi
            sudo "$PKG_MGR" install -y lutris
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y lutris
            ;;
        arch)
            sudo pacman -S --noconfirm lutris
            ;;
        suse)
            # Try OBS Games repo first, fall back to Flatpak
            if sudo zypper addrepo -f \
                "https://download.opensuse.org/repositories/games/openSUSE_Tumbleweed/games.repo" \
                games 2>/dev/null; then
                sudo zypper refresh
                sudo zypper install -y lutris
            elif has_flatpak; then
                flatpak install -y flathub net.lutris.Lutris
            else
                error "Could not install Lutris on this openSUSE system."
                return 1
            fi
            ;;
    esac
    info "Lutris installed."
}

uninstall_lutris() {
    info "Uninstalling Lutris..."
    if flatpak_is_installed "net.lutris.Lutris"; then
        flatpak uninstall -y net.lutris.Lutris
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y lutris
                # Remove PPA if added
                sudo add-apt-repository -y --remove ppa:lutris-team/lutris 2>/dev/null || true
                ;;
            fedora|rhel)
                sudo "$PKG_MGR" remove -y lutris
                ;;
            arch)
                sudo pacman -Rs --noconfirm lutris
                ;;
            suse)
                sudo zypper remove -y lutris 2>/dev/null || true
                sudo zypper removerepo games 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/lutris"
    rm -rf "$HOME/.local/share/lutris"
}

update_lutris() {
    info "Updating Lutris..."
    if flatpak_is_installed "net.lutris.Lutris"; then
        flatpak update -y net.lutris.Lutris
    else
        case "$DISTRO_FAMILY" in
            debian)   sudo apt-get install -y --only-upgrade lutris ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y lutris ;;
            arch)     sudo pacman -S --noconfirm lutris ;;
            suse)     sudo zypper update -y lutris ;;
        esac
    fi
}

get_version_lutris() {
    _ver_from_cmd lutris || echo ""
}
