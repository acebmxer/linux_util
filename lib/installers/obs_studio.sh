#!/bin/bash
# OBS Studio installer functions

# --- OBS Studio ---

check_obs_studio() {
    command -v obs &>/dev/null || \
        pkg_check_installed obs-studio || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "com.obsproject.Studio")
}

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
            sudo apt install -y obs-studio
            ;;
        fedora)
            # OBS is in RPM Fusion free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
                sudo "$PKG_MGR" makecache
            fi
            sudo "$PKG_MGR" install -y obs-studio
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y obs-studio 2>/dev/null || {
                warn "obs-studio not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.obsproject.Studio
                    return $?
                fi
                error "OBS Studio requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm obs-studio
            ;;
        suse)
            sudo zypper install -y obs-studio 2>/dev/null || {
                if has_flatpak; then
                    flatpak install -y flathub com.obsproject.Studio
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.obsproject.Studio"; then
        flatpak uninstall -y com.obsproject.Studio
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y obs-studio
                sudo add-apt-repository -y --remove ppa:obsproject/obs-studio 2>/dev/null || true
                ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y obs-studio ;;
            arch)        sudo pacman -Rs --noconfirm obs-studio ;;
            suse)        sudo zypper remove -y obs-studio ;;
        esac
    fi
    rm -rf "$HOME/.config/obs-studio"
}

update_obs_studio() {
    info "Updating OBS Studio..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.obsproject.Studio"; then
        flatpak update -y com.obsproject.Studio
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt update && sudo apt upgrade -y obs-studio ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y obs-studio ;;
            arch)    sudo pacman -S --noconfirm obs-studio ;;
            suse)    sudo zypper update -y obs-studio ;;
        esac
    fi
}

get_version_obs_studio() {
    obs --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "com.obsproject.Studio" | awk -F'\t' '{print $3}') || \
    pkg_get_version obs-studio 2>/dev/null | sed 's/-.*//' || \
    echo ""
}
