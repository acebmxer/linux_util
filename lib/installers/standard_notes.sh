#!/bin/bash
# Standard Notes installer functions

# --- Standard Notes ---

_SN_APPIMAGE="$HOME/.local/share/standard-notes/standard-notes.AppImage"
_SN_DESKTOP="$HOME/.local/share/applications/standard-notes.desktop"

check_standard_notes() {
    command -v standard-notes &>/dev/null || \
        [[ -f "$_SN_APPIMAGE" ]] || \
        pkg_check_installed standard-notes || \
        (flatpak_is_installed "org.standardnotes.standardnotes")
}

_sn_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/standardnotes/app/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+linux[^"]*\.'"$ext"'"' \
        | grep -v "arm\|i386" | head -1
}

install_standard_notes() {
    info "Installing Standard Notes..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_sn_latest_url "deb")
            if [[ -n "$url" ]]; then
                local tmpfile
                tmpfile=$(mktemp /tmp/standard-notes-XXXXXX.deb)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Standard Notes .deb."; return 1; }
                sudo apt install -y "$tmpfile"
                return 0
            fi
            warn "No .deb found. Falling back to AppImage..."
            _sn_install_appimage
            ;;
        fedora|rhel)
            if has_flatpak; then
                flatpak install -y flathub org.standardnotes.standardnotes
            else
                _sn_install_appimage
            fi
            ;;
        arch)
            aur_ensure standard-notes-bin
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub org.standardnotes.standardnotes
            else
                _sn_install_appimage
            fi
            ;;
    esac
    info "Standard Notes installed."
}

_sn_install_appimage() {
    local url
    url=$(_sn_latest_url "AppImage")
    [[ -z "$url" ]] && { error "Could not find Standard Notes AppImage URL."; return 1; }

    mkdir -p "$(dirname "$_SN_APPIMAGE")"
    wget -qO "$_SN_APPIMAGE" "$url" || { error "Failed to download Standard Notes AppImage."; return 1; }
    chmod +x "$_SN_APPIMAGE"

    mkdir -p "$HOME/.local/bin"
    ln -sf "$_SN_APPIMAGE" "$HOME/.local/bin/standard-notes"

    cat > "$_SN_DESKTOP" <<EOF
[Desktop Entry]
Name=Standard Notes
Comment=A safe place for your notes
Exec=$_SN_APPIMAGE --no-sandbox %U
Icon=standard-notes
Terminal=false
Type=Application
Categories=Utility;TextEditor;
StartupWMClass=standard notes
EOF
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications 2>/dev/null || true
}

uninstall_standard_notes() {
    info "Uninstalling Standard Notes..."
    if flatpak_is_installed "org.standardnotes.standardnotes"; then
        flatpak uninstall -y org.standardnotes.standardnotes
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y standard-notes 2>/dev/null || true ;;
            arch)    aur_remove standard-notes-bin 2>/dev/null || sudo pacman -Rs --noconfirm standard-notes 2>/dev/null || true ;;
        esac
    fi
    rm -f "$_SN_APPIMAGE"
    rm -f "$HOME/.local/bin/standard-notes"
    rm -f "$_SN_DESKTOP"
    rm -rf "$HOME/.config/Standard Notes"
    rm -rf "$(dirname "$_SN_APPIMAGE")"
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications 2>/dev/null || true
}

update_standard_notes() {
    info "Updating Standard Notes..."
    if flatpak_is_installed "org.standardnotes.standardnotes"; then
        flatpak update -y org.standardnotes.standardnotes
    elif [[ -f "$_SN_APPIMAGE" ]]; then
        _sn_install_appimage
    else
        case "$DISTRO_FAMILY" in
            debian)   install_standard_notes ;;
            arch)
                aur_ensure standard-notes-bin
                ;;
        esac
    fi
}

get_version_standard_notes() {
    _ver_from_flatpak org.standardnotes || _ver_from_pkg standard-notes || echo ""
}
