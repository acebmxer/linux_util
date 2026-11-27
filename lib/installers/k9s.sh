#!/bin/bash
# k9s Kubernetes terminal UI installer functions

# --- k9s ---

check_k9s() { _check_standard k9s k9s ""; }

install_k9s() {
    info "Installing k9s..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            pkg_install k9s
            ;;
        *)
            _install_k9s_binary
            ;;
    esac
    info "k9s installed."
}

_install_k9s_binary() {
    # Installed as root into /usr/local/bin, so the archive must match the
    # SHA-256 GitHub publishes for it (github_asset_download refuses otherwise).
    local arch tmpdir tarball
    arch=$(upstream_arch go) || return 1
    tmpdir=$(mktemp -d /tmp/k9s-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tarball=$(github_asset_download derailed/k9s "k9s_Linux_${arch}\.tar\.gz" "$tmpdir") || return 1
    sudo tar -xzf "$tarball" -C /usr/local/bin k9s || { error "Failed to unpack k9s."; return 1; }
    sudo chmod +x /usr/local/bin/k9s
}

uninstall_k9s() {
    info "Uninstalling k9s..."
    if [[ -f /usr/local/bin/k9s ]]; then
        sudo rm -f /usr/local/bin/k9s
    fi
    case "$DISTRO_FAMILY" in
        arch) pkg_remove k9s 2>/dev/null || true ;;
    esac
    rm -rf "$HOME/.config/k9s"
}

update_k9s() {
    info "Updating k9s..."
    if [[ "$DISTRO_FAMILY" == "arch" ]] && ! [[ -f /usr/local/bin/k9s ]]; then
        pkg_upgrade k9s
    else
        _install_k9s_binary
    fi
}

get_version_k9s() {
    _ver_from_cmd k9s version --short 2>/dev/null | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_pkg k9s || echo ""
}
