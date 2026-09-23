#!/bin/bash
# Superfile terminal file manager installer functions

# --- Superfile ---

_SUPERFILE_API="https://api.github.com/repos/yorukot/superfile/releases/latest"

check_superfile() { _check_standard spf superfile ""; }

install_superfile() {
    info "Installing Superfile..."
    case "$DISTRO_FAMILY" in
        arch) pkg_install superfile ;;
        *)    ensure_tools; _install_superfile_binary ;;
    esac
    info "Superfile installed."
}

# Download the upstream Linux binary tarball and install spf to /usr/local/bin.
# Used for every distro family except Arch, where superfile is a native
# `extra` repo package (pacman) — no Debian/Fedora/openSUSE repo carries it.
_install_superfile_binary() {
    local version arch asset tmpdir tarball checksums expected_hash spf_bin

    version=$(curl -fsSL "$_SUPERFILE_API" | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest superfile version."; return 1; }

    arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"

    asset="superfile-linux-${version}-${arch}.tar.gz"
    tmpdir=$(mktemp -d /tmp/superfile-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tarball="$tmpdir/$asset"

    if ! curl -fsSL -o "$tarball" \
        "https://github.com/yorukot/superfile/releases/download/${version}/${asset}"; then
        error "Failed to download superfile."
        return 1
    fi
    verify_download "$tarball" "tar.gz" "$asset" || return 1

    # Upstream's checksums asset is named superfile-<version>-checksums.txt,
    # which doesn't match github_verify_checksum's fixed filename patterns —
    # looked up directly here rather than widening that shared helper for one repo.
    checksums=$(curl -fsSL \
        "https://github.com/yorukot/superfile/releases/download/${version}/superfile-${version}-checksums.txt" \
        2>/dev/null)
    if [[ -n "$checksums" ]]; then
        expected_hash=$(echo "$checksums" | grep -F "$asset" | awk '{print $1}' | head -1)
        [[ -n "$expected_hash" ]] && { verify_sha256 "$tarball" "$expected_hash" "$asset" || return 1; }
    else
        warn "Could not fetch superfile checksums — skipping verification."
    fi

    if ! tar -xzf "$tarball" -C "$tmpdir"; then
        error "Failed to extract superfile archive."
        return 1
    fi

    spf_bin=$(find "$tmpdir" -type f -name spf | head -1)
    [[ -z "$spf_bin" ]] && { error "spf binary not found in downloaded archive."; return 1; }

    sudo install -m 755 "$spf_bin" /usr/local/bin/spf
}

uninstall_superfile() {
    info "Uninstalling Superfile..."
    sudo rm -f /usr/local/bin/spf
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        pkg_check_installed superfile && sudo pacman -Rs --noconfirm superfile
    fi
    rm -rf "$HOME/.config/superfile" "$HOME/.local/share/superfile" "$HOME/.local/state/superfile"
}

update_superfile() {
    info "Updating Superfile..."
    case "$DISTRO_FAMILY" in
        arch) pkg_upgrade superfile ;;
        *)    _install_superfile_binary ;;
    esac
}

get_version_superfile() {
    _ver_from_pkg superfile || _ver_from_cmd spf || echo ""
}
