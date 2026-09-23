#!/bin/bash
# MangoHud installer functions

# --- MangoHud ---

check_mangohud() { _check_standard mangohud mangohud ""; }

install_mangohud() {
    info "Installing MangoHud..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" || "$DISTRO_ID" == "neon" ]]; then
                # MangoHud is in universe; also install 32-bit for Steam games
                pkg_install mangohud
                # 32-bit variant for Steam (best-effort)
                sudo dpkg --add-architecture i386 2>/dev/null || true
                sudo apt update
                pkg_install mangohud:i386 2>/dev/null || warn "32-bit MangoHud not available; 64-bit only."
            else
                # Debian: build from source via the upstream install script
                pkg_install meson ninja-build glslang-tools libx11-dev libdbus-1-dev libwayland-dev libxrandr-dev python3-mako python3-pip git 2>/dev/null || true

                local tmpdir
                tmpdir=$(mktemp -d)
                git clone --depth=1 https://github.com/flightlessmango/MangoHud.git "$tmpdir" || {
                    error "Failed to clone MangoHud repository."
                    rm -rf "$tmpdir"
                    return 1
                }
                (cd "$tmpdir" && ./build.sh build install) || {
                    error "MangoHud build/install failed."
                    rm -rf "$tmpdir"
                    return 1
                }
                rm -rf "$tmpdir"
            fi
            ;;
        fedora)
            # MangoHud is in RPM Fusion free
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
            fi
            pkg_install mangohud
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install mangohud 2>/dev/null || {
                warn "MangoHud not found in EPEL. Attempting Flatpak fallback..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.freedesktop.Platform.VulkanLayer.MangoHud
                else
                    error "MangoHud unavailable on this RHEL-based system."
                    return 1
                fi
            }
            ;;
        arch)
            pkg_install mangohud lib32-mangohud 2>/dev/null || pkg_install mangohud
            ;;
        suse)
            pkg_install mangohud 2>/dev/null || {
                warn "MangoHud not in default repos. Attempting Flatpak fallback..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.freedesktop.Platform.VulkanLayer.MangoHud
                else
                    error "MangoHud unavailable on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "MangoHud installed. Prefix game launch command with 'mangohud' to enable."
}

uninstall_mangohud() {
    info "Uninstalling MangoHud..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove mangohud mangohud:i386 2>/dev/null || true
            ;;
        fedora|rhel)
            pkg_remove mangohud 2>/dev/null || true
            ;;
        arch)
            pkg_remove mangohud lib32-mangohud 2>/dev/null || pkg_remove mangohud 2>/dev/null || true
            ;;
        suse)
            pkg_remove mangohud 2>/dev/null || true
            ;;
    esac
    # Remove Flatpak layer if installed
    has_flatpak && flatpak uninstall -y --user org.freedesktop.Platform.VulkanLayer.MangoHud 2>/dev/null || \
        sudo flatpak uninstall -y --system org.freedesktop.Platform.VulkanLayer.MangoHud 2>/dev/null || true
    rm -rf "$HOME/.config/MangoHud"
}

update_mangohud() {
    info "Updating MangoHud..."
    case "$DISTRO_FAMILY" in
        debian)   sudo apt-get install -y --only-upgrade mangohud 2>/dev/null || install_mangohud ;;
        fedora|rhel) pkg_upgrade mangohud ;;
        arch)     pkg_upgrade mangohud lib32-mangohud 2>/dev/null || sudo pacman -S --noconfirm mangohud ;;
        suse)     pkg_upgrade mangohud ;;
    esac
}

get_version_mangohud() {
    _ver_from_cmd mangohud || echo ""
}
