#!/bin/bash
# HandBrake video transcoder installer functions

# --- HandBrake ---

check_handbrake() { _check_standard ghb handbrake fr.handbrake.ghb; }

install_handbrake() {
    info "Installing HandBrake..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install handbrake 2>/dev/null || pkg_install handbrake-gtk 2>/dev/null || {
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
            pkg_install HandBrake-gui HandBrake-cli
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
            pkg_install handbrake
            ;;
        suse)
            pkg_install handbrake 2>/dev/null || {
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
        flatpak uninstall -y --user fr.handbrake.ghb 2>/dev/null || \
            sudo flatpak uninstall -y --system fr.handbrake.ghb
    else
        case "$DISTRO_FAMILY" in
            debian)
                pkg_remove handbrake handbrake-gtk handbrake-cli 2>/dev/null || true
                ;;
            fedora|rhel)
                pkg_remove HandBrake-gui HandBrake-cli 2>/dev/null || pkg_remove handbrake 2>/dev/null || true
                ;;
            arch)
                pkg_remove handbrake
                ;;
            suse)
                pkg_remove handbrake
                ;;
        esac
    fi
    rm -rf "$HOME/.config/ghb"
}

update_handbrake() {
    info "Updating HandBrake..."
    if flatpak_is_installed "fr.handbrake.ghb"; then
        flatpak update -y --user fr.handbrake.ghb 2>/dev/null || \
            sudo flatpak update -y --system fr.handbrake.ghb
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt-get install -y --only-upgrade handbrake handbrake-gtk 2>/dev/null || true
                ;;
            fedora|rhel)
                pkg_upgrade HandBrake-gui HandBrake-cli 2>/dev/null || true
                ;;
            arch)
                pkg_upgrade handbrake
                ;;
            suse)
                pkg_upgrade handbrake
                ;;
        esac
    fi
}

get_version_handbrake() {
    _ver_from_flatpak fr.handbrake.ghb || _ver_from_pkg handbrake || echo ""
}
