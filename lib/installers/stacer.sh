#!/bin/bash
# Stacer installer functions

# --- Stacer ---

check_stacer() { _check_standard stacer stacer ""; }

_stacer_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/oguzhaninan/Stacer/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext" | grep -v "arm" | head -1
}

install_stacer() {
    info "Installing Stacer..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_stacer_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find Stacer .deb release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/stacer-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer .deb."; return 1; }
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local url
            url=$(_stacer_latest_url "rpm")
            if [[ -z "$url" ]]; then
                error "Could not find Stacer .rpm release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/stacer-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer .rpm."; return 1; }
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            aur_ensure stacer-bin
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.oguzhaninan.Stacer
            else
                # Try .rpm from GitHub
                local url
                url=$(_stacer_latest_url "rpm")
                if [[ -n "$url" ]]; then
                    local tmpfile
                    tmpfile=$(mktemp /tmp/stacer-XXXXXX.rpm)
                    CLEANUP_FILES+=("$tmpfile")
                    wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer .rpm."; return 1; }
                    sudo zypper install -y "$tmpfile"
                else
                    error "Could not install Stacer on this openSUSE system."
                    return 1
                fi
            fi
            ;;
    esac
    info "Stacer installed."
}

uninstall_stacer() {
    info "Uninstalling Stacer..."
    if flatpak_is_installed "com.oguzhaninan.Stacer"; then
        flatpak uninstall -y com.oguzhaninan.Stacer
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y stacer ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y stacer ;;
            arch)    aur_remove stacer-bin 2>/dev/null || sudo pacman -Rs --noconfirm stacer 2>/dev/null || true ;;
            suse)    sudo zypper remove -y stacer 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.config/stacer"
}

update_stacer() {
    info "Updating Stacer..."
    if flatpak_is_installed "com.oguzhaninan.Stacer"; then
        flatpak update -y com.oguzhaninan.Stacer
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_stacer ;;
            arch)
                aur_ensure stacer-bin
                ;;
        esac
    fi
}

get_version_stacer() {
    # Do NOT call stacer --version — Electron apps launch a full GUI window.
    _ver_from_pkg stacer || echo ""
}
