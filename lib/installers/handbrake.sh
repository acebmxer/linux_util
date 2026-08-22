#!/bin/bash
# HandBrake video transcoder installer functions

# --- HandBrake ---

check_handbrake() { _check_standard ghb handbrake fr.handbrake.ghb; }

install_handbrake() {
    info "Installing HandBrake..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y handbrake 2>/dev/null || \
                sudo apt install -y handbrake-gtk 2>/dev/null || {
                    warn "handbrake not in repos. Falling back to Flatpak..."
                    if has_flatpak; then
                        sudo flatpak install -y flathub fr.handbrake.ghb
                        return $?
                    fi
                    error "HandBrake requires Flatpak on this system."
                    return 1
                }
            ;;
        fedora)
            # HandBrake requires RPM Fusion Free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
            fi
            sudo "$PKG_MGR" install -y HandBrake-gui HandBrake-cli
            ;;
        rhel)
            if has_flatpak; then
                sudo flatpak install -y flathub fr.handbrake.ghb
            else
                error "HandBrake requires Flatpak on this RHEL-based system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm handbrake
            ;;
        suse)
            sudo zypper install -y handbrake 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub fr.handbrake.ghb
                else
                    error "HandBrake requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "HandBrake installed."
}

uninstall_handbrake() {
    info "Uninstalling HandBrake..."
    if flatpak_is_installed "fr.handbrake.ghb"; then
        flatpak uninstall -y fr.handbrake.ghb
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y handbrake handbrake-gtk handbrake-cli 2>/dev/null || true
                ;;
            fedora|rhel)
                sudo "$PKG_MGR" remove -y HandBrake-gui HandBrake-cli 2>/dev/null || \
                    sudo "$PKG_MGR" remove -y handbrake 2>/dev/null || true
                ;;
            arch)
                sudo pacman -Rs --noconfirm handbrake
                ;;
            suse)
                sudo zypper remove -y handbrake
                ;;
        esac
    fi
    rm -rf "$HOME/.config/ghb"
}

update_handbrake() {
    info "Updating HandBrake..."
    if flatpak_is_installed "fr.handbrake.ghb"; then
        flatpak update -y fr.handbrake.ghb
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt-get install -y --only-upgrade handbrake handbrake-gtk 2>/dev/null || true
                ;;
            fedora|rhel)
                sudo "$PKG_MGR" upgrade -y HandBrake-gui HandBrake-cli 2>/dev/null || true
                ;;
            arch)
                sudo pacman -S --noconfirm handbrake
                ;;
            suse)
                sudo zypper update -y handbrake
                ;;
        esac
    fi
}

get_version_handbrake() {
    _ver_from_flatpak fr.handbrake.ghb || _ver_from_pkg handbrake || echo ""
}
