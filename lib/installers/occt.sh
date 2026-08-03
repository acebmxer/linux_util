#!/bin/bash
# OCCT installer functions
# https://www.ocbase.com
#
# OCCT (OverClock Checking Tool) is a stability/stress-testing and hardware
# monitoring suite (CPU, RAM, GPU, PSU tests). The Personal edition is free for
# personal use.
#
# Upstream ships Linux as a single self-contained x86_64 ELF binary served from
# a stable, unversioned URL — there is no apt/dnf repo, no AUR package, no
# Flatpak, no GitHub release, and no published checksum. It is not "installed"
# in any real sense: you drop the binary somewhere and run it.
#
# CRITICAL — the binary must live in a USER-WRITABLE directory. OCCT keeps its
# state (notably the license file you import through the GUI) *next to its own
# executable*. Installed to a root-owned path like /usr/local/bin, OCCT runs but
# silently dies the moment it tries to persist the license — no error, no crash
# trace, because it simply cannot write there. So it goes in ~/.local/share/occt
# with a wrapper on PATH, and nothing here needs root.
#
# Do NOT wrap the launcher in pkexec/sudo either: OCCT's Avalonia GUI needs the
# user's display session, and pkexec scrubs the environment (under Wayland the
# app authenticates and then dies with no display). OCCT elevates itself if a
# test needs raw hardware access.
#
#   - install: drop the binary in ~/.local/share/occt + wrapper + .desktop entry
#   - update:  no repo to upgrade from, so just re-download the latest binary
#   - checksum: none published upstream, so none can be verified (see below)

# --- OCCT ---

OCCT_URL="https://www.ocbase.com/download/edition:Personal/os:Linux"
_OCCT_DIR="$HOME/.local/share/occt"
_OCCT_BIN="$_OCCT_DIR/occt"
_OCCT_WRAPPER="$HOME/.local/bin/occt"
_OCCT_DESKTOP="$HOME/.local/share/applications/occt.desktop"

check_occt() {
    [[ -x "$_OCCT_BIN" ]] && return 0
    _have_cmd occt && return 0
    return 1
}

install_occt() {
    info "Installing OCCT..."
    ensure_tools

    # Upstream only builds an x86_64 Linux binary.
    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "x86_64" ]]; then
        error "OCCT only provides a Linux binary for x86_64 (this system is '${arch}')."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/occt-XXXXXX)
    CLEANUP_FILES+=("$tmpfile")

    # ~200 MB single binary, so download_file's 30s timeout is far too short —
    # call curl directly with a generous one. -sS keeps the progress meter out
    # of the menu UI while still printing real errors.
    info "Downloading OCCT (this is a large download, please be patient)..."
    if ! curl -fsSL --max-time 900 --retry 2 -o "$tmpfile" "$OCCT_URL"; then
        error "Failed to download OCCT."
        return 1
    fi

    # Plain ELF executable rather than a package archive. The "AppImage"
    # verifier checks for ELF magic bytes (soft-warns rather than failing).
    verify_download "$tmpfile" "AppImage" "OCCT" || return 1

    # No checksum verification is possible: ocbase.com publishes no checksum or
    # signature alongside the Linux binary, and the download URL is unversioned.

    # Preserve an existing license/settings across a reinstall or update — they
    # live beside the binary, so only replace the executable itself.
    mkdir -p "$_OCCT_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
    install -m755 "$tmpfile" "$_OCCT_BIN" || {
        error "Failed to install OCCT to ${_OCCT_BIN}."
        return 1
    }

    # Wrapper on PATH. It cd's into the install dir first: OCCT resolves its
    # license and settings relative to the working directory, so launching it
    # from elsewhere would leave it unable to find an already-imported license.
    cat > "$_OCCT_WRAPPER" <<EOF
#!/bin/bash
cd "$_OCCT_DIR" || exit 1
exec "$_OCCT_BIN" "\$@"
EOF
    chmod +x "$_OCCT_WRAPPER"

    # Launch via the wrapper (not the raw binary) so the menu entry gets the
    # same working directory, and as the desktop user — never pkexec.
    cat > "$_OCCT_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=OCCT
Comment=CPU, RAM, and GPU stability testing and hardware monitoring
Exec=$_OCCT_WRAPPER
Path=$_OCCT_DIR
Terminal=false
Categories=System;Monitor;
EOF
    refresh_desktop_caches

    info "OCCT installed to ${_OCCT_DIR}. Launch it from your application menu or run 'occt'."
    info "Import your license through the GUI — it is saved alongside the binary."
}

uninstall_occt() {
    info "Uninstalling OCCT..."
    # Removes the binary and, with it, the imported license and settings.
    rm -rf "$_OCCT_DIR"
    rm -f "$_OCCT_WRAPPER" "$_OCCT_DESKTOP"
    # Cache of native libs the .NET single-file bundle unpacks on first run.
    # ~/.net is shared with any other single-file .NET app, so only remove
    # OCCT's own subdirectory, then the parent if that leaves it empty.
    rm -rf "$HOME/.net/OCCTGUI"
    rmdir "$HOME/.net" 2>/dev/null || true
    # Test results and reports OCCT writes under ~/Documents are the user's own
    # data — intentionally left untouched.
    refresh_desktop_caches
    info "OCCT uninstalled."
}

update_occt() {
    info "Updating OCCT..."
    # No upstream repo to upgrade from — re-download the latest binary. The
    # license and settings beside it are preserved (see install_occt).
    install_occt
}

get_version_occt() {
    _ver_from_cmd occt --version || echo ""
}
