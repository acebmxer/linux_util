#!/bin/bash
# Ventoy bootable USB creator installer functions

# --- Ventoy ---

_VENTOY_INSTALL_DIR="/opt/ventoy"

check_ventoy() {
    [[ -f "$_VENTOY_INSTALL_DIR/Ventoy2Disk.sh" ]] || _have_cmd ventoy
}

install_ventoy() {
    info "Installing Ventoy..."
    ensure_tools

    # Root unpacks this into /opt, so it must match the SHA-256 GitHub
    # publishes for the release file.
    local tmpdir tmpfile ver_num
    tmpdir=$(mktemp -d /tmp/ventoy-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tmpfile=$(github_asset_download ventoy/Ventoy 'ventoy-[0-9.]+-linux\.tar\.gz' "$tmpdir") || return 1
    ver_num=$(basename "$tmpfile" | grep -oP 'ventoy-\K[0-9.]+(?=-linux)')

    sudo mkdir -p "$_VENTOY_INSTALL_DIR"
    # Tarball entries are prefixed './ventoy-X.Y.Z/...', so strip the leading
    # './' and the version directory (2 components) to land files flat in the dir.
    sudo tar -xzf "$tmpfile" -C "$_VENTOY_INSTALL_DIR" --strip-components=2

    # Create a launcher wrapper in PATH for convenience
    sudo tee /usr/local/bin/ventoy > /dev/null <<'WRAPPER'
#!/bin/bash
exec sudo /opt/ventoy/VentoyGUI.x86_64 "$@" 2>/dev/null || \
     sudo /opt/ventoy/VentoyGUI.aarch64 "$@" 2>/dev/null || \
     sudo /opt/ventoy/Ventoy2Disk.sh "$@"
WRAPPER
    sudo chmod +x /usr/local/bin/ventoy

    # GUI launcher for the desktop menu. The GUI needs root, so escalate with
    # pkexec (graphical prompt); forward DISPLAY/XAUTHORITY so root can reach
    # the user's X session, which pkexec otherwise strips from the environment.
    sudo tee /usr/local/bin/ventoy-gui > /dev/null <<'GUILAUNCHER'
#!/bin/bash
gui=/opt/ventoy/VentoyGUI.x86_64
[[ -x "$gui" ]] || gui=/opt/ventoy/VentoyGUI.aarch64
exec pkexec env DISPLAY="$DISPLAY" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" "$gui" "$@"
GUILAUNCHER
    sudo chmod +x /usr/local/bin/ventoy-gui

    # Desktop menu entry
    sudo tee /usr/share/applications/ventoy.desktop > /dev/null <<DESKTOP
[Desktop Entry]
Name=Ventoy
Comment=Create a multiboot USB drive
Exec=/usr/local/bin/ventoy-gui
Icon=$_VENTOY_INSTALL_DIR/WebUI/static/img/VentoyLogo.png
Type=Application
Categories=System;Utility;
Terminal=false
DESKTOP
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true

    info "Ventoy ${ver_num} installed to $_VENTOY_INSTALL_DIR."
    info "Run 'sudo /opt/ventoy/Ventoy2Disk.sh -i /dev/sdX' to install Ventoy to a USB drive."
    info "Or launch the GUI from the application menu, or run: ventoy-gui"
}

uninstall_ventoy() {
    info "Uninstalling Ventoy..."
    sudo rm -rf "$_VENTOY_INSTALL_DIR"
    sudo rm -f /usr/local/bin/ventoy /usr/local/bin/ventoy-gui
    sudo rm -f /usr/share/applications/ventoy.desktop
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    info "Ventoy uninstalled."
}

update_ventoy() {
    info "Updating Ventoy..."
    install_ventoy
}

get_version_ventoy() {
    if [[ -f "$_VENTOY_INSTALL_DIR/ventoy/version" ]]; then
        cat "$_VENTOY_INSTALL_DIR/ventoy/version" 2>/dev/null || echo ""
    else
        echo ""
    fi
}
