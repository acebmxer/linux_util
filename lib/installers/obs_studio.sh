#!/bin/bash
# OBS Studio installer functions

# --- OBS Studio ---

check_obs_studio() { _check_standard obs obs-studio com.obsproject.Studio; }

install_obs_studio() {
    info "Installing OBS Studio..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" || "$DISTRO_ID" == "neon" ]]; then
                # Official OBS PPA for latest version on Ubuntu
                sudo add-apt-repository -y ppa:obsproject/obs-studio
                sudo apt update
            fi
            pkg_install obs-studio
            ;;
        fedora)
            # OBS is in RPM Fusion free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
                sudo "$PKG_MGR" makecache
            fi
            pkg_install obs-studio
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install obs-studio 2>/dev/null || {
                warn "obs-studio not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub com.obsproject.Studio
                    return $?
                fi
                error "OBS Studio requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            pkg_install obs-studio
            ;;
        suse)
            pkg_install obs-studio 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub com.obsproject.Studio
                else
                    error "OBS Studio requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "OBS Studio installed."
}

uninstall_obs_studio() {
    info "Uninstalling OBS Studio..."
    if flatpak_is_installed "com.obsproject.Studio"; then
        flatpak uninstall -y --user com.obsproject.Studio 2>/dev/null || \
            sudo flatpak uninstall -y --system com.obsproject.Studio
    else
        case "$DISTRO_FAMILY" in
            debian)
                pkg_remove obs-studio
                sudo add-apt-repository -y --remove ppa:obsproject/obs-studio 2>/dev/null || true
                ;;
            fedora|rhel) pkg_remove obs-studio ;;
            arch)        pkg_remove obs-studio ;;
            suse)        pkg_remove obs-studio ;;
        esac
    fi
    rm -rf "$HOME/.config/obs-studio"
}

update_obs_studio() {
    info "Updating OBS Studio..."
    if flatpak_is_installed "com.obsproject.Studio"; then
        flatpak update -y --user com.obsproject.Studio 2>/dev/null || \
            sudo flatpak update -y --system com.obsproject.Studio
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y --only-upgrade obs-studio ;;
            fedora|rhel) pkg_upgrade obs-studio ;;
            arch)    pkg_upgrade obs-studio ;;
            suse)    pkg_upgrade obs-studio ;;
        esac
    fi
}

get_version_obs_studio() {
    _ver_from_cmd obs || _ver_from_flatpak com.obsproject.Studio || _ver_from_pkg obs-studio || echo ""
}
