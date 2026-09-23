#!/bin/bash
# VLC media player installer functions

# --- VLC ---

check_vlc() { _check_standard vlc vlc org.videolan.VLC; }

install_vlc() {
    info "Installing VLC..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install vlc
            ;;
        fedora)
            # VLC requires RPM Fusion Free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
            fi
            pkg_install vlc
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" 2>/dev/null || true
            fi
            pkg_install vlc 2>/dev/null || {
                warn "VLC not found in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.videolan.VLC
                    return $?
                fi
                error "VLC requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            pkg_install vlc
            ;;
        suse)
            pkg_install vlc 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub org.videolan.VLC
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
        flatpak uninstall -y --user org.videolan.VLC 2>/dev/null || \
            sudo flatpak uninstall -y --system org.videolan.VLC
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove vlc ;;
            fedora|rhel) pkg_remove vlc ;;
            arch)        pkg_remove vlc ;;
            suse)        pkg_remove vlc ;;
        esac
    fi
    rm -rf "$HOME/.config/vlc"
}

update_vlc() {
    info "Updating VLC..."
    if flatpak_is_installed "org.videolan.VLC"; then
        flatpak update -y --user org.videolan.VLC 2>/dev/null || \
            sudo flatpak update -y --system org.videolan.VLC
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade vlc ;;
            fedora|rhel) pkg_upgrade vlc ;;
            arch)        pkg_upgrade vlc ;;
            suse)        pkg_upgrade vlc ;;
        esac
    fi
}

get_version_vlc() {
    _ver_from_cmd vlc || _ver_from_flatpak org.videolan.VLC || _ver_from_pkg vlc || echo ""
}
