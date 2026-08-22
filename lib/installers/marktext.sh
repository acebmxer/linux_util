#!/bin/bash
# Mark Text Markdown editor installer functions
#
# Arch does NOT use the AUR here. The `marktext` AUR package pins
# _electron=electron15 and rewrites package.json to run the app on that system
# runtime instead of the Electron upstream bundles. Electron 15 shipped in
# September 2021 and went EOL in May 2022; Arch's repos carry electron39-43, so
# the dependency can only come from AUR electron15 (last touched 2022-08-31) or
# electron15-bin -- roughly four years of unpatched Chromium. The package is a
# from-source yarn/electron-rebuild build on top of that, is stuck at 0.17.1,
# and has been flagged out-of-date since 2026-07-10 while upstream is at 0.19.1.
#
# Flathub stays the first choice on every family. Where Flatpak is unavailable,
# upstream's own .tar.gz is unpacked per-user: it is a self-contained Electron
# bundle carrying the Electron that Mark Text actually ships, it needs no root,
# and unpacking sidesteps the AppImage runtime's libfuse.so.2 dependency the
# same way lib/installers/stacer.sh does.

# --- Mark Text ---

_MT_DIR="$HOME/.local/share/marktext"
_MT_APP="$_MT_DIR/marktext"
_MT_WRAPPER="$HOME/.local/bin/marktext"
_MT_DESKTOP="$HOME/.local/share/applications/marktext.desktop"

# Print the download URL for an upstream release asset matching $1 (an ERE).
# Asset names carry the version (marktext-linux-0.19.1.deb), so they cannot be
# hardcoded -- the old code asked for a fixed "marktext-amd64.deb" that upstream
# has never published, so every Debian install 404'd into the Flatpak fallback.
_mt_asset_url() {
    curl -fsSL "https://api.github.com/repos/marktext/marktext/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -m1 -E "$1"
}

# Unpack upstream's .tar.gz into ~/.local/share and wire up a launcher.
_mt_install_tarball() {
    local url tmpdir tarball
    url=$(_mt_asset_url 'marktext-linux-[0-9][^/]*\.tar\.gz$')
    if [[ -z "$url" ]]; then
        error "Could not find a Mark Text .tar.gz release asset."
        return 1
    fi

    tmpdir=$(mktemp -d /tmp/marktext-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tarball="$tmpdir/marktext.tar.gz"

    info "Downloading Mark Text..."
    wget -qO "$tarball" "$url" || { error "Failed to download Mark Text."; return 1; }

    mkdir -p "$tmpdir/payload"
    if ! tar xzf "$tarball" -C "$tmpdir/payload"; then
        error "Failed to unpack the Mark Text tarball."
        return 1
    fi

    # The tarball has a single versioned top-level directory; find the binary
    # rather than assuming its name, so a rename upstream fails loudly here
    # instead of leaving a launcher pointing at nothing.
    local found
    found=$(find "$tmpdir/payload" -mindepth 2 -maxdepth 2 -type f -name marktext -perm -u+x | head -1)
    if [[ -z "$found" ]]; then
        error "Unpacked Mark Text payload has no marktext executable."
        return 1
    fi

    rm -rf "$_MT_DIR"
    mkdir -p "$(dirname "$_MT_DIR")"
    mv "$(dirname "$found")" "$_MT_DIR" || {
        error "Failed to install Mark Text to ${_MT_DIR}."
        return 1
    }

    mkdir -p "$(dirname "$_MT_WRAPPER")"
    ln -sf "$_MT_APP" "$_MT_WRAPPER"

    mkdir -p "$(dirname "$_MT_DESKTOP")"
    cat > "$_MT_DESKTOP" <<EOF
[Desktop Entry]
Name=Mark Text
Comment=Simple and elegant markdown editor
Exec=$_MT_APP %U
Icon=$_MT_DIR/resources/app/assets/images/logo-small.png
Terminal=false
Type=Application
Categories=Office;TextEditor;Utility;
MimeType=text/markdown;text/x-markdown;
EOF
    refresh_desktop_caches
    info "Mark Text installed to ${_MT_DIR}."
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        warn "$HOME/.local/bin is not on your PATH; launch Mark Text from your application menu."
    fi
    return 0
}

check_marktext() {
    [[ -x "$_MT_APP" ]] && return 0
    _check_standard marktext marktext com.github.marktext.marktext
}

install_marktext() {
    info "Installing Mark Text..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url tmpfile
            url=$(_mt_asset_url 'marktext-linux-[0-9][^/]*\.deb$')
            [[ -z "$url" ]] && { error "Could not find a Mark Text .deb release asset."; return 1; }
            tmpfile=$(mktemp /tmp/marktext-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "$url"; then
                warn "Direct .deb download failed. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub com.github.marktext.marktext
                    return $?
                fi
                error "Mark Text installation failed."
                return 1
            fi
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            if has_flatpak; then
                sudo flatpak install -y flathub com.github.marktext.marktext
            else
                error "Mark Text requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            # Tier order: repos, then Flathub, then upstream's own binary.
            # The AUR is not a tier here -- see this file's header.
            arch_install_ordered "marktext" "com.github.marktext.marktext" "_mt_install_tarball" "" || return 1
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub com.github.marktext.marktext
            else
                error "Mark Text requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Mark Text installed."
}

uninstall_marktext() {
    info "Uninstalling Mark Text..."
    if flatpak_is_installed "com.github.marktext.marktext"; then
        flatpak uninstall -y com.github.marktext.marktext
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt purge --autoremove -y marktext ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y marktext 2>/dev/null || true ;;
            arch)
                # marktext is the old AUR package, removed only if an install
                # predating the tarball path is still registered with pacman.
                pkg_check_installed marktext && \
                    sudo pacman -Rs --noconfirm marktext 2>/dev/null
                true
                ;;
        esac
    fi
    rm -rf "$_MT_DIR"
    rm -f "$_MT_WRAPPER" "$_MT_DESKTOP"
    refresh_desktop_caches
    rm -rf "$HOME/.config/marktext"
}

update_marktext() {
    info "Updating Mark Text..."
    if flatpak_is_installed "com.github.marktext.marktext"; then
        flatpak update -y com.github.marktext.marktext
    else
        case "$DISTRO_FAMILY" in
            debian)      install_marktext ;;
            fedora|rhel) install_marktext ;;
            arch)        install_marktext ;;
            suse)        install_marktext ;;
        esac
    fi
}

get_version_marktext() {
    _ver_from_pkg marktext \
        || _ver_from_flatpak com.github.marktext.marktext \
        || ([[ -x "$_MT_APP" ]] && _ver_from_cmd "$_MT_APP") \
        || echo ""
}
