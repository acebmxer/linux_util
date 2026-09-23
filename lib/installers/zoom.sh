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
            pkg_install "$tmpfile"
            ;;
        fedora|rhel)
            local tmpfile
            tmpfile=$(mktemp /tmp/zoom-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://zoom.us/client/latest/zoom_x86_64.rpm"; then
                error "Failed to download Zoom .rpm package."
                return 1
            fi
            pkg_install "$tmpfile"
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
                pkg_install --allow-unsigned-rpm "$tmpfile"
            fi
            ;;
    esac
    info "Zoom installed."
}

uninstall_zoom() {
    info "Uninstalling Zoom..."
    if flatpak_is_installed "us.zoom.Zoom"; then
        flatpak uninstall -y --user us.zoom.Zoom 2>/dev/null || \
            sudo flatpak uninstall -y --system us.zoom.Zoom
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove zoom ;;
            fedora|rhel) pkg_remove zoom ;;
            arch)
                aur_remove zoom 2>/dev/null || \
                    pkg_remove zoom 2>/dev/null || true
                ;;
            suse)        pkg_remove zoom 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.zoom" "$HOME/.config/zoomus.conf"
}

update_zoom() {
    info "Updating Zoom..."
    if flatpak_is_installed "us.zoom.Zoom"; then
        flatpak update -y --user us.zoom.Zoom 2>/dev/null || \
            sudo flatpak update -y --system us.zoom.Zoom
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_zoom ;;
            arch)               repo_or_aur zoom ;;
            suse)               pkg_upgrade zoom 2>/dev/null || install_zoom ;;
        esac
    fi
}

get_version_zoom() {
    _ver_from_pkg zoom || _ver_from_flatpak us.zoom.Zoom || echo ""
}
