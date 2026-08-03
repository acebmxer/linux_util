#!/bin/bash
# Postman installer functions

# --- Postman ---

_POSTMAN_DIR="$HOME/.local/share/postman"
_POSTMAN_BIN="$HOME/.local/bin/postman"
_POSTMAN_DESKTOP="$HOME/.local/share/applications/postman.desktop"

check_postman() {
    _have_cmd postman || [[ -f "$_POSTMAN_DIR/Postman" ]]
}

install_postman() {
    info "Installing Postman..."
    ensure_tools

    local download_url="https://dl.pstmn.io/download/latest/linux_64"
    local tmpfile
    tmpfile=$(mktemp /tmp/postman-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")

    info "Downloading Postman..."
    if ! wget -qO "$tmpfile" "$download_url"; then
        error "Failed to download Postman."
        return 1
    fi
    verify_download "$tmpfile" "tar.gz" "Postman" || return 1

    rm -rf "$_POSTMAN_DIR"
    mkdir -p "$_POSTMAN_DIR"
    tar -xzf "$tmpfile" -C "$_POSTMAN_DIR" --strip-components=1

    # Create wrapper on PATH
    mkdir -p "$HOME/.local/bin"
    cat > "$_POSTMAN_BIN" <<EOF
#!/bin/bash
exec "$_POSTMAN_DIR/Postman" "\$@"
EOF
    chmod +x "$_POSTMAN_BIN"

    # Create .desktop entry
    cat > "$_POSTMAN_DESKTOP" <<EOF
[Desktop Entry]
Name=Postman
Comment=API platform for building and using APIs
Exec=$_POSTMAN_DIR/Postman
Icon=$_POSTMAN_DIR/app/icons/icon_128x128.png
Terminal=false
Type=Application
Categories=Development;Utility;
StartupWMClass=postman
EOF
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications 2>/dev/null || true
    info "Postman installed."
}

uninstall_postman() {
    info "Uninstalling Postman..."
    rm -f "$_POSTMAN_BIN"
    rm -f "$_POSTMAN_DESKTOP"
    rm -rf "$_POSTMAN_DIR"
    rm -rf "$HOME/.config/Postman"
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications 2>/dev/null || true
    info "Postman uninstalled."
}

update_postman() {
    info "Updating Postman..."
    install_postman
}

get_version_postman() {
    local pkg_json="$_POSTMAN_DIR/app/package.json"
    if [[ -f "$pkg_json" ]]; then
        awk -F'"' '/"version"/{print $4; exit}' "$pkg_json" 2>/dev/null || echo ""
    else
        echo ""
    fi
}
