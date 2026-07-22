#!/bin/bash
# Stacer installer functions
# https://github.com/oguzhaninan/Stacer
#
# Upstream is frozen at v1.1.0 (2019), which constrains every install path:
#
#   - debian: the upstream .deb still installs cleanly.
#   - arch:   stacer-bin in the AUR.
#   - fedora/rhel/suse: nothing installable from a package manager.
#       * Stacer is NOT on Flathub. com.oguzhaninan.Stacer has never been
#         published there — flathub's appstream API 404s on that ID and
#         `flatpak search stacer` returns nothing. Do not "restore" a Flathub
#         branch here; it fails on every retry.
#       * It is not in the Fedora, EPEL, or openSUSE repos either.
#       * The upstream .rpm predates rpm payload digests, so rpm >= 6
#         (Fedora 41+) rejects the transaction with "does not verify: no
#         digest". rpm 6 also dropped --nodigest, leaving no bypass short of
#         lowering %_pkgverify_level system-wide — not worth doing to a user's
#         machine for one app.
#     So rpm families get the upstream AppImage, installed per-user.
#
# The AppImage is EXTRACTED at install time rather than run in place: its 2019
# runtime needs libfuse.so.2, which current Fedora/RHEL/SUSE no longer install
# by default. Extracting sidesteps FUSE entirely and keeps this path root-free
# — no sudo anywhere in it. It costs disk: the 31 MB AppImage unpacks to ~76 MB
# of bundled Qt5 under ~/.local/share/stacer.
#
# Only libqxcb.so is bundled (there is no Qt Wayland plugin in a 2019 Qt5
# build), so the wrapper pins QT_QPA_PLATFORM=xcb. Under a session that exports
# QT_QPA_PLATFORM=wayland, Qt would otherwise abort with "could not find or
# load the Qt platform plugin".

# --- Stacer ---

_STACER_REPO_API="https://api.github.com/repos/oguzhaninan/Stacer/releases/latest"
_STACER_DIR="$HOME/.local/share/stacer"
_STACER_APP="$_STACER_DIR/squashfs-root"
_STACER_VERSION_FILE="$_STACER_DIR/version"
_STACER_WRAPPER="$HOME/.local/bin/stacer"
_STACER_DESKTOP="$HOME/.local/share/applications/stacer.desktop"

check_stacer() {
    [[ -x "$_STACER_APP/AppRun" ]] && return 0
    _check_standard stacer stacer ""
}

_stacer_latest_url() {
    local ext="$1"
    curl -fsSL "$_STACER_REPO_API" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.'"$ext" | grep -v "arm" | head -1
}

# Download the upstream AppImage, unpack it into ~/.local/share/stacer, and put
# a wrapper plus a menu entry in place. Needs no root and no FUSE.
_stacer_install_appimage() {
    local url
    url=$(_stacer_latest_url "AppImage")
    if [[ -z "$url" ]]; then
        error "Could not find Stacer AppImage release URL."
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/stacer-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")
    local tmpfile="$tmpdir/stacer.AppImage"

    wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer AppImage."; return 1; }
    verify_download "$tmpfile" "AppImage" "Stacer" || return 1
    github_verify_checksum "$_STACER_REPO_API" "$(basename "$url")" "$tmpfile" || return 1
    chmod +x "$tmpfile"

    # --appimage-extract always writes ./squashfs-root relative to the working
    # directory, so run it inside the temp dir rather than next to the install.
    if ! (cd "$tmpdir" && "$tmpfile" --appimage-extract >/dev/null 2>&1); then
        error "Failed to extract the Stacer AppImage."
        return 1
    fi
    if [[ ! -x "$tmpdir/squashfs-root/AppRun" ]]; then
        error "Extracted Stacer AppImage is missing its AppRun entry point."
        return 1
    fi

    # Swap the payload in only once extraction has succeeded, so a failed
    # update cannot leave a half-removed install behind.
    mkdir -p "$_STACER_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
    rm -rf "$_STACER_APP"
    mv "$tmpdir/squashfs-root" "$_STACER_APP" || {
        error "Failed to install Stacer to ${_STACER_APP}."
        return 1
    }

    # Stacer's binary never reports a usable version (it opens a GUI window
    # instead), so record the version from the asset name for get_version.
    basename "$url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > "$_STACER_VERSION_FILE"

    cat > "$_STACER_WRAPPER" <<EOF
#!/bin/bash
# Only the xcb platform plugin is bundled in this AppImage — see stacer.sh.
export QT_QPA_PLATFORM=xcb
exec "$_STACER_APP/AppRun" "\$@"
EOF
    chmod +x "$_STACER_WRAPPER"

    # Icon by absolute path: the extracted tree ships one PNG and nothing
    # installs it into a hicolor theme directory.
    cat > "$_STACER_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Stacer
Comment=Linux System Optimizer and Monitoring
Exec=$_STACER_WRAPPER
Icon=$_STACER_APP/stacer.png
Terminal=false
Categories=System;Monitor;Utility;
EOF
    refresh_desktop_caches

    info "Stacer installed to ${_STACER_DIR}. Launch it from your application menu or run 'stacer'."
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
            github_verify_checksum "$_STACER_REPO_API" "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile" || { error "Failed to install Stacer .deb."; return 1; }
            ;;
        fedora|rhel|suse)
            _stacer_install_appimage || return 1
            ;;
        arch)
            aur_ensure stacer-bin || return 1
            ;;
    esac
    info "Stacer installed."
}

uninstall_stacer() {
    info "Uninstalling Stacer..."
    if [[ -d "$_STACER_DIR" ]]; then
        rm -rf "$_STACER_DIR"
        rm -f "$_STACER_WRAPPER" "$_STACER_DESKTOP"
        refresh_desktop_caches
    else
        case "$DISTRO_FAMILY" in
            debian)     sudo apt purge --autoremove -y stacer ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y stacer ;;
            arch)       aur_remove stacer-bin 2>/dev/null || sudo pacman -Rs --noconfirm stacer 2>/dev/null || true ;;
            suse)       sudo zypper remove -y stacer 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.config/stacer"
}

update_stacer() {
    info "Updating Stacer..."
    if [[ -d "$_STACER_APP" ]]; then
        # Upstream has not shipped a release since 2019, so check the tag before
        # pulling 30 MB down again on every update run.
        local latest current
        latest=$(_stacer_latest_url "AppImage" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        current=$(cat "$_STACER_VERSION_FILE" 2>/dev/null)
        if [[ -n "$latest" && "$latest" == "$current" ]]; then
            info "Stacer is already at the latest release (${current})."
            return 0
        fi
        _stacer_install_appimage
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
    # Do NOT call stacer --version — it launches a full GUI window instead of
    # printing anything.
    _ver_from_pkg stacer || cat "$_STACER_VERSION_FILE" 2>/dev/null || echo ""
}
