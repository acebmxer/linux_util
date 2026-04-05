#!/bin/bash
# Obsidian installer functions

# --- Obsidian ---

check_obsidian() {
    command -v obsidian &>/dev/null || \
        pkg_check_installed obsidian || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "md.obsidian.Obsidian")
}

_obsidian_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext"'"' | head -1
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
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local url
            url=$(_obsidian_latest_url "rpm")
            if [[ -z "$url" ]]; then
                warn "Could not find Obsidian .rpm. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub md.obsidian.Obsidian
                    return $?
                fi
                error "Obsidian requires Flatpak on this system."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/obsidian-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Obsidian .rpm."; return 1; }
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            if has_aur_helper; then
                aur_install obsidian
            else
                aur_build obsidian
            fi
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub md.obsidian.Obsidian
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "md.obsidian.Obsidian"; then
        flatpak uninstall -y md.obsidian.Obsidian
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y obsidian ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y obsidian ;;
            arch)    aur_remove obsidian 2>/dev/null || sudo pacman -Rs --noconfirm obsidian 2>/dev/null || true ;;
            suse)    flatpak uninstall -y md.obsidian.Obsidian 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.config/obsidian"
}

update_obsidian() {
    info "Updating Obsidian..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "md.obsidian.Obsidian"; then
        flatpak update -y md.obsidian.Obsidian
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_obsidian ;;
            arch)
                if has_aur_helper; then
                    aur_upgrade obsidian
                else
                    aur_build obsidian
                fi
                ;;
        esac
    fi
}

get_version_obsidian() {
    obsidian --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "md.obsidian.Obsidian" | awk -F'\t' '{print $3}') || \
    pkg_get_version obsidian 2>/dev/null | sed 's/-.*//' || \
    echo ""
}
