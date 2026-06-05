#!/bin/bash
# Btop++ installer functions

# --- Btop ---

check_btop() { _check_standard btop btop ""; }

install_btop() {
    info "Installing Btop++..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y btop
            ;;
        fedora)
            sudo "$PKG_MGR" install -y btop
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y btop 2>/dev/null || {
                warn "btop not in EPEL. Installing from GitHub release..."
                _btop_install_binary
            }
            ;;
        arch)
            sudo pacman -S --noconfirm btop
            ;;
        suse)
            sudo zypper install -y btop 2>/dev/null || {
                warn "btop not in repos. Installing from GitHub release..."
                _btop_install_binary
            }
            ;;
    esac
    info "Btop++ installed."
}

# Install pre-built static binary from GitHub releases as a fallback
_btop_install_binary() {
    ensure_tools
    local arch
    arch=$(uname -m)
    local url
    url=$(curl -fsSL "https://api.github.com/repos/aristocratos/btop/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+btop-'"$arch"'-linux-musl\.tbz(?=")' | head -1)
    [[ -z "$url" ]] && { error "Could not find btop binary for ${arch}."; return 1; }

    local tmpfile
    tmpfile=$(mktemp /tmp/btop-XXXXXX.tbz)
    CLEANUP_FILES+=("$tmpfile")
    wget -qO "$tmpfile" "$url" || { error "Failed to download btop."; return 1; }
    verify_download "$tmpfile" "tbz" "Btop" || return 1
    github_verify_checksum "https://api.github.com/repos/aristocratos/btop/releases/latest" \
        "$(basename "$url")" "$tmpfile" || return 1

    local tmpdir
    tmpdir=$(mktemp -d)
    tar -xjf "$tmpfile" -C "$tmpdir"
    (cd "$tmpdir" && sudo make install PREFIX=/usr/local) || {
        # Fallback: manual copy
        sudo cp "$tmpdir/btop/bin/btop" /usr/local/bin/btop
        sudo chmod +x /usr/local/bin/btop
    }
    rm -rf "$tmpdir"
}

uninstall_btop() {
    info "Uninstalling Btop++..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y btop ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y btop 2>/dev/null || sudo rm -f /usr/local/bin/btop ;;
        arch)    sudo pacman -Rs --noconfirm btop ;;
        suse)    sudo zypper remove -y btop 2>/dev/null || sudo rm -f /usr/local/bin/btop ;;
    esac
    sudo rm -f /usr/local/bin/btop 2>/dev/null || true
    rm -rf "$HOME/.config/btop"
}

update_btop() {
    info "Updating Btop++..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y --only-upgrade btop ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y btop 2>/dev/null || _btop_install_binary ;;
        arch)    sudo pacman -S --noconfirm btop ;;
        suse)    sudo zypper update -y btop 2>/dev/null || _btop_install_binary ;;
    esac
}

get_version_btop() {
    _ver_from_cmd btop || echo ""
}
