#!/bin/bash
# LM Studio installer functions
# https://lmstudio.ai/download?os=linux
#
# Upstream publishes an AppImage (x64 and arm64) and a .deb. The .deb covers
# only Debian-based systems, so every family gets the same per-user AppImage
# install:
#
#   ~/.local/opt/lm-studio/LM-Studio.AppImage                      the app
#   ~/.local/bin/lm-studio                                         symlink to it
#   ~/.local/share/applications/ai.elementlabs.lmstudio.desktop    menu entry
#
# The app can update itself, so the installed version is read from the
# AppImage (the X-AppImage-Version key of its embedded menu entry), cached
# against the file's size and mtime, rather than from a stamp written at
# install time that would go stale.
#
# Models, settings and the `lms` command live in ~/.lmstudio and are created
# by the app on first launch. Uninstalling removes the app only; ~/.lmstudio
# (often tens of gigabytes of models) is left.

# --- LM Studio ---

_LMS_DIR="$HOME/.local/opt/lm-studio"
_LMS_APPIMAGE="$_LMS_DIR/LM-Studio.AppImage"
_LMS_BIN="$HOME/.local/bin/lm-studio"
_LMS_DESKTOP="$HOME/.local/share/applications/ai.elementlabs.lmstudio.desktop"
_LMS_ICON="$HOME/.local/share/icons/hicolor/512x512/apps/lm-studio.png"
_LMS_VERSION_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/linux_util/lm-studio.version"

check_lm_studio() {
    [[ -x "$_LMS_APPIMAGE" ]]
}

# Upstream's architecture name for this machine; fails on anything else.
_lms_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             return 1 ;;
    esac
}

# Latest version as upstream names it in the download path ("0.4.28-2"). The
# "latest" download link redirects to the versioned AppImage, so the redirect
# target is read without downloading anything.
_lms_latest_version() {
    local arch
    arch=$(_lms_arch) || return 1
    curl -fsS --max-time 15 -o /dev/null -w '%{redirect_url}' \
        "https://lmstudio.ai/download/latest/linux/${arch}" 2>/dev/null | _lms_version_from_url
}

# Reads a download URL on stdin and prints the version in its path.
_lms_version_from_url() {
    grep -oP '/linux/[a-z0-9]+/\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+(?=/)' | head -1
}

# Version of the AppImage at $1 in the same "0.4.28-2" form (the embedded menu
# entry says "0.4.28+2"). Extracting one small file needs no FUSE.
_lms_appimage_version() {
    local appimage="$1" tmpdir v
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lm-studio-ver-XXXXXX") || return 1
    v=$(cd "$tmpdir" && "$appimage" --appimage-extract '*.desktop' >/dev/null 2>&1 \
        && grep -m1 -h '^X-AppImage-Version=' squashfs-root/*.desktop 2>/dev/null | cut -d= -f2-)
    rm -rf "$tmpdir"
    printf '%s\n' "$v" | tr -d '[:space:]' | tr '+' '-'
}

get_version_lm_studio() {
    [[ -x "$_LMS_APPIMAGE" ]] || { echo ""; return 0; }
    local key cached_key cached_v v
    key=$(stat -c '%s:%Y' "$_LMS_APPIMAGE" 2>/dev/null)
    if [[ -n "$key" && -r "$_LMS_VERSION_CACHE" ]]; then
        read -r cached_key cached_v < "$_LMS_VERSION_CACHE"
        if [[ "$cached_key" == "$key" && -n "$cached_v" ]]; then
            printf '%s\n' "$cached_v"
            return 0
        fi
    fi
    v=$(_lms_appimage_version "$_LMS_APPIMAGE")
    if [[ -n "$v" && -n "$key" ]]; then
        mkdir -p "$(dirname "$_LMS_VERSION_CACHE")" 2>/dev/null && \
            printf '%s %s\n' "$key" "$v" > "$_LMS_VERSION_CACHE" 2>/dev/null
    fi
    printf '%s\n' "$v"
}

# Download version $1 for architecture $2 and check it against the SHA-512
# file upstream publishes beside it. The verified file is left in $_LMS_FILE,
# next to the install path so the final move is a rename on one filesystem.
_lms_download() {
    local version="$1" arch="$2" name base sum expected tmp
    _LMS_FILE=""
    name="LM-Studio-${version}-${arch}.AppImage"
    base="https://installers.lmstudio.ai/linux/${arch}/${version}"

    sum=$(curl -fsSL --max-time 30 "${base}/${name}.sha512" 2>/dev/null) || {
        error "Could not download the LM Studio ${version} checksum file."
        return 1
    }
    expected=$(printf '%s\n' "$sum" | grep -oE '^[0-9a-fA-F]{128}' | head -1 | tr '[:upper:]' '[:lower:]')
    if [[ -z "$expected" ]]; then
        error "The LM Studio ${version} checksum file does not hold a SHA-512."
        return 1
    fi

    mkdir -p "$_LMS_DIR" || return 1
    tmp="${_LMS_APPIMAGE}.linux_util-part"
    CLEANUP_FILES+=("$tmp")
    info "Downloading LM Studio ${version} (about 1 GB)..."
    # wget when present (ensure_tools installs it), else curl with no overall
    # time limit -- download_file's curl branch caps the whole transfer at 30s.
    local fetched=0
    if command -v wget &>/dev/null; then
        wget -q --timeout=30 -O "$tmp" "${base}/${name}" && fetched=1
    else
        curl -fsSL --connect-timeout 30 --retry 3 -o "$tmp" "${base}/${name}" && fetched=1
    fi
    if (( ! fetched )); then
        rm -f "$tmp"
        rmdir "$_LMS_DIR" 2>/dev/null
        error "Failed to download LM Studio ${version}."
        return 1
    fi

    if [[ "$(sha512sum "$tmp" | awk '{print $1}')" != "$expected" ]]; then
        rm -f "$tmp"
        rmdir "$_LMS_DIR" 2>/dev/null
        error "LM Studio ${version} failed SHA-512 verification; nothing was installed."
        return 1
    fi
    verbose "LM Studio ${version}: SHA-512 verified."
    _LMS_FILE="$tmp"
}

# Menu entry and icon, taken from the AppImage itself: Exec is pointed at the
# installed copy. The AppImage's AppRun decides about --no-sandbox by itself.
_lms_add_menu_entry() {
    local tmpdir desktop_src="ai.elementlabs.lmstudio.desktop" icon_src="usr/share/icons/hicolor/512x512/apps/lm-studio.png"
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lm-studio-XXXXXX") || return 1
    CLEANUP_FILES+=("$tmpdir")
    if ! ( cd "$tmpdir" && "$_LMS_APPIMAGE" --appimage-extract "$desktop_src" >/dev/null 2>&1 \
             && "$_LMS_APPIMAGE" --appimage-extract "$icon_src" >/dev/null 2>&1 ) \
       || [[ ! -f "$tmpdir/squashfs-root/$desktop_src" ]]; then
        warn "Could not read the menu entry from the LM Studio AppImage; no menu item was added."
        return 0
    fi
    mkdir -p "$(dirname "$_LMS_DESKTOP")" || return 1
    sed -e "s|^Exec=[^ ]*|Exec=\"${_LMS_APPIMAGE}\"|" -e "/^TryExec=/d" \
        "$tmpdir/squashfs-root/$desktop_src" > "$_LMS_DESKTOP"
    if [[ -f "$tmpdir/squashfs-root/$icon_src" ]]; then
        install -Dm644 "$tmpdir/squashfs-root/$icon_src" "$_LMS_ICON"
    fi
    rm -rf "$tmpdir"
}

# Name any shared libraries the bundled Electron cannot find. Non-fatal.
_lms_check_libs() {
    command -v ldd &>/dev/null || return 0
    local tmpdir missing
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lm-studio-ldd-XXXXXX") || return 0
    CLEANUP_FILES+=("$tmpdir")
    ( cd "$tmpdir" && "$_LMS_APPIMAGE" --appimage-extract 'lm-studio' >/dev/null 2>&1 \
        && "$_LMS_APPIMAGE" --appimage-extract '*.so' >/dev/null 2>&1 ) || return 0
    [[ -f "$tmpdir/squashfs-root/lm-studio" ]] || return 0
    missing=$(LD_LIBRARY_PATH="$tmpdir/squashfs-root" ldd "$tmpdir/squashfs-root/lm-studio" 2>/dev/null \
        | awk '/not found/{print $1}' | sort -u | tr '\n' ' ')
    rm -rf "$tmpdir"
    if [[ -n "${missing// /}" ]]; then
        warn "LM Studio is missing shared libraries: ${missing}"
        warn "Install the packages providing them, or LM Studio will not start."
    fi
}

install_lm_studio() {
    info "Installing LM Studio..."
    local arch version
    if ! arch=$(_lms_arch); then
        error "LM Studio is published for x86_64 and aarch64 only (this machine is $(uname -m))."
        return 1
    fi
    ensure_tools

    version=$(_lms_latest_version)
    if [[ -z "$version" ]]; then
        error "Could not find the latest LM Studio version on lmstudio.ai."
        return 1
    fi

    ensure_appimage_fuse
    ensure_electron_runtime_deps "LM Studio"
    _lms_download "$version" "$arch" || return 1

    chmod 0755 "$_LMS_FILE" || return 1
    mv -f "$_LMS_FILE" "$_LMS_APPIMAGE" || { error "Failed to install LM Studio to ${_LMS_APPIMAGE}."; return 1; }

    mkdir -p "$(dirname "$_LMS_BIN")" || return 1
    ln -sfn "$_LMS_APPIMAGE" "$_LMS_BIN"
    _lms_add_menu_entry
    refresh_desktop_caches
    _lms_check_libs

    info "LM Studio ${version} installed (command: lm-studio)."
    info "Start LM Studio once from the application menu; it sets up the 'lms' command and ~/.lmstudio on first launch."
}

uninstall_lm_studio() {
    info "Uninstalling LM Studio..."
    if [[ ! -e "$_LMS_APPIMAGE" && ! -d "$_LMS_DIR" ]]; then
        echo "LM Studio installation not found."
        return 0
    fi
    rm -rf "$_LMS_DIR" || return 1
    [[ -L "$_LMS_BIN" && "$(readlink "$_LMS_BIN")" == "$_LMS_APPIMAGE" ]] && rm -f "$_LMS_BIN"
    # Only the entry that points at this install; a copy kept elsewhere keeps its own.
    if grep -qF "$_LMS_APPIMAGE" "$_LMS_DESKTOP" 2>/dev/null || \
       grep -qF "$_LMS_BIN" "$_LMS_DESKTOP" 2>/dev/null; then
        rm -f "$_LMS_DESKTOP"
    fi
    rm -f "$_LMS_ICON" "$_LMS_VERSION_CACHE"
    refresh_desktop_caches
    info "Your models and settings in ~/.lmstudio were kept."
}

update_lm_studio() {
    info "Updating LM Studio..."
    local installed latest
    installed=$(get_version_lm_studio)
    latest=$(_lms_latest_version)
    # An unknown version on either side falls through and reinstalls rather than
    # risk skipping a real update.
    if [[ -n "$installed" && "$installed" == "$latest" ]]; then
        info "LM Studio is already at the latest version (${installed})."
        return 0
    fi
    install_lm_studio
}
