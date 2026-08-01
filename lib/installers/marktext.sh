#!/bin/bash
# Mark Text Markdown editor installer functions

# --- Mark Text ---

check_marktext() { _check_standard marktext marktext com.github.marktext.marktext; }

install_marktext() {
    info "Installing Mark Text..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local version tmpfile
            version=$(curl -fsSL https://api.github.com/repos/marktext/marktext/releases/latest \
                | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
            [[ -z "$version" ]] && { error "Could not determine latest Mark Text version."; return 1; }
            tmpfile=$(mktemp /tmp/marktext-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" \
                "https://github.com/marktext/marktext/releases/download/${version}/marktext-amd64.deb"; then
                warn "Direct .deb download failed. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.github.marktext.marktext
                    return $?
                fi
                error "Mark Text installation failed."
                return 1
            fi
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            if has_flatpak; then
                flatpak install -y flathub com.github.marktext.marktext
            else
                error "Mark Text requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            flatpak_or_aur com.github.marktext.marktext marktext
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.github.marktext.marktext
            else
                error "Mark Text requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Mark Text installed."
}

uninstall_marktext() {
    info "Uninstalling Mark Text..."
    if flatpak_is_installed "com.github.marktext.marktext"; then
        flatpak uninstall -y com.github.marktext.marktext
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y marktext ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y marktext 2>/dev/null || true ;;
            arch)
                aur_remove marktext 2>/dev/null || \
                    sudo pacman -Rs --noconfirm marktext 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/marktext"
}

update_marktext() {
    info "Updating Mark Text..."
    if flatpak_is_installed "com.github.marktext.marktext"; then
        flatpak update -y com.github.marktext.marktext
    else
        case "$DISTRO_FAMILY" in
            debian)      install_marktext ;;
            fedora|rhel) install_marktext ;;
            arch)        aur_ensure marktext ;;
            suse)        install_marktext ;;
        esac
    fi
}

get_version_marktext() {
    _ver_from_pkg marktext || _ver_from_flatpak com.github.marktext.marktext || echo ""
}
