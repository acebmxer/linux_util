#!/bin/bash
# Stacer installer functions

# --- Stacer ---

check_stacer() {
    command -v stacer &>/dev/null || pkg_check_installed stacer
}

_stacer_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/oguzhaninan/Stacer/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext"'"' | grep -v "arm" | head -1
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
            if has_aur_helper; then
                aur_install stacer-bin
            else
                aur_build stacer-bin
            fi
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.oguzhaninan.Stacer"; then
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.oguzhaninan.Stacer"; then
        flatpak update -y com.oguzhaninan.Stacer
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel) install_stacer ;;
            arch)
                if has_aur_helper; then
                    aur_upgrade stacer-bin
                else
                    aur_build stacer-bin
                fi
                ;;
        esac
    fi
}

get_version_stacer() {
    stacer --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    pkg_get_version stacer 2>/dev/null | sed 's/-.*//' || \
    echo ""
}
