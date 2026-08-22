#!/bin/bash
# Zoom video conferencing installer functions

# --- Zoom ---

check_zoom() { _check_standard zoom zoom us.zoom.Zoom; }

install_zoom() {
    info "Installing Zoom..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmpfile
            tmpfile=$(mktemp /tmp/zoom-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://zoom.us/client/latest/zoom_amd64.deb"; then
                error "Failed to download Zoom .deb package."
                return 1
            fi
            verify_download "$tmpfile" "deb" "Zoom" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local tmpfile
            tmpfile=$(mktemp /tmp/zoom-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://zoom.us/client/latest/zoom_x86_64.rpm"; then
                error "Failed to download Zoom .rpm package."
                return 1
            fi
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            flatpak_or_aur us.zoom.Zoom zoom
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub us.zoom.Zoom
            else
                local tmpfile
                tmpfile=$(mktemp /tmp/zoom-XXXXXX.rpm)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "https://zoom.us/client/latest/zoom_x86_64.rpm" || {
                    error "Failed to download Zoom .rpm package."
                    return 1
                }
                sudo zypper install -y --allow-unsigned-rpm "$tmpfile"
            fi
            ;;
    esac
    info "Zoom installed."
}

uninstall_zoom() {
    info "Uninstalling Zoom..."
    if flatpak_is_installed "us.zoom.Zoom"; then
        flatpak uninstall -y us.zoom.Zoom
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y zoom ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y zoom ;;
            arch)
                aur_remove zoom 2>/dev/null || \
                    sudo pacman -Rs --noconfirm zoom 2>/dev/null || true
                ;;
            suse)        sudo zypper remove -y zoom 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.zoom" "$HOME/.config/zoomus.conf"
}

update_zoom() {
    info "Updating Zoom..."
    if flatpak_is_installed "us.zoom.Zoom"; then
        flatpak update -y us.zoom.Zoom
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_zoom ;;
            arch)               repo_or_aur zoom ;;
            suse)               sudo zypper update -y zoom 2>/dev/null || install_zoom ;;
        esac
    fi
}

get_version_zoom() {
    _ver_from_pkg zoom || _ver_from_flatpak us.zoom.Zoom || echo ""
}
