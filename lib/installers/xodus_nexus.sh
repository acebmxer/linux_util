#!/bin/bash
# Xodus Nexus installer functions
# https://github.com/domsvoboda/xodus-nexus
#
# Upstream publishes the launcher as an x86_64 AppImage only (no .deb, .rpm,
# Flatpak or distro package), so every family gets the same per-user install,
# at the same paths upstream's own scripts/install.sh uses:
#
#   ~/.local/opt/xodus-nexus/Xodus-Nexus.AppImage   the app
#   ~/.local/bin/xodus-nexus                        symlink to it
#   ~/.local/share/applications/xodus-nexus.desktop menu entry
#
# Sharing those paths means a copy installed with upstream's script is detected
# and updated in place instead of being duplicated, and the launcher's own
# in-app updater (Settings) keeps working: it replaces the AppImage it was
# started from, and refuses unless that file is owned by the user and writable
# only by them, which is what a per-user 0755 install gives it.
#
# Because the in-app updater can swap the AppImage at any time, the installed
# version is read from the AppImage itself (the X-AppImage-Version key of its
# embedded menu entry), cached against the file's size and mtime, rather than
# from a stamp written at install time that would go stale.
#
# The Nexus backend and runtime, the Microsoft sign-in and the games are all
# installed from inside the app, not here. Uninstalling removes the launcher
# only; its settings, sign-in, backend, runtime and installed games are left.

# --- Xodus Nexus ---

_XN_REPO="domsvoboda/xodus-nexus"
_XN_RELEASES_API="https://api.github.com/repos/${_XN_REPO}/releases?per_page=30"
_XN_DIR="$HOME/.local/opt/xodus-nexus"
_XN_APPIMAGE="$_XN_DIR/Xodus-Nexus.AppImage"
_XN_BIN="$HOME/.local/bin/xodus-nexus"
_XN_DESKTOP="$HOME/.local/share/applications/xodus-nexus.desktop"
_XN_ICON="$HOME/.local/share/icons/hicolor/512x512/apps/xodus-nexus.png"
_XN_VERSION_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/linux_util/xodus-nexus.version"

check_xodus_nexus() {
    [[ -x "$_XN_APPIMAGE" ]]
}

# Newest stable launcher release, as a bare version ("0.3.9"). The repository
# also publishes backend-* and runtime-* releases, and GitHub's "latest" can
# point at one of those, so this reads the release list and keeps only vX.Y.Z
# tags that are not pre-releases -- the same rule as the launcher's own updater.
# One API request, no download.
_xn_latest_version() {
    curl -fsSL --max-time 15 "$_XN_RELEASES_API" 2>/dev/null | _xn_pick_latest
}

# Reads a GitHub release-list JSON on stdin and prints the newest stable vX.Y.Z
# version. In each release object "tag_name" comes before "prerelease", and
# release assets carry neither key, so the two values pair up in order.
_xn_pick_latest() {
    grep -oP '"(tag_name|prerelease)"\s*:\s*\K("[^"]*"|true|false)' \
        | paste - - \
        | awk -F'\t' '$1 ~ /^"v[0-9]+\.[0-9]+\.[0-9]+"$/ && $2 == "false" { gsub(/"/, "", $1); sub(/^v/, "", $1); print $1 }' \
        | sort -V | tail -1
}

# Version of the AppImage at $1, from its embedded menu entry. Extracting one
# small file needs no FUSE and takes milliseconds.
_xn_appimage_version() {
    local appimage="$1" tmpdir v
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/xodus-nexus-ver-XXXXXX") || return 1
    v=$(cd "$tmpdir" && "$appimage" --appimage-extract '*.desktop' >/dev/null 2>&1 \
        && grep -m1 -h '^X-AppImage-Version=' squashfs-root/*.desktop 2>/dev/null | cut -d= -f2-)
    rm -rf "$tmpdir"
    printf '%s\n' "$v" | tr -d '[:space:]'
}

get_version_xodus_nexus() {
    [[ -x "$_XN_APPIMAGE" ]] || { echo ""; return 0; }
    local key cached_key cached_v v
    key=$(stat -c '%s:%Y' "$_XN_APPIMAGE" 2>/dev/null)
    if [[ -n "$key" && -r "$_XN_VERSION_CACHE" ]]; then
        read -r cached_key cached_v < "$_XN_VERSION_CACHE"
        if [[ "$cached_key" == "$key" && -n "$cached_v" ]]; then
            printf '%s\n' "$cached_v"
            return 0
        fi
    fi
    v=$(_xn_appimage_version "$_XN_APPIMAGE")
    if [[ -n "$v" && -n "$key" ]]; then
        mkdir -p "$(dirname "$_XN_VERSION_CACHE")" 2>/dev/null && \
            printf '%s %s\n' "$key" "$v" > "$_XN_VERSION_CACHE" 2>/dev/null
    fi
    printf '%s\n' "$v"
}

# Debian 13 and Ubuntu 24.04+ renamed several libraries for the 64-bit time_t
# transition (libasound2 -> libasound2t64). apt picks the new name by itself
# for some of them but not for libasound2, which has two providers on Ubuntu.
_xn_debian_name() {
    if apt-cache show "${1}t64" &>/dev/null; then echo "${1}t64"; else echo "$1"; fi
}

# Runtime libraries for the Electron inside the AppImage: an AppImage is not a
# package, so nothing else pulls them in. Most are present on any desktop
# install; this matters on minimal ones. Taken from the libraries the bundled
# binary links (ldd), named per family the same way as NVIDIA PAIR's list.
_xn_install_runtime_deps() {
    local -a deps=()
    case "$DISTRO_FAMILY" in
        debian)
            deps=("$(_xn_debian_name libgtk-3-0)" libnss3 libxtst6 libxss1
                  "$(_xn_debian_name libasound2)" libgbm1 libsecret-1-0 xdg-utils)
            ;;
        fedora|rhel)
            deps=(gtk3 nss libXScrnSaver libXtst xdg-utils libsecret mesa-libgbm alsa-lib)
            ;;
        suse)
            deps=(gtk3 mozilla-nss libXss1 libXtst6 xdg-utils libsecret-1-0 libgbm1 libasound2)
            ;;
        arch)
            deps=(gtk3 nss libxss libxtst xdg-utils libsecret mesa alsa-lib)
            ;;
    esac
    (( ${#deps[@]} == 0 )) && return 0

    local dep
    local -a missing=()
    for dep in "${deps[@]}"; do
        pkg_check_installed "$dep" || missing+=("$dep")
    done
    (( ${#missing[@]} == 0 )) && return 0

    # One transaction; if it fails a single wrong name is the likely cause, so
    # retry individually rather than lose the rest.
    if ! pkg_install "${missing[@]}"; then
        for dep in "${missing[@]}"; do
            pkg_check_installed "$dep" && continue
            pkg_install "$dep" || \
                verbose "Xodus Nexus: runtime dependency '${dep}' unavailable; continuing."
        done
    fi
    return 0
}

# Download release $1 and check it against the SHA-512 file upstream publishes
# beside every launcher AppImage (the same check the in-app updater makes). The
# verified file is left in $_XN_FILE, next to the install path so the final move
# is a rename on the same filesystem.
_xn_download() {
    local version="$1" name base sums expected tmp
    _XN_FILE=""
    name="Xodus-Nexus-${version}-x86_64.AppImage"
    base="https://github.com/${_XN_REPO}/releases/download/v${version}"

    sums=$(curl -fsSL --max-time 30 "${base}/${name}.sha512sum" 2>/dev/null) || {
        error "Could not download the Xodus Nexus ${version} checksum file."
        return 1
    }
    expected=$(printf '%s\n' "$sums" | awk -v n="$name" '$2 == n && $1 ~ /^[0-9a-fA-F]{128}$/ { print tolower($1); exit }')
    if [[ -z "$expected" ]]; then
        error "The Xodus Nexus ${version} checksum file does not list ${name}."
        return 1
    fi

    mkdir -p "$_XN_DIR" || return 1
    tmp="${_XN_APPIMAGE}.linux_util-part"
    CLEANUP_FILES+=("$tmp")
    info "Downloading Xodus Nexus ${version} (about 130 MB)..."
    # wget when present (ensure_tools installs it), else curl with no overall
    # time limit -- download_file's curl branch caps the whole transfer at 30s,
    # too short for 130 MB. Minimal RHEL images ship curl-minimal, which
    # conflicts with ensure_tools' "curl" and so leaves wget uninstalled.
    local fetched=0
    if command -v wget &>/dev/null; then
        wget -q --timeout=30 -O "$tmp" "${base}/${name}" && fetched=1
    else
        curl -fsSL --connect-timeout 30 --retry 3 -o "$tmp" "${base}/${name}" && fetched=1
    fi
    if (( ! fetched )); then
        rm -f "$tmp"
        rmdir "$_XN_DIR" 2>/dev/null
        error "Failed to download Xodus Nexus ${version}."
        return 1
    fi

    if [[ "$(sha512sum "$tmp" | awk '{print $1}')" != "$expected" ]]; then
        rm -f "$tmp"
        rmdir "$_XN_DIR" 2>/dev/null
        error "Xodus Nexus ${version} failed SHA-512 verification; nothing was installed."
        return 1
    fi
    verbose "Xodus Nexus ${version}: SHA-512 verified."
    _XN_FILE="$tmp"
}

# Menu entry and icon, taken from the AppImage itself: Exec is pointed at the
# installed copy and keeps upstream's arguments (--no-sandbox %U).
_xn_add_menu_entry() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/xodus-nexus-XXXXXX") || return 1
    CLEANUP_FILES+=("$tmpdir")
    if ! ( cd "$tmpdir" && "$_XN_APPIMAGE" --appimage-extract 'xodus-nexus.desktop' >/dev/null 2>&1 \
             && "$_XN_APPIMAGE" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/xodus-nexus.png' >/dev/null 2>&1 ) \
       || [[ ! -f "$tmpdir/squashfs-root/xodus-nexus.desktop" ]]; then
        warn "Could not read the menu entry from the Xodus Nexus AppImage; no menu item was added."
        return 0
    fi
    mkdir -p "$(dirname "$_XN_DESKTOP")" || return 1
    sed -e "s|^Exec=[^ ]*|Exec=\"${_XN_APPIMAGE}\"|" -e "/^TryExec=/d" \
        "$tmpdir/squashfs-root/xodus-nexus.desktop" > "$_XN_DESKTOP"
    if [[ -f "$tmpdir/squashfs-root/usr/share/icons/hicolor/512x512/apps/xodus-nexus.png" ]]; then
        install -Dm644 "$tmpdir/squashfs-root/usr/share/icons/hicolor/512x512/apps/xodus-nexus.png" "$_XN_ICON"
    fi
    # upstream's installer points Icon= at this file instead; the entry above no
    # longer uses it.
    rm -f "$_XN_DIR/icon.png"
}

# Name any shared libraries the bundled Electron cannot find. Non-fatal.
_xn_check_libs() {
    command -v ldd &>/dev/null || return 0
    local tmpdir missing
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/xodus-nexus-ldd-XXXXXX") || return 0
    CLEANUP_FILES+=("$tmpdir")
    ( cd "$tmpdir" && "$_XN_APPIMAGE" --appimage-extract 'xodus-nexus.bin' >/dev/null 2>&1 \
        && "$_XN_APPIMAGE" --appimage-extract '*.so' >/dev/null 2>&1 ) || return 0
    [[ -f "$tmpdir/squashfs-root/xodus-nexus.bin" ]] || return 0
    missing=$(LD_LIBRARY_PATH="$tmpdir/squashfs-root" ldd "$tmpdir/squashfs-root/xodus-nexus.bin" 2>/dev/null \
        | awk '/not found/{print $1}' | sort -u | tr '\n' ' ')
    rm -rf "$tmpdir"
    if [[ -n "${missing// /}" ]]; then
        warn "Xodus Nexus is missing shared libraries: ${missing}"
        warn "Install the packages providing them, or Xodus Nexus will not start."
    fi
}

install_xodus_nexus() {
    info "Installing Xodus Nexus..."
    if [[ "$(uname -m)" != "x86_64" ]]; then
        error "Xodus Nexus is published for x86_64 only (this machine is $(uname -m))."
        return 1
    fi
    ensure_tools

    local version
    version=$(_xn_latest_version)
    if [[ -z "$version" ]]; then
        error "Could not find the latest Xodus Nexus release on GitHub."
        return 1
    fi

    ensure_appimage_fuse
    _xn_install_runtime_deps
    _xn_download "$version" || return 1

    chmod 0755 "$_XN_FILE" || return 1
    mv -f "$_XN_FILE" "$_XN_APPIMAGE" || { error "Failed to install Xodus Nexus to ${_XN_APPIMAGE}."; return 1; }

    mkdir -p "$(dirname "$_XN_BIN")" || return 1
    ln -sfn "$_XN_APPIMAGE" "$_XN_BIN"
    _xn_add_menu_entry
    refresh_desktop_caches
    _xn_check_libs

    info "Xodus Nexus ${version} installed (command: xodus-nexus)."
    info "In Xodus Nexus, open Settings to install the Nexus backend and Nexus runtime, then sign in with your Microsoft account."
}

uninstall_xodus_nexus() {
    info "Uninstalling Xodus Nexus..."
    if [[ ! -e "$_XN_APPIMAGE" && ! -d "$_XN_DIR" ]]; then
        echo "Xodus Nexus installation not found."
        return 0
    fi
    # The whole directory: besides the AppImage it holds only what upstream's
    # installer and the in-app updater put there (icon, update backups, locks).
    rm -rf "$_XN_DIR" || return 1
    [[ -L "$_XN_BIN" && "$(readlink "$_XN_BIN")" == "$_XN_APPIMAGE" ]] && rm -f "$_XN_BIN"
    # Only the entry that points at this install; a copy kept elsewhere keeps its own.
    if grep -qF "$_XN_APPIMAGE" "$_XN_DESKTOP" 2>/dev/null || \
       grep -qF "$_XN_BIN" "$_XN_DESKTOP" 2>/dev/null; then
        rm -f "$_XN_DESKTOP"
    fi
    rm -f "$_XN_ICON" "$_XN_VERSION_CACHE"
    refresh_desktop_caches
    # Settings, sign-in, the Nexus backend and runtime, installed games and any
    # game shortcuts the app made are left alone.
}

update_xodus_nexus() {
    info "Updating Xodus Nexus..."
    local installed latest
    installed=$(get_version_xodus_nexus)
    latest=$(_xn_latest_version)
    # An unknown version on either side falls through and reinstalls rather than
    # risk skipping a real update.
    if [[ -n "$installed" && "$installed" == "$latest" ]]; then
        info "Xodus Nexus is already at the latest version (${installed})."
        return 0
    fi
    install_xodus_nexus
}
