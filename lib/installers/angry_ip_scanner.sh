#!/bin/bash
# Angry IP Scanner installer functions

# --- Angry IP Scanner ---

check_angry_ip_scanner() { _check_standard ipscan ipscan ""; }

_angry_ip_latest_url() {
    local pattern="$1"
    curl -fsSL "https://api.github.com/repos/angryip/ipscan/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+'"$pattern" | head -1
}

install_angry_ip_scanner() {
    info "Installing Angry IP Scanner..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url tmpfile
            url=$(_angry_ip_latest_url '_amd64\.deb')
            if [[ -z "$url" ]]; then
                error "Could not find Angry IP Scanner .deb release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/ipscan-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Angry IP Scanner .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Angry IP Scanner" || return 1
            github_verify_checksum "https://api.github.com/repos/angryip/ipscan/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local url tmpfile
            url=$(_angry_ip_latest_url '\.x86_64\.rpm')
            if [[ -z "$url" ]]; then
                error "Could not find Angry IP Scanner .rpm release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/ipscan-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Angry IP Scanner .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Angry IP Scanner" || return 1
            github_verify_checksum "https://api.github.com/repos/angryip/ipscan/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            aur_ensure ipscan
            ;;
        suse)
            local url tmpfile
            url=$(_angry_ip_latest_url '\.x86_64\.rpm')
            if [[ -z "$url" ]]; then
                error "Could not find Angry IP Scanner .rpm release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/ipscan-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Angry IP Scanner .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Angry IP Scanner" || return 1
            github_verify_checksum "https://api.github.com/repos/angryip/ipscan/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo zypper install -y "$tmpfile"
            ;;
    esac
    info "Angry IP Scanner installed."
}

uninstall_angry_ip_scanner() {
    info "Uninstalling Angry IP Scanner..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y ipscan ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y ipscan ;;
        arch)    aur_remove angryipscanner 2>/dev/null || sudo pacman -Rs --noconfirm ipscan 2>/dev/null || true ;;
        suse)    sudo zypper remove -y ipscan 2>/dev/null || true ;;
    esac
    rm -rf "$HOME/.ipscan"
}

update_angry_ip_scanner() {
    info "Updating Angry IP Scanner..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel|suse) install_angry_ip_scanner ;;
        arch) aur_ensure ipscan ;;
    esac
}

get_version_angry_ip_scanner() {
    _ver_from_pkg ipscan || echo ""
}
