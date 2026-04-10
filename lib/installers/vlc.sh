#!/bin/bash
# VLC media player installer functions

# --- VLC ---

check_vlc() { _check_standard vlc vlc org.videolan.VLC; }

install_vlc() {
    info "Installing VLC..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y vlc
            ;;
        fedora)
            # VLC requires RPM Fusion Free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
            fi
            sudo "$PKG_MGR" install -y vlc
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" 2>/dev/null || true
            fi
            sudo "$PKG_MGR" install -y vlc 2>/dev/null || {
                warn "VLC not found in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub org.videolan.VLC
                    return $?
                fi
                error "VLC requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm vlc
            ;;
        suse)
            sudo zypper install -y vlc 2>/dev/null || {
                if has_flatpak; then
                    flatpak install -y flathub org.videolan.VLC
                else
                    error "VLC requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "VLC installed."
}

uninstall_vlc() {
    info "Uninstalling VLC..."
    if flatpak_is_installed "org.videolan.VLC"; then
        flatpak uninstall -y org.videolan.VLC
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y vlc ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y vlc ;;
            arch)        sudo pacman -Rs --noconfirm vlc ;;
            suse)        sudo zypper remove -y vlc ;;
        esac
    fi
    rm -rf "$HOME/.config/vlc"
}

update_vlc() {
    info "Updating VLC..."
    if flatpak_is_installed "org.videolan.VLC"; then
        flatpak update -y org.videolan.VLC
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade vlc ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y vlc ;;
            arch)        sudo pacman -S --noconfirm vlc ;;
            suse)        sudo zypper update -y vlc ;;
        esac
    fi
}

get_version_vlc() {
    _ver_from_cmd vlc || _ver_from_flatpak org.videolan.VLC || _ver_from_pkg vlc || echo ""
}
