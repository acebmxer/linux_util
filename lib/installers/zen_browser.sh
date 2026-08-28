#!/bin/bash
# Zen Browser installer functions
#
# Zen Browser (https://zen-browser.app) is a Firefox-based browser focused on
# privacy and a calmer, customizable UI (vertical tabs, split view, workspaces).
# The project is still in beta. Upstream ships Linux builds as a tarball and
# Flatpak (plus a per-release AppImage on GitHub). The official tarball is
# preferred here on every distro, with Flatpak as the fallback when the tarball
# cannot be installed (unsupported architecture or failed download/extract).

# --- Zen Browser ---

_ZEN_FLATPAK_ID="app.zen_browser.zen"
_ZEN_DIR="$HOME/.local/share/zen-browser"
_ZEN_BIN="$_ZEN_DIR/zen/zen"
_ZEN_DESKTOP="$HOME/.local/share/applications/zen-browser.desktop"

check_zen_browser() {
    _check_standard zen-browser "" "$_ZEN_FLATPAK_ID" || [[ -x "$_ZEN_BIN" ]]
}

# Echo the official tarball download URL for this machine's architecture.
_zen_tarball_url() {
    case "$(uname -m)" in
        x86_64)  echo "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz" ;;
        aarch64) echo "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-aarch64.tar.xz" ;;
        *) error "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac
}

# Default install path: official tarball + wrapper script + desktop entry.
# The tarball extracts to a top-level "zen/" directory.
_install_zen_tarball() {
    local download_url
    download_url=$(_zen_tarball_url) || return 1

    # tar -xJf needs the xz binary; most distros ship it, Debian calls it xz-utils
    if ! command -v xz &>/dev/null; then
        case "$DISTRO_FAMILY" in
            debian) pkg_install xz-utils ;;
            *)      pkg_install xz ;;
        esac
    fi

    local tmptar
    tmptar=$(mktemp /tmp/zen-XXXXXX.tar.xz)
    info "Downloading Zen Browser tarball..."
    if ! wget -qO "$tmptar" "$download_url"; then
        rm -f "$tmptar"
        error "Failed to download Zen Browser tarball."
        return 1
    fi

    mkdir -p "$_ZEN_DIR"
    # Preserve distribution/ (policies.json written by the browser-extension
    # installers) across re-extracts; the tarball does not ship one.
    local dist_backup=""
    if [[ -d "$_ZEN_DIR/zen/distribution" ]]; then
        dist_backup=$(mktemp -d /tmp/zen-dist-XXXXXX)
        cp -a "$_ZEN_DIR/zen/distribution/." "$dist_backup/"
    fi
    rm -rf "$_ZEN_DIR/zen"
    if ! tar -xJf "$tmptar" -C "$_ZEN_DIR"; then
        rm -f "$tmptar"
        [[ -n "$dist_backup" ]] && rm -rf "$dist_backup"
        error "Failed to extract Zen Browser tarball."
        return 1
    fi
    rm -f "$tmptar"
    if [[ -n "$dist_backup" ]]; then
        mkdir -p "$_ZEN_DIR/zen/distribution"
        cp -a "$dist_backup/." "$_ZEN_DIR/zen/distribution/"
        rm -rf "$dist_backup"
    fi

    # Create wrapper script on PATH
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/zen-browser" <<'EOF'
#!/bin/bash
exec "$HOME/.local/share/zen-browser/zen/zen" "$@"
EOF
    chmod +x "$HOME/.local/bin/zen-browser"

    # Install icon (shipped inside the tarball)
    local icon_dir="$HOME/.local/share/icons/hicolor/128x128/apps"
    mkdir -p "$icon_dir"
    cp "$_ZEN_DIR/zen/browser/chrome/icons/default/default128.png" \
        "$icon_dir/zen-browser.png" 2>/dev/null || true

    # Create .desktop entry
    cat > "$_ZEN_DESKTOP" <<EOF
[Desktop Entry]
Name=Zen Browser
Comment=Privacy-focused Firefox-based browser
Exec=$HOME/.local/bin/zen-browser %u
Icon=zen-browser
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=zen
EOF
    refresh_desktop_caches
    info "Zen Browser tarball installed. Ensure ~/.local/bin is in your PATH."
}

install_zen_browser() {
    info "Installing Zen Browser (Beta)..."
    ensure_tools
    # The official tarball is the preferred install method on all distros
    if _install_zen_tarball; then
        :
    elif has_flatpak; then
        info "Tarball install unavailable — falling back to Flatpak."
        sudo flatpak install -y flathub "$_ZEN_FLATPAK_ID"
    else
        error "Could not install the Zen Browser tarball and Flatpak is not available."
        return 1
    fi
    info "Zen Browser installed."
}

uninstall_zen_browser() {
    info "Uninstalling Zen Browser..."
    if flatpak_is_installed "$_ZEN_FLATPAK_ID"; then
        flatpak uninstall -y --user "$_ZEN_FLATPAK_ID" 2>/dev/null || \
            sudo flatpak uninstall -y --system "$_ZEN_FLATPAK_ID"
    fi
    rm -f "$HOME/.local/bin/zen-browser"
    rm -f "$_ZEN_DESKTOP"
    rm -f "$HOME/.local/share/icons/hicolor/128x128/apps/zen-browser.png"
    rm -rf "$_ZEN_DIR"
    rm -rf "$HOME/.zen" "$HOME/.var/app/$_ZEN_FLATPAK_ID"
    refresh_desktop_caches
    info "Zen Browser uninstalled."
}

update_zen_browser() {
    info "Updating Zen Browser..."
    if [[ -x "$_ZEN_BIN" ]]; then
        # Re-download and re-extract the latest tarball in place
        _install_zen_tarball
    elif flatpak_is_installed "$_ZEN_FLATPAK_ID"; then
        flatpak update -y --user "$_ZEN_FLATPAK_ID" 2>/dev/null || \
            sudo flatpak update -y --system "$_ZEN_FLATPAK_ID"
    fi
}

get_version_zen_browser() {
    # Beta versions look like "1.21b" — read application.ini rather than
    # executing the browser binary
    if [[ -f "$_ZEN_DIR/zen/application.ini" ]]; then
        local v
        v=$(grep -m1 '^Version=' "$_ZEN_DIR/zen/application.ini" | cut -d= -f2)
        [[ -n "$v" ]] && { echo "$v"; return; }
    fi
    _ver_from_flatpak "$_ZEN_FLATPAK_ID" || echo ""
}
