#!/bin/bash
# Libation installer functions

# --- Libation ---

check_libation() { _check_standard libation libation ""; }

_libation_latest_url() {
    local ext="$1"  # deb or rpm
    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) error "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac
    curl -fsSL "https://api.github.com/repos/rmcrackan/Libation/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+linux-chardonnay-'"$arch"'\.'"$ext"'(?=")' | head -1
}

install_libation() {
    info "Installing Libation..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_libation_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find Libation .deb release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/libation-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Libation .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Libation" || return 1
            github_verify_checksum "https://api.github.com/repos/rmcrackan/Libation/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel|suse)
            local url
            url=$(_libation_latest_url "rpm")
            if [[ -z "$url" ]]; then
                error "Could not find Libation .rpm release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/libation-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Libation .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Libation" || return 1
            github_verify_checksum "https://api.github.com/repos/rmcrackan/Libation/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            if [[ "$DISTRO_FAMILY" == "suse" ]]; then
                sudo zypper install -y --allow-unsigned-rpm "$tmpfile"
            else
                sudo "$PKG_MGR" install -y "$tmpfile"
            fi
            ;;
        arch)
            repo_or_aur libation
            ;;
    esac
    info "Libation installed."
}

uninstall_libation() {
    info "Uninstalling Libation..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y libation
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y libation
            ;;
        suse)
            sudo zypper remove -y libation
            ;;
        arch)
            aur_remove libation 2>/dev/null || \
                sudo pacman -Rs --noconfirm libation 2>/dev/null || true
            ;;
    esac
    # ~/Libation and the Books folder hold the user's library database and
    # downloaded audiobooks — intentionally left untouched.
    rm -rf "$HOME/.config/Libation"
}

update_libation() {
    info "Updating Libation..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel|suse) install_libation ;;
        arch)
            repo_or_aur libation
            ;;
    esac
}

get_version_libation() {
    # Do NOT call libation --version — it launches the full GUI window.
    _ver_from_pkg libation || echo ""
}
