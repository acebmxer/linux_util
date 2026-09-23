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
            pkg_install lutris
            ;;
        fedora)
            # Lutris is available via RPM Fusion free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
                sudo "$PKG_MGR" makecache
            fi
            pkg_install lutris
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install lutris
            ;;
        arch)
            pkg_install lutris
            ;;
        suse)
            # Try OBS Games repo first, fall back to Flatpak
            if sudo zypper addrepo -f \
                "https://download.opensuse.org/repositories/games/openSUSE_Tumbleweed/games.repo" \
                games 2>/dev/null; then
                sudo zypper refresh
                pkg_install lutris
            elif has_flatpak; then
                sudo flatpak install -y flathub net.lutris.Lutris
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
        flatpak uninstall -y --user net.lutris.Lutris 2>/dev/null || \
            sudo flatpak uninstall -y --system net.lutris.Lutris
    else
        case "$DISTRO_FAMILY" in
            debian)
                pkg_remove lutris
                # Remove PPA if added
                sudo add-apt-repository -y --remove ppa:lutris-team/lutris 2>/dev/null || true
                ;;
            fedora|rhel)
                pkg_remove lutris
                ;;
            arch)
                pkg_remove lutris
                ;;
            suse)
                pkg_remove lutris 2>/dev/null || true
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
        flatpak update -y --user net.lutris.Lutris 2>/dev/null || \
            sudo flatpak update -y --system net.lutris.Lutris
    else
        case "$DISTRO_FAMILY" in
            debian)   sudo apt-get install -y --only-upgrade lutris ;;
            fedora|rhel) pkg_upgrade lutris ;;
            arch)     pkg_upgrade lutris ;;
            suse)     pkg_upgrade lutris ;;
        esac
    fi
}

get_version_lutris() {
    _ver_from_cmd lutris || echo ""
}
