#!/bin/bash
# ArtCraft installer functions
# ArtCraft Launcher, plus the helpers shared with the individual Craft apps
# (lib/installers/craft_apps.sh).

# --- ArtCraft ---

# Every Craft app, and the launcher, publishes the same release layout on
# GitHub: <name>-<version>-linux-<x86_64|aarch64>.{deb,rpm,AppImage,flatpak}
# with a SHA256SUMS.txt beside them, and the .deb/.rpm package is named after
# the app. That is why one set of helpers serves all of them. The main ArtCraft
# desktop app (storytold/artcraft) is deliberately not what "ArtCraft" installs:
# it publishes Windows and macOS builds only.
#
# This is deliberately the only copy of the download/install logic for these
# apps -- craft_apps.sh calls it, so do not add a second one.

_craft_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) error "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac
}

# Installed from the release AppImage (Arch family: no .deb/.rpm route).
_craft_appimage_path() { echo "$HOME/Applications/$1.AppImage"; }
_craft_appimage_stamp() { echo "$HOME/Applications/.$1.version"; }

# check_<app> for every Craft app: package, command, or the Arch AppImage.
_craft_check() {
    local pkg="$1"
    _have_cmd "$pkg" && return 0
    pkg_check_installed "$pkg" && return 0
    [[ -x "$(_craft_appimage_path "$pkg")" ]]
}

# Latest published version of repo $1, from the release tag ("v0.6.0" -> "0.6.0").
_craft_latest_version() {
    curl -fsSL --max-time 15 "https://api.github.com/repos/storytold/$1/releases/latest" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"v?\K[^"]+' | head -1
}

# Download URL of repo $1's newest release asset with extension $2.
_craft_asset_url() {
    local repo="$1" ext="$2" arch
    arch=$(_craft_arch) || return 1
    curl -fsSL "https://api.github.com/repos/storytold/${repo}/releases/latest" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -m1 -E "/[a-z-]+-[0-9][^/]*-linux-${arch}\.${ext}\$"
}

# Download and verify one release asset into a temp file, left in
# $_CRAFT_FILE. Not printed: verify_download and the checksum check write their
# own messages to stdout, which would end up inside a command substitution.
# Usage: _craft_download repo ext label
_craft_download() {
    local repo="$1" ext="$2" label="$3" url tmpfile
    _CRAFT_FILE=""
    url=$(_craft_asset_url "$repo" "$ext")
    if [[ -z "$url" ]]; then
        error "Could not find a ${label} .${ext} release asset."
        return 1
    fi
    tmpfile=$(mktemp "/tmp/${repo}-XXXXXX.${ext}") || return 1
    CLEANUP_FILES+=("$tmpfile")
    wget -qO "$tmpfile" "$url" || { error "Failed to download ${label} .${ext}."; return 1; }
    # An AppImage is an ELF file, not a package, so it has no verify_download type.
    if [[ "$ext" != "AppImage" ]]; then
        verify_download "$tmpfile" "$ext" "$label" || return 1
    fi
    github_verify_checksum "https://api.github.com/repos/storytold/${repo}/releases/latest" \
        "$(basename "$url")" "$tmpfile" || return 1
    _CRAFT_FILE="$tmpfile"
}

# Menu entry for an AppImage install. The AppImage carries its own .desktop
# file and icon; extract those and point Exec at the installed copy. Every Craft
# package ships them as ai.storyteller.<package>, which is also what the .deb and
# .rpm use, so the entry replaces rather than duplicates a packaged one.
_craft_menu_desktop() { echo "$HOME/.local/share/applications/ai.storyteller.$1.desktop"; }
_craft_menu_icon() { echo "$HOME/.local/share/icons/hicolor/256x256/apps/ai.storyteller.$1.png"; }

_craft_add_menu_entry() {
    local pkg="$1" label="$2" appimage="$3" tmpdir src_desktop src_icon
    tmpdir=$(mktemp -d /tmp/craft-extract-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    # Extraction needs no FUSE; it unpacks into ./squashfs-root.
    if ! ( cd "$tmpdir" && "$appimage" --appimage-extract >/dev/null 2>&1 ); then
        warn "Could not read ${label}'s menu entry from its AppImage; no menu item was added."
        return 0
    fi
    src_desktop=$(find "$tmpdir/squashfs-root" -maxdepth 1 -name '*.desktop' | head -1)
    src_icon=$(find "$tmpdir/squashfs-root" -maxdepth 1 -name '*.png' | head -1)
    if [[ -z "$src_desktop" ]]; then
        warn "${label}'s AppImage has no menu entry; no menu item was added."
        return 0
    fi
    mkdir -p "$HOME/.local/share/applications" || return 1
    sed -e "s|^Exec=[^ ]*|Exec=\"${appimage}\"|" -e "s|^TryExec=.*|TryExec=${appimage}|" \
        "$src_desktop" > "$(_craft_menu_desktop "$pkg")"
    if [[ -n "$src_icon" ]]; then
        install -Dm644 "$src_icon" "$(_craft_menu_icon "$pkg")"
    fi
    refresh_desktop_caches
}

# Arch family: nothing is packaged for pacman, so use the release AppImage.
_craft_install_appimage() {
    local repo="$1" pkg="$2" label="$3" dest
    _craft_download "$repo" "AppImage" "$label" || return 1
    dest=$(_craft_appimage_path "$pkg")
    mkdir -p "$HOME/Applications" "$HOME/.local/bin" || return 1
    install -m 755 "$_CRAFT_FILE" "$dest" || { error "Failed to install ${label}."; return 1; }
    ln -sf "$dest" "$HOME/.local/bin/$pkg"
    _craft_latest_version "$repo" > "$(_craft_appimage_stamp "$pkg")"
    _craft_add_menu_entry "$pkg" "$label" "$dest"
    info "${label} installed to ${dest} (command: ${pkg})."
}

# Usage: _craft_install repo pkg label
_craft_install() {
    local repo="$1" pkg="$2" label="$3"
    info "Installing ${label}..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _craft_download "$repo" "deb" "$label" || return 1
            pkg_install "$_CRAFT_FILE" || return 1
            ;;
        fedora|rhel)
            _craft_download "$repo" "rpm" "$label" || return 1
            pkg_install "$_CRAFT_FILE" || return 1
            ;;
        suse)
            _craft_download "$repo" "rpm" "$label" || return 1
            pkg_install --allow-unsigned-rpm "$_CRAFT_FILE" || return 1
            ;;
        arch)
            _craft_install_appimage "$repo" "$pkg" "$label" || return 1
            ;;
    esac
    refresh_desktop_caches
    info "${label} installed."
}

# Usage: _craft_uninstall pkg label
# Settings and documents the apps keep under ~ are intentionally left alone.
_craft_uninstall() {
    local pkg="$1" label="$2"
    info "Uninstalling ${label}..."
    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        pkg_remove "$pkg" || return 1
    fi
    rm -f "$(_craft_appimage_path "$pkg")" "$(_craft_appimage_stamp "$pkg")" "$HOME/.local/bin/$pkg"
    # Only the entry this installer wrote: it points at our AppImage. A user's own
    # copy elsewhere keeps its entry.
    if grep -qF "$(_craft_appimage_path "$pkg")" "$(_craft_menu_desktop "$pkg")" 2>/dev/null; then
        rm -f "$(_craft_menu_desktop "$pkg")" "$(_craft_menu_icon "$pkg")"
    fi
    refresh_desktop_caches
}

# Usage: _craft_update repo pkg label
_craft_update() {
    local repo="$1" pkg="$2" label="$3" installed latest
    info "Updating ${label}..."
    installed=$(_craft_version "$pkg")
    latest=$(_craft_latest_version "$repo")
    # An unknown version on either side falls through and reinstalls rather than
    # risk skipping a real update.
    if [[ -n "$installed" && "$installed" == "$latest" ]]; then
        info "${label} is already at the latest version (${installed})."
        return 0
    fi
    _craft_install "$repo" "$pkg" "$label"
}

_craft_version() {
    local pkg="$1" stamp v
    stamp=$(_craft_appimage_stamp "$pkg")
    if [[ -r "$stamp" ]]; then
        v=$(head -1 "$stamp" | tr -d '[:space:]')
        [[ -n "$v" ]] && { printf '%s\n' "$v"; return 0; }
    fi
    _ver_from_pkg "$pkg" || echo ""
}

# --- ArtCraft Launcher ---

# An AppImage the user downloaded and ran themselves: it writes its own menu
# entry, and that entry's Exec line is the only record of where the file is
# (it can be anywhere, e.g. ~/Downloads). Prints the path when it still exists.
_artcraft_launcher_own_appimage() {
    local desktop="$HOME/.local/share/applications/ai.storyteller.artcraft-launcher.desktop" path
    [[ -r "$desktop" ]] || return 1
    path=$(grep -m1 '^Exec=' "$desktop" | sed 's/^Exec=//; s/^"//; s/".*$//')
    [[ -n "$path" && -x "$path" ]] || return 1
    printf '%s\n' "$path"
}

check_artcraft() {
    _craft_check artcraft-launcher || _artcraft_launcher_own_appimage >/dev/null
}
install_artcraft()       { _craft_install craft-launcher artcraft-launcher "ArtCraft Launcher"; }
uninstall_artcraft()     { _craft_uninstall artcraft-launcher "ArtCraft Launcher"; }
update_artcraft()        { _craft_update craft-launcher artcraft-launcher "ArtCraft Launcher"; }

get_version_artcraft() {
    local v path
    v=$(_craft_version artcraft-launcher)
    if [[ -z "$v" ]] && path=$(_artcraft_launcher_own_appimage); then
        v=$(basename "$path" | grep -oP '\d+\.\d+\.\d+' | head -1)
    fi
    printf '%s\n' "$v"
}
