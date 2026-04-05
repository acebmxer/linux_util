#!/bin/bash
# Cursor IDE installer functions

# --- Cursor IDE ---

_CURSOR_APPIMAGE="$HOME/.local/share/cursor/cursor.AppImage"
_CURSOR_DESKTOP="$HOME/.local/share/applications/cursor.desktop"

check_cursor() {
    command -v cursor &>/dev/null || [[ -f "$_CURSOR_APPIMAGE" ]]
}

install_cursor() {
    info "Installing Cursor IDE..."
    ensure_tools

    local api_url="https://www.cursor.com/api/download?platform=linux&releaseTrack=stable"
    local download_url
    download_url=$(curl -fsSL "$api_url" | grep -oP '"url"\s*:\s*"\K[^"]+') || {
        error "Failed to retrieve Cursor download URL."
        return 1
    }
    [[ -z "$download_url" ]] && { error "Cursor download URL is empty."; return 1; }

    mkdir -p "$(dirname "$_CURSOR_APPIMAGE")"
    info "Downloading Cursor AppImage..."
    if ! wget -qO "$_CURSOR_APPIMAGE" "$download_url"; then
        error "Failed to download Cursor AppImage."
        return 1
    fi
    chmod +x "$_CURSOR_APPIMAGE"

    # Create wrapper script on PATH
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/cursor" <<'EOF'
#!/bin/bash
exec "$HOME/.local/share/cursor/cursor.AppImage" --no-sandbox "$@"
EOF
    chmod +x "$HOME/.local/bin/cursor"

    # Install icon
    local icon_dir="$HOME/.local/share/icons/hicolor/512x512/apps"
    mkdir -p "$icon_dir"
    if "$_CURSOR_APPIMAGE" --appimage-extract "usr/share/icons/hicolor/512x512/apps/cursor.png" &>/dev/null; then
        mv squashfs-root/usr/share/icons/hicolor/512x512/apps/cursor.png "$icon_dir/cursor.png" 2>/dev/null || true
        rm -rf squashfs-root
    fi

    # Create .desktop entry
    cat > "$_CURSOR_DESKTOP" <<EOF
[Desktop Entry]
Name=Cursor
Comment=AI-powered code editor
Exec=$HOME/.local/bin/cursor %U
Icon=cursor
Terminal=false
Type=Application
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupWMClass=Cursor
EOF
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications 2>/dev/null || true
    info "Cursor IDE installed. Ensure ~/.local/bin is in your PATH."
}

uninstall_cursor() {
    info "Uninstalling Cursor IDE..."
    rm -f "$_CURSOR_APPIMAGE"
    rm -f "$HOME/.local/bin/cursor"
    rm -f "$_CURSOR_DESKTOP"
    rm -f "$HOME/.local/share/icons/hicolor/512x512/apps/cursor.png"
    rm -rf "$HOME/.config/Cursor"
    rm -rf "$HOME/.local/share/cursor"
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications 2>/dev/null || true
    info "Cursor IDE uninstalled."
}

update_cursor() {
    info "Updating Cursor IDE..."
    # Re-download latest AppImage
    local api_url="https://www.cursor.com/api/download?platform=linux&releaseTrack=stable"
    local download_url
    download_url=$(curl -fsSL "$api_url" | grep -oP '"url"\s*:\s*"\K[^"]+') || {
        error "Failed to retrieve Cursor download URL."
        return 1
    }
    [[ -z "$download_url" ]] && { error "Cursor download URL is empty."; return 1; }

    info "Downloading latest Cursor AppImage..."
    if ! wget -qO "$_CURSOR_APPIMAGE" "$download_url"; then
        error "Failed to download Cursor AppImage."
        return 1
    fi
    chmod +x "$_CURSOR_APPIMAGE"
    info "Cursor IDE updated."
}

get_version_cursor() {
    if [[ -f "$_CURSOR_APPIMAGE" ]]; then
        local tmpdir
        tmpdir=$(mktemp -d)
        trap "rm -rf '$tmpdir'" RETURN
        if (cd "$tmpdir" && timeout 10 "$_CURSOR_APPIMAGE" --appimage-extract "resources/app/package.json") &>/dev/null; then
            awk -F'"' '/"version"/{print $4; exit}' "$tmpdir/squashfs-root/resources/app/package.json" 2>/dev/null && return
        fi
    fi
    echo ""
}
