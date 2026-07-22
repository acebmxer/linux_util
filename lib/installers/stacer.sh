#!/bin/bash
# Stacer installer functions

# --- Stacer ---

check_stacer() { _check_standard stacer stacer com.oguzhaninan.Stacer; }

_stacer_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/oguzhaninan/Stacer/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext" | grep -v "arm" | head -1
}

# Download the latest upstream .rpm and install it with the native package
# manager. Kept only as a fallback: Stacer's last release (1.1.0, 2019) was
# built without a payload digest, so rpm >= 6 (Fedora 41+) rejects the
# transaction with "does not verify: no digest". Flatpak is preferred.
_stacer_install_rpm() {
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
    verify_download "$tmpfile" "rpm" "Stacer" || return 1
    github_verify_checksum "https://api.github.com/repos/oguzhaninan/Stacer/releases/latest" \
        "$(basename "$url")" "$tmpfile" || return 1
    sudo "$PKG_MGR" install -y "$tmpfile" || {
        error "Failed to install Stacer .rpm. Upstream builds predate rpm payload digests and are rejected by rpm >= 6."
        return 1
    }
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
            verify_download "$tmpfile" "deb" "Stacer" || return 1
            github_verify_checksum "https://api.github.com/repos/oguzhaninan/Stacer/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile" || { error "Failed to install Stacer .deb."; return 1; }
            ;;
        fedora|rhel|suse)
            if ensure_flatpak; then
                flatpak install -y flathub com.oguzhaninan.Stacer || {
                    error "Failed to install Stacer from Flathub."
                    return 1
                }
            else
                _stacer_install_rpm || return 1
            fi
            ;;
        arch)
            aur_ensure stacer-bin || return 1
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
            debian|fedora|rhel|suse) install_stacer ;;
            arch)
                aur_ensure stacer-bin
                ;;
        esac
    fi
}

get_version_stacer() {
    # Do NOT call stacer --version — Electron apps launch a full GUI window.
    _ver_from_pkg stacer || _ver_from_flatpak com.oguzhaninan.Stacer || echo ""
}
