#!/bin/bash
# Zotero reference manager installer functions

# --- Zotero ---

_ZOTERO_INSTALL_DIR="/opt/zotero"

check_zotero() {
    _have_cmd zotero || [[ -f "$_ZOTERO_INSTALL_DIR/zotero" ]]
}

install_zotero() {
    info "Installing Zotero..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            repo_or_aur zotero
            ;;
        *)
            _install_zotero_tarball
            ;;
    esac
    info "Zotero installed."
    info "Launch Zotero from your application menu or by running 'zotero'."
}

_install_zotero_tarball() {
    # Zotero provides a tarball installer with a bundled set-up script
    local tmpfile
    tmpfile=$(mktemp /tmp/zotero-XXXXXX.tar.bz2)
    CLEANUP_FILES+=("$tmpfile")

    # The Zotero download page provides a stable URL
    local url="https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64"
    if ! wget -qO "$tmpfile" "$url"; then
        error "Failed to download Zotero."
        return 1
    fi

    sudo mkdir -p "$_ZOTERO_INSTALL_DIR"
    sudo tar -xjf "$tmpfile" -C "$_ZOTERO_INSTALL_DIR" --strip-components=1

    # Register the desktop integration (sets up MIME types and desktop entry)
    if [[ -f "$_ZOTERO_INSTALL_DIR/set_launcher_icon" ]]; then
        (cd "$_ZOTERO_INSTALL_DIR" && sudo bash set_launcher_icon 2>/dev/null) || true
    fi

    # Create a symlink in PATH
    sudo ln -sf "$_ZOTERO_INSTALL_DIR/zotero" /usr/local/bin/zotero

    # Install desktop entry
    sudo tee /usr/share/applications/zotero.desktop > /dev/null <<DESKTOP
[Desktop Entry]
Name=Zotero
Comment=Collect, organize, cite, and share your research
Exec=$_ZOTERO_INSTALL_DIR/zotero %U
Icon=$_ZOTERO_INSTALL_DIR/chrome/icons/default/default256.png
Type=Application
Categories=Office;Education;
MimeType=x-scheme-handler/zotero;
DESKTOP
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
}

uninstall_zotero() {
    info "Uninstalling Zotero..."
    if [[ -d "$_ZOTERO_INSTALL_DIR" ]]; then
        sudo rm -rf "$_ZOTERO_INSTALL_DIR"
        sudo rm -f /usr/local/bin/zotero
        sudo rm -f /usr/share/applications/zotero.desktop
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    else
        case "$DISTRO_FAMILY" in
            arch)
                aur_remove zotero 2>/dev/null || \
                    sudo pacman -Rs --noconfirm zotero 2>/dev/null || true
                ;;
        esac
    fi
    # Note: user library data lives in ~/Zotero — we do not delete it
}

update_zotero() {
    info "Updating Zotero..."
    if [[ "$DISTRO_FAMILY" == "arch" ]] && ! [[ -d "$_ZOTERO_INSTALL_DIR" ]]; then
        repo_or_aur zotero
    else
        _install_zotero_tarball
    fi
}

get_version_zotero() {
    if [[ -f "$_ZOTERO_INSTALL_DIR/zotero" ]]; then
        # Version is embedded in the application.ini file
        grep -oP '(?<=^Version=)[0-9]+\.[0-9]+\.[0-9]+' \
            "$_ZOTERO_INSTALL_DIR/application.ini" 2>/dev/null || echo ""
    else
        _ver_from_pkg zotero || echo ""
    fi
}
