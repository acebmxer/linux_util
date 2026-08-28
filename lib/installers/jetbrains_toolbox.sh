#!/bin/bash
# JetBrains Toolbox installer functions

# --- JetBrains Toolbox ---

_JB_TOOLBOX_DIR="$HOME/.local/share/JetBrains/Toolbox"
_JB_TOOLBOX_BIN="$_JB_TOOLBOX_DIR/bin/jetbrains-toolbox"
_JB_TOOLBOX_JVM="$_JB_TOOLBOX_DIR/bin/jre/lib/server/libjvm.so"
_JB_TOOLBOX_DESKTOP="$HOME/.local/share/applications/jetbrains-toolbox.desktop"
_JB_TOOLBOX_ICON="$HOME/.local/share/icons/hicolor/scalable/apps/jetbrains-toolbox.svg"

# The launcher is a thin native stub that dlopen()s the bundled JRE at
# bin/jre/lib/server/libjvm.so relative to its own directory. A tree with the
# stub but no JRE is a broken install that exits instantly with "Failed to
# start JVM", so both have to be present before this counts as installed.
check_jetbrains_toolbox() {
    [[ -f "$_JB_TOOLBOX_BIN" && -f "$_JB_TOOLBOX_JVM" ]] && return 0

    # A copy installed by other means (distro package, manual install) still
    # counts, but our own symlink does not -- it points back at the tree just
    # rejected above.
    local onpath
    onpath=$(command -v jetbrains-toolbox 2>/dev/null) || return 1
    [[ -n "$onpath" ]] || return 1
    [[ "$(readlink -f "$onpath")" != "$(readlink -f "$_JB_TOOLBOX_BIN")" ]]
}

install_jetbrains_toolbox() {
    info "Installing JetBrains Toolbox..."
    ensure_tools

    # Fetch latest download URL from JetBrains data API.
    # The response is captured before it is filtered rather than piped straight
    # into grep: `head -1` closes the pipe as soon as it has its line, and curl
    # reports that as "(23) Failure writing output to destination" on stderr.
    local api_url="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    local download_url body links
    body=$(curl -fsSL "$api_url")
    links=$(printf '%s\n' "$body" | grep -oP '"linux"\s*:\s*\{[^}]*"link"\s*:\s*"\K[^"]+')
    download_url="${links%%$'\n'*}"

    if [[ -z "$download_url" ]]; then
        # Fallback: scrape the toolbox download page
        body=$(curl -fsSL "https://www.jetbrains.com/toolbox-app/download/download-thanks.html?platform=linux")
        links=$(printf '%s\n' "$body" | grep -oP 'https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[^"]+\.tar\.gz')
        download_url="${links%%$'\n'*}"
    fi

    if [[ -z "$download_url" ]]; then
        error "Failed to retrieve JetBrains Toolbox download URL."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/jetbrains-toolbox-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")

    # ~150 MB: the archive carries a full JRE alongside the launcher.
    info "Downloading JetBrains Toolbox (~150 MB)..."
    if ! wget -qO "$tmpfile" "$download_url"; then
        error "Failed to download JetBrains Toolbox."
        return 1
    fi
    verify_download "$tmpfile" "tar.gz" "JetBrains Toolbox" || return 1

    local tmpdir
    tmpdir=$(mktemp -d) || { error "Failed to create temporary directory."; return 1; }
    if ! tar -xzf "$tmpfile" -C "$tmpdir"; then
        rm -rf "$tmpdir"
        error "Failed to extract JetBrains Toolbox archive."
        return 1
    fi

    # The archive holds a single jetbrains-toolbox-<version>/bin/ tree: the
    # launcher stub plus its bundled jre/, lib/, and native .so files. The whole
    # directory has to be installed together -- copying just the stub out of it
    # yields a launcher that cannot find libjvm.so and dies on start.
    local src_bin
    src_bin=$(find "$tmpdir" -mindepth 2 -maxdepth 2 -type d -name bin -print -quit)
    if [[ -z "$src_bin" || ! -x "$src_bin/jetbrains-toolbox" ]]; then
        rm -rf "$tmpdir"
        error "Unexpected JetBrains Toolbox archive layout; could not locate bin/ tree."
        return 1
    fi

    # Replace the app tree only. Installed IDEs and their settings live in
    # apps/ and ~/.local/share/JetBrains/<IDE>, which are left untouched.
    mkdir -p "$_JB_TOOLBOX_DIR"
    rm -rf "${_JB_TOOLBOX_DIR:?}/bin"
    if ! cp -a "$src_bin" "$_JB_TOOLBOX_DIR/bin"; then
        rm -rf "$tmpdir"
        error "Failed to install JetBrains Toolbox files."
        return 1
    fi
    chmod +x "$_JB_TOOLBOX_BIN"
    rm -rf "$tmpdir"

    # Create symlink on PATH
    mkdir -p "$HOME/.local/bin"
    ln -sf "$_JB_TOOLBOX_BIN" "$HOME/.local/bin/jetbrains-toolbox"

    # Toolbox writes its own menu entry on first run, but that only happens once
    # it has started successfully. Install one now so the launcher is reachable
    # from the menu immediately, with an absolute Exec= so it does not depend on
    # ~/.local/bin being on the desktop session's PATH.
    mkdir -p "$(dirname "$_JB_TOOLBOX_ICON")" "$(dirname "$_JB_TOOLBOX_DESKTOP")"
    [[ -f "$_JB_TOOLBOX_DIR/bin/toolbox.svg" ]] && \
        cp -f "$_JB_TOOLBOX_DIR/bin/toolbox.svg" "$_JB_TOOLBOX_ICON"
    cat > "$_JB_TOOLBOX_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Comment=Manage JetBrains IDEs and projects
Exec=$_JB_TOOLBOX_BIN %U
Icon=jetbrains-toolbox
Terminal=false
StartupNotify=false
StartupWMClass=jetbrains-toolbox
Categories=Development;IDE;
EOF
    refresh_desktop_caches

    # Toolbox is a tray/GUI app; starting it from a TTY or an SSH session with
    # no display just produces an immediate silent exit.
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        nohup setsid "$_JB_TOOLBOX_BIN" &>/dev/null &
        disown 2>/dev/null || true
        info "JetBrains Toolbox installed. It will launch shortly to complete setup."
    else
        info "JetBrains Toolbox installed. No graphical session detected -- start it"
        info "from your application menu, or run: jetbrains-toolbox"
    fi
}

uninstall_jetbrains_toolbox() {
    info "Uninstalling JetBrains Toolbox..."
    # Kill running instance
    pkill -f "jetbrains-toolbox" 2>/dev/null || true
    rm -f "$HOME/.local/bin/jetbrains-toolbox"
    rm -rf "$_JB_TOOLBOX_DIR"
    rm -f "$_JB_TOOLBOX_DESKTOP"
    rm -f "$_JB_TOOLBOX_ICON"
    rm -rf "$HOME/.config/JetBrains/Toolbox"
    refresh_desktop_caches
    info "JetBrains Toolbox uninstalled. Installed IDEs were not removed."
}

update_jetbrains_toolbox() {
    info "Updating JetBrains Toolbox..."
    # Toolbox updates itself; just re-run the installer to force an update
    install_jetbrains_toolbox
}

get_version_jetbrains_toolbox() {
    if [[ -f "$_JB_TOOLBOX_BIN" ]]; then
        "$_JB_TOOLBOX_BIN" --version 2>/dev/null | grep -oP '[0-9]+(\.[0-9]+)+' | head -1 || echo ""
    else
        echo ""
    fi
}
