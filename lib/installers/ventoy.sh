#!/bin/bash
# Ventoy bootable USB creator installer functions

# --- Ventoy ---

_VENTOY_INSTALL_DIR="/opt/ventoy"

check_ventoy() {
    [[ -f "$_VENTOY_INSTALL_DIR/Ventoy2Disk.sh" ]] || command -v ventoy &>/dev/null
}

install_ventoy() {
    info "Installing Ventoy..."
    ensure_tools

    local version arch tmpfile
    version=$(curl -fsSL https://api.github.com/repos/ventoy/Ventoy/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest Ventoy version."; return 1; }
    # Strip leading 'v' if present
    local ver_num="${version#v}"

    arch="x86_64"
    [[ "$(uname -m)" == "aarch64" ]] && arch="aarch64"

    tmpfile=$(mktemp /tmp/ventoy-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")

    if ! wget -qO "$tmpfile" \
        "https://github.com/ventoy/Ventoy/releases/download/${version}/ventoy-${ver_num}-linux.tar.gz"; then
        error "Failed to download Ventoy."
        return 1
    fi

    sudo mkdir -p "$_VENTOY_INSTALL_DIR"
    sudo tar -xzf "$tmpfile" -C "$_VENTOY_INSTALL_DIR" --strip-components=1

    # Create a launcher wrapper in PATH for convenience
    sudo tee /usr/local/bin/ventoy > /dev/null <<'WRAPPER'
#!/bin/bash
exec sudo /opt/ventoy/VentoyGUI.x86_64 "$@" 2>/dev/null || \
     sudo /opt/ventoy/VentoyGUI.aarch64 "$@" 2>/dev/null || \
     sudo /opt/ventoy/Ventoy2Disk.sh "$@"
WRAPPER
    sudo chmod +x /usr/local/bin/ventoy

    info "Ventoy ${ver_num} installed to $_VENTOY_INSTALL_DIR."
    info "Run 'sudo /opt/ventoy/Ventoy2Disk.sh -i /dev/sdX' to install Ventoy to a USB drive."
    info "Or launch the GUI: sudo /opt/ventoy/VentoyGUI.x86_64"
}

uninstall_ventoy() {
    info "Uninstalling Ventoy..."
    sudo rm -rf "$_VENTOY_INSTALL_DIR"
    sudo rm -f /usr/local/bin/ventoy
    info "Ventoy uninstalled."
}

update_ventoy() {
    info "Updating Ventoy..."
    install_ventoy
}

get_version_ventoy() {
    if [[ -f "$_VENTOY_INSTALL_DIR/ventoy/VERSION" ]]; then
        cat "$_VENTOY_INSTALL_DIR/ventoy/VERSION" 2>/dev/null || echo ""
    elif [[ -d "$_VENTOY_INSTALL_DIR" ]]; then
        # Version is encoded in the directory structure
        ls "$_VENTOY_INSTALL_DIR"/ventoy_*.tar.gz 2>/dev/null | \
            grep -oP 'ventoy_\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
    else
        echo ""
    fi
}
