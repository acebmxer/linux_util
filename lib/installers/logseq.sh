#!/bin/bash
# Logseq graph-based note-taking app installer functions

# --- Logseq ---

check_logseq() {
    _have_cmd logseq || \
        flatpak_is_installed "com.logseq.Logseq" || \
        [[ -f /opt/logseq/logseq ]]
}

install_logseq() {
    info "Installing Logseq..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            flatpak_or_aur com.logseq.Logseq logseq-desktop-bin
            ;;
        *)
            # Flatpak is the recommended distribution method for most distros
            if has_flatpak; then
                flatpak install -y flathub com.logseq.Logseq
            else
                _install_logseq_appimage
            fi
            ;;
    esac
    info "Logseq installed."
}

_install_logseq_appimage() {
    info "Installing Logseq AppImage..."
    local version tmpfile
    version=$(curl -fsSL https://api.github.com/repos/logseq/logseq/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest Logseq version."; return 1; }
    tmpfile=$(mktemp /tmp/logseq-XXXXXX.AppImage)
    CLEANUP_FILES+=("$tmpfile")
    if ! wget -qO "$tmpfile" \
        "https://github.com/logseq/logseq/releases/download/${version}/Logseq-linux-x64-${version}.AppImage"; then
        error "Failed to download Logseq AppImage."
        return 1
    fi
    sudo mkdir -p /opt/logseq
    sudo install -m 755 "$tmpfile" /opt/logseq/logseq
    # Create a desktop entry
    sudo tee /usr/share/applications/logseq.desktop > /dev/null <<'DESKTOP'
[Desktop Entry]
Name=Logseq
Comment=A privacy-first, open-source platform for knowledge management and collaboration
Exec=/opt/logseq/logseq %U
Icon=logseq
Type=Application
Categories=Office;Education;
DESKTOP
    sudo ln -sf /opt/logseq/logseq /usr/local/bin/logseq
}

uninstall_logseq() {
    info "Uninstalling Logseq..."
    if flatpak_is_installed "com.logseq.Logseq"; then
        flatpak uninstall -y com.logseq.Logseq
    elif [[ -f /opt/logseq/logseq ]]; then
        sudo rm -rf /opt/logseq
        sudo rm -f /usr/local/bin/logseq
        sudo rm -f /usr/share/applications/logseq.desktop
    else
        case "$DISTRO_FAMILY" in
            arch)
                aur_remove logseq-desktop-bin 2>/dev/null || \
                    sudo pacman -Rs --noconfirm logseq-desktop-bin 2>/dev/null || true
                ;;
        esac
    fi
    # Note: user graph data lives in ~/logseq — we do not delete it
}

update_logseq() {
    info "Updating Logseq..."
    if flatpak_is_installed "com.logseq.Logseq"; then
        flatpak update -y com.logseq.Logseq
    elif [[ -f /opt/logseq/logseq ]]; then
        _install_logseq_appimage
    else
        case "$DISTRO_FAMILY" in
            arch) aur_ensure logseq-desktop-bin ;;
            *)    install_logseq ;;
        esac
    fi
}

get_version_logseq() {
    _ver_from_flatpak com.logseq.Logseq || echo ""
}
