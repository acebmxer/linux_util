#!/bin/bash
# Obsidian installer functions

# --- Obsidian ---

check_obsidian() { _check_standard obsidian obsidian md.obsidian.Obsidian; }

_obsidian_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext"'(?=")' | head -1
}

install_obsidian() {
    info "Installing Obsidian..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_obsidian_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find Obsidian .deb release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/obsidian-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Obsidian .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Obsidian" || return 1
            github_verify_checksum "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local url
            url=$(_obsidian_latest_url "rpm")
            if [[ -z "$url" ]]; then
                warn "Could not find Obsidian .rpm. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub md.obsidian.Obsidian
                    return $?
                fi
                error "Obsidian requires Flatpak on this system."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/obsidian-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Obsidian .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Obsidian" || return 1
            github_verify_checksum "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            repo_or_aur obsidian
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub md.obsidian.Obsidian
            else
                error "Obsidian requires Flatpak on openSUSE."
                return 1
            fi
            ;;
    esac
    info "Obsidian installed."
}

uninstall_obsidian() {
    info "Uninstalling Obsidian..."
    if flatpak_is_installed "md.obsidian.Obsidian"; then
        flatpak uninstall -y --user md.obsidian.Obsidian 2>/dev/null || \
            sudo flatpak uninstall -y --system md.obsidian.Obsidian
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y obsidian ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y obsidian ;;
            arch)    aur_remove obsidian 2>/dev/null || sudo pacman -Rs --noconfirm obsidian 2>/dev/null || true ;;
            suse)    flatpak uninstall -y --user md.obsidian.Obsidian 2>/dev/null || \
                         sudo flatpak uninstall -y --system md.obsidian.Obsidian 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.config/obsidian"
}

update_obsidian() {
    info "Updating Obsidian..."
    if flatpak_is_installed "md.obsidian.Obsidian"; then
        flatpak update -y --user md.obsidian.Obsidian 2>/dev/null || \
            sudo flatpak update -y --system md.obsidian.Obsidian
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_obsidian ;;
            arch)
                repo_or_aur obsidian
                ;;
        esac
    fi
}

get_version_obsidian() {
    # Do NOT call obsidian --version — Electron apps launch a full GUI window.
    _ver_from_pkg obsidian || _ver_from_flatpak md.obsidian.Obsidian || echo ""
}
