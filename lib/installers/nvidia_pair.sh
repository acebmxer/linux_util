#!/bin/bash
# NVIDIA PAIR (Personal AI Router) installer functions
# https://www.nvidia.com/en-us/ai-on-rtx/personal-ai-router/
#
# Upstream (github.com/NVIDIA/Personal-AI-Router, Apache-2.0) publishes Linux
# builds as a .deb only (amd64 and arm64): no .rpm, no AppImage, no Flatpak and
# nothing in any distro repo. The same shape as Termius, so the same split:
#
#   - debian: the upstream .deb installs directly, so apt resolves its Depends.
#   - everyone else: the .deb payload is unpacked natively into /opt/PAIR.
#
# The payload is a self-contained Electron bundle plus Go helper binaries under
# resources/cli-bin. Of the .deb's postinst only these steps are reproduced:
# the `nvpair` terminal launcher, the setuid Chromium sandbox helper and the
# cache refreshes. The AppArmor profile is Debian/Ubuntu-only and is dropped.
#
# Unlike Termius, the version is not just the release tag: the .deb's control
# file says "1.0.0-85" (build suffix), so the suffix is stripped for display and
# compared against the tag.
#
# This is deliberately a second copy of the .deb-unpacking logic in termius.sh,
# which stays untouched because it is proven. Do not add a third.

# --- NVIDIA PAIR ---

_PAIR_GH_API="https://api.github.com/repos/NVIDIA/Personal-AI-Router/releases/latest"
_PAIR_PREFIX="/opt/PAIR"
_PAIR_APP="$_PAIR_PREFIX/nvpair"
_PAIR_LAUNCHER="/usr/bin/nvpair"
_PAIR_DESKTOP="/usr/share/applications/nvpair.desktop"
# Kept inside the payload dir so uninstalling the tree takes the marker with it.
_PAIR_VERSION_FILE="$_PAIR_PREFIX/.linux_util-version"

check_nvidia_pair() {
    [[ -x "$_PAIR_APP" ]] && return 0
    pkg_check_installed nvpair
}

# Latest release version upstream publishes, from the tag ("v1.0.0" -> "1.0.0").
# One API request, no download.
_pair_latest_version() {
    curl -fsSL --max-time 15 "$_PAIR_GH_API" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"v?\K[^"]+' | head -1
}

# Download URL of the newest release's .deb for this machine.
_pair_deb_url() {
    local arch
    case "$(uname -m)" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) error "Unsupported architecture for NVIDIA PAIR: $(uname -m)"; return 1 ;;
    esac
    # NVPAIR-Setup-<version>-<arch>.deb; the rolling NVPAIR-Setup-latest-* copies
    # are skipped so the file name matches what SHA/release notes refer to.
    curl -fsSL "$_PAIR_GH_API" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -m1 -E "/NVPAIR-Setup-[0-9][^/]*-${arch}\.deb\$"
}

# Download and verify the .deb into $_PAIR_FILE (not printed: verify_download
# writes to stdout, which would end up inside a command substitution).
_pair_download() {
    local url tmpfile
    _PAIR_FILE=""
    url=$(_pair_deb_url) || return 1
    if [[ -z "$url" ]]; then
        error "Could not find an NVIDIA PAIR .deb release asset."
        return 1
    fi
    tmpfile=$(mktemp /tmp/nvpair-XXXXXX.deb) || return 1
    CLEANUP_FILES+=("$tmpfile")
    info "Downloading NVIDIA PAIR (about 140 MB)..."
    wget -qO "$tmpfile" "$url" || { error "Failed to download NVIDIA PAIR."; return 1; }
    verify_download "$tmpfile" "deb" "NVIDIA PAIR" || return 1
    _PAIR_FILE="$tmpfile"
}

# Runtime libraries for the bundled Electron, translated from the .deb's own
# Depends: line (libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils
# libatspi2.0-0 libuuid1 libsecret-1-0), plus libgbm and libasound, which
# Electron links but upstream does not list. Best-effort per family; the ldd
# check after staging is what decides whether the result is usable.
_pair_install_runtime_deps() {
    local -a deps=()
    case "$DISTRO_FAMILY" in
        fedora|rhel)
            deps=(gtk3 libnotify nss libXScrnSaver libXtst xdg-utils
                  at-spi2-atk libuuid libsecret mesa-libgbm alsa-lib)
            ;;
        suse)
            deps=(gtk3 libnotify4 mozilla-nss libXss1 libXtst6 xdg-utils
                  at-spi2-atk-common libuuid1 libsecret-1-0 libgbm1 libasound2)
            ;;
        arch)
            deps=(gtk3 libnotify nss libxss libxtst xdg-utils
                  at-spi2-core util-linux-libs libsecret mesa alsa-lib)
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
                verbose "NVIDIA PAIR: optional runtime dependency '${dep}' unavailable; continuing."
        done
    fi
    return 0
}

_pair_refresh_system_caches() {
    command -v update-desktop-database &>/dev/null && \
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    command -v gtk-update-icon-cache &>/dev/null && \
        sudo gtk-update-icon-cache -qf /usr/share/icons/hicolor 2>/dev/null || true
    return 0
}

# Name any unresolved shared libraries in the staged binary. Non-fatal.
_pair_check_libs() {
    command -v ldd &>/dev/null || return 0
    local missing
    missing=$(ldd "$_PAIR_APP" 2>/dev/null | awk '/not found/{print $1}' | sort -u | tr '\n' ' ')
    if [[ -n "${missing// /}" ]]; then
        warn "NVIDIA PAIR is missing shared libraries: ${missing}"
        warn "Install the packages providing them, or NVIDIA PAIR will not start."
    fi
}

# Extract one member of a .deb into a directory. The decompressor is chosen from
# the member's suffix because tar cannot sniff compression on a pipe.
_pair_extract_member() {
    local deb="$1" member="$2" dest="$3"
    local -a decomp
    case "$member" in
        *.tar)     decomp=(cat) ;;
        *.tar.gz)  decomp=(gzip -dc) ;;
        *.tar.xz)  decomp=(xz -dc) ;;
        *.tar.bz2) decomp=(bzip2 -dc) ;;
        *.tar.zst) decomp=(zstd -dc) ;;
        *)
            error "Unsupported compression on .deb member '${member}'."
            return 1
            ;;
    esac
    if ! command -v "${decomp[0]}" &>/dev/null; then
        error "'${decomp[0]}' is required to unpack '${member}' but is not installed."
        return 1
    fi
    ar p "$deb" "$member" 2>/dev/null | "${decomp[@]}" 2>/dev/null | tar x -C "$dest" 2>/dev/null
}

# Unpack the upstream .deb into /opt/PAIR. No dpkg involved.
_pair_install_native() {
    # Already the published release? Nothing to fetch. An unknown version on
    # either side falls through and installs rather than risk skipping an update.
    if [[ -f "$_PAIR_VERSION_FILE" && "${PAIR_FORCE_REINSTALL:-0}" != "1" ]]; then
        local installed latest
        installed=$(get_version_nvidia_pair)
        latest=$(_pair_latest_version)
        if [[ -n "$installed" && "$installed" == "$latest" ]]; then
            info "NVIDIA PAIR is already at the latest version (${installed})."
            return 0
        fi
    fi

    if ! command -v ar &>/dev/null; then
        info "Installing binutils (needed to unpack the NVIDIA PAIR .deb)..."
        pkg_install binutils || { error "Could not install binutils."; return 1; }
        command -v ar &>/dev/null || { error "'ar' still unavailable after installing binutils."; return 1; }
    fi

    _pair_download || return 1
    local deb="$_PAIR_FILE" tmpdir
    tmpdir=$(mktemp -d /tmp/nvpair-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")

    local data_member control_member
    data_member=$(ar t "$deb" 2>/dev/null | grep '^data\.tar' | head -1)
    control_member=$(ar t "$deb" 2>/dev/null | grep '^control\.tar' | head -1)
    if [[ -z "$data_member" ]]; then
        error "NVIDIA PAIR .deb has no data member; the download is not a Debian package."
        return 1
    fi

    mkdir -p "$tmpdir/payload" "$tmpdir/control"
    if ! _pair_extract_member "$deb" "$data_member" "$tmpdir/payload"; then
        error "Failed to unpack the NVIDIA PAIR .deb payload."
        return 1
    fi
    if [[ ! -x "$tmpdir/payload/opt/PAIR/nvpair" ]]; then
        error "Unpacked NVIDIA PAIR payload is missing opt/PAIR/nvpair."
        return 1
    fi

    # The Electron binary reports its bundled Node version, so the control file
    # is the only real source for the app version ("1.0.0-85").
    local version=""
    if [[ -n "$control_member" ]] && \
       _pair_extract_member "$deb" "$control_member" "$tmpdir/control"; then
        version=$(awk '/^Version:/{print $2; exit}' "$tmpdir/control/control" 2>/dev/null)
    fi

    _pair_install_runtime_deps

    # Swap in only after unpacking succeeded, so a failed download cannot leave
    # a half-removed install behind.
    info "Installing NVIDIA PAIR to ${_PAIR_PREFIX}..."
    sudo rm -rf "$_PAIR_PREFIX"
    sudo mkdir -p /opt
    sudo cp -a "$tmpdir/payload/opt/PAIR" /opt/ || {
        error "Failed to install NVIDIA PAIR to ${_PAIR_PREFIX}."
        return 1
    }
    sudo chown -R root:root "$_PAIR_PREFIX"

    # cp -a keeps the SELinux context of the staging dir; relabel to what the
    # /opt policy says. Best-effort: non-SELinux hosts have no restorecon.
    command -v restorecon &>/dev/null && \
        sudo restorecon -RF "$_PAIR_PREFIX" 2>/dev/null || true

    # Same as upstream's postinst: setuid Chromium sandbox, which also works
    # where unprivileged user namespaces are restricted.
    [[ -f "$_PAIR_PREFIX/chrome-sandbox" ]] && sudo chmod 4755 "$_PAIR_PREFIX/chrome-sandbox"

    # Upstream's postinst writes a wrapper (not a symlink): `nvpair` in a
    # terminal is the bundled TUI, while the desktop entry runs the GUI directly.
    sudo rm -f "$_PAIR_LAUNCHER"
    printf '%s\n' '#!/bin/sh' '# NVIDIA PAIR terminal UI launcher.' \
        "exec '${_PAIR_PREFIX}/resources/cli-bin/nvpair-tui' \"\$@\"" \
        | sudo tee "$_PAIR_LAUNCHER" >/dev/null
    sudo chmod 0755 "$_PAIR_LAUNCHER"

    # Upstream's own .desktop already points Exec at /opt/PAIR/nvpair.
    if [[ -f "$tmpdir/payload/usr/share/applications/nvpair.desktop" ]]; then
        sudo install -Dm644 "$tmpdir/payload/usr/share/applications/nvpair.desktop" \
            "$_PAIR_DESKTOP"
    fi

    local icon rel
    for icon in "$tmpdir"/payload/usr/share/icons/hicolor/*/apps/nvpair.png; do
        [[ -f "$icon" ]] || continue
        rel="${icon#"$tmpdir"/payload/usr/share/icons/}"
        sudo install -Dm644 "$icon" "/usr/share/icons/$rel"
    done

    # Written even with no parsed version: uninstall keys off this file's
    # existence to tell a native install from the Debian package, which owns the
    # same /opt/PAIR directory.
    if [[ -n "$version" ]]; then
        printf '%s\n' "$version" | sudo tee "$_PAIR_VERSION_FILE" >/dev/null
    else
        sudo touch "$_PAIR_VERSION_FILE"
    fi

    _pair_refresh_system_caches
    refresh_desktop_caches
    _pair_check_libs
    return 0
}

install_nvidia_pair() {
    info "Installing NVIDIA PAIR..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _pair_download || return 1
            pkg_install "$_PAIR_FILE" || return 1
            ;;
        fedora|rhel|suse|arch)
            _pair_install_native || return 1
            ;;
        *)
            error "NVIDIA PAIR is not supported on ${DISTRO_NAME}."
            return 1
            ;;
    esac
    info "NVIDIA PAIR installed."
}

uninstall_nvidia_pair() {
    info "Uninstalling NVIDIA PAIR..."
    local rc=0
    # Gate on the marker, never on /opt/PAIR alone: the Debian package owns that
    # same directory and must be removed through the package manager.
    if [[ -f "$_PAIR_VERSION_FILE" ]]; then
        sudo rm -rf "$_PAIR_PREFIX" || rc=1
        sudo rm -f "$_PAIR_LAUNCHER" "$_PAIR_DESKTOP" || rc=1
        sudo rm -f /usr/share/icons/hicolor/*/apps/nvpair.png || rc=1
        _pair_refresh_system_caches
        refresh_desktop_caches
    elif pkg_check_installed nvpair; then
        pkg_remove nvpair || rc=1
    else
        echo "NVIDIA PAIR installation not found."
    fi
    # Settings, cluster identity and certificates under ~/.config are left alone,
    # as is every downloaded model (~/.ollama, ~/.llamacpp, ~/.lmstudio): the
    # same data upstream's package keeps on a plain remove.
    return $rc
}

update_nvidia_pair() {
    info "Updating NVIDIA PAIR..."
    case "$DISTRO_FAMILY" in
        debian)
            local installed latest
            installed=$(get_version_nvidia_pair)
            latest=$(_pair_latest_version)
            if [[ -n "$installed" && "$installed" == "$latest" ]]; then
                info "NVIDIA PAIR is already at the latest version (${installed})."
                return 0
            fi
            install_nvidia_pair
            ;;
        *)
            if [[ -f "$_PAIR_VERSION_FILE" ]]; then
                _pair_install_native
            else
                install_nvidia_pair
            fi
            ;;
    esac
}

get_version_nvidia_pair() {
    # Do NOT run nvpair --version: the Electron binary reports its bundled Node
    # version, and launching it opens the GUI.
    local v=""
    if [[ -s "$_PAIR_VERSION_FILE" ]]; then
        v=$(head -1 "$_PAIR_VERSION_FILE")
    elif pkg_check_installed nvpair; then
        v=$(pkg_get_version nvpair)
    fi
    # "1.0.0-85" -> "1.0.0": drop an epoch and the build suffix.
    printf '%s\n' "$v" | sed 's/^[0-9]*://; s/-.*//'
}
