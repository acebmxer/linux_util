#!/bin/bash
# RustDesk remote desktop installer functions

# --- RustDesk ---

check_rustdesk() { _check_standard rustdesk rustdesk com.rustdesk.RustDesk; }

install_rustdesk() {
    info "Installing RustDesk..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local version tmpfile arch
            arch="amd64"
            [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
            version=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
                | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
            [[ -z "$version" ]] && { error "Could not determine latest RustDesk version."; return 1; }
            tmpfile=$(mktemp /tmp/rustdesk-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" \
                "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version#v}-x86_64.deb" 2>/dev/null && \
               ! wget -qO "$tmpfile" \
                "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version}-${arch}.deb" 2>/dev/null; then
                warn "Direct .deb download failed. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.rustdesk.RustDesk
                    return $?
                fi
                error "RustDesk installation failed."
                return 1
            fi
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local version tmpfile
            version=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
                | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
            [[ -z "$version" ]] && { error "Could not determine latest RustDesk version."; return 1; }
            tmpfile=$(mktemp /tmp/rustdesk-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" \
                "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version#v}-x86_64.rpm" 2>/dev/null; then
                warn "Direct .rpm download failed. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.rustdesk.RustDesk
                    return $?
                fi
                error "RustDesk installation failed."
                return 1
            fi
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            flatpak_or_aur com.rustdesk.RustDesk rustdesk-bin
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.rustdesk.RustDesk
            else
                error "RustDesk requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "RustDesk installed."
}

uninstall_rustdesk() {
    info "Uninstalling RustDesk..."
    if flatpak_is_installed "com.rustdesk.RustDesk"; then
        flatpak uninstall -y com.rustdesk.RustDesk
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y rustdesk ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y rustdesk ;;
            arch)
                aur_remove rustdesk-bin 2>/dev/null || \
                    sudo pacman -Rs --noconfirm rustdesk 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/rustdesk"
}

update_rustdesk() {
    info "Updating RustDesk..."
    if flatpak_is_installed "com.rustdesk.RustDesk"; then
        flatpak update -y com.rustdesk.RustDesk
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_rustdesk ;;
            arch)               aur_ensure rustdesk-bin ;;
            suse)               install_rustdesk ;;
        esac
    fi
}

get_version_rustdesk() {
    _ver_from_pkg rustdesk || _ver_from_flatpak com.rustdesk.RustDesk || echo ""
}
