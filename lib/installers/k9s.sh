#!/bin/bash
# k9s Kubernetes terminal UI installer functions

# --- k9s ---

check_k9s() { _check_standard k9s k9s ""; }

install_k9s() {
    info "Installing k9s..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -S --noconfirm k9s
            ;;
        *)
            _install_k9s_binary
            ;;
    esac
    info "k9s installed."
}

_install_k9s_binary() {
    local version arch tmpfile
    version=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest k9s version."; return 1; }
    arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
    tmpfile=$(mktemp /tmp/k9s-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")
    if ! wget -qO "$tmpfile" \
        "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_${arch}.tar.gz"; then
        error "Failed to download k9s."
        return 1
    fi
    sudo tar -xzf "$tmpfile" -C /usr/local/bin k9s
    sudo chmod +x /usr/local/bin/k9s
}

uninstall_k9s() {
    info "Uninstalling k9s..."
    if [[ -f /usr/local/bin/k9s ]]; then
        sudo rm -f /usr/local/bin/k9s
    fi
    case "$DISTRO_FAMILY" in
        arch) sudo pacman -Rs --noconfirm k9s 2>/dev/null || true ;;
    esac
    rm -rf "$HOME/.config/k9s"
}

update_k9s() {
    info "Updating k9s..."
    if [[ "$DISTRO_FAMILY" == "arch" ]] && ! [[ -f /usr/local/bin/k9s ]]; then
        sudo pacman -S --noconfirm k9s
    else
        _install_k9s_binary
    fi
}

get_version_k9s() {
    _ver_from_cmd k9s version --short 2>/dev/null | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_pkg k9s || echo ""
}
