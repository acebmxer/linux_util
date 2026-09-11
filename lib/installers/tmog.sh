#!/bin/bash
# TMOG (Task Manager OG) installer functions
# https://tmog.org/
#
# TMOG has no GitHub repo, no package repo, no AUR package, and publishes no
# checksums — the vendor site just serves fixed-name files
# (TaskManagerOG-<version>-x86_64.AppImage / .deb / -linux-x86_64.tar.gz)
# directly from tmog.org/downloads/, and the version number only appears
# embedded in those filenames on the download page itself, currently
# "BETA 3" / 0.1.3. There is no version API and no checksums file to check
# against, so this installer scrapes the current filenames off the homepage
# and relies on verify_download's non-empty/magic-byte check only.
#
# Debian family gets the real .deb (native package management). Everyone else
# (Fedora/RHEL, Arch, openSUSE) gets the AppImage, extracted rather than run
# in place — same approach as stacer.sh — since there is no .rpm, no repo
# package, and no AUR entry to fall back to.

# --- TMOG ---

_TMOG_HOME_URL="https://tmog.org/"
_TMOG_DIR="$HOME/.local/share/tmog"
_TMOG_APP="$_TMOG_DIR/squashfs-root"
_TMOG_VERSION_FILE="$_TMOG_DIR/version"
_TMOG_WRAPPER="$HOME/.local/bin/tmog"
_TMOG_DESKTOP="$HOME/.local/share/applications/tmog.desktop"

check_tmog() {
    [[ -x "$_TMOG_APP/AppRun" ]] && return 0
    # The .deb installs the binary as tmog-task-manager, not tmog.
    _have_cmd tmog-task-manager && return 0
    pkg_check_installed taskmanagerog
}

# Print the current download URL for asset type $1 (deb|AppImage) by scraping
# the vendor homepage — there is no release API to query.
_tmog_latest_url() {
    local ext="$1" path
    path=$(curl -fsSL "$_TMOG_HOME_URL" 2>/dev/null \
        | grep -oP "/downloads/TaskManagerOG-[0-9][^\"']*\.${ext}" \
        | head -1)
    [[ -z "$path" ]] && return 1
    printf 'https://tmog.org%s\n' "$path"
}

# Download the upstream AppImage, unpack it into ~/.local/share/tmog, and put
# a wrapper plus a menu entry in place. Needs no root and no FUSE.
_tmog_install_appimage() {
    local url
    url=$(_tmog_latest_url "AppImage")
    if [[ -z "$url" ]]; then
        error "Could not find the TMOG AppImage download URL on tmog.org."
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/tmog-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")
    local tmpfile="$tmpdir/tmog.AppImage"

    wget -qO "$tmpfile" "$url" || { error "Failed to download the TMOG AppImage."; return 1; }
    verify_download "$tmpfile" "AppImage" "TMOG" || return 1
    chmod +x "$tmpfile"

    # --appimage-extract always writes ./squashfs-root relative to the working
    # directory, so run it inside the temp dir rather than next to the install.
    if ! (cd "$tmpdir" && "$tmpfile" --appimage-extract >/dev/null 2>&1); then
        error "Failed to extract the TMOG AppImage."
        return 1
    fi
    if [[ ! -x "$tmpdir/squashfs-root/AppRun" ]]; then
        error "Extracted TMOG AppImage is missing its AppRun entry point."
        return 1
    fi

    # Swap the payload in only once extraction has succeeded, so a failed
    # update cannot leave a half-removed install behind.
    mkdir -p "$_TMOG_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
    rm -rf "$_TMOG_APP"
    mv "$tmpdir/squashfs-root" "$_TMOG_APP" || {
        error "Failed to install TMOG to ${_TMOG_APP}."
        return 1
    }

    basename "$url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > "$_TMOG_VERSION_FILE"

    cat > "$_TMOG_WRAPPER" <<EOF
#!/bin/bash
exec "$_TMOG_APP/AppRun" "\$@"
EOF
    chmod +x "$_TMOG_WRAPPER"

    # The upstream AppImage ships its icon at the root as tmog-task-manager.png
    # (no hicolor theme tree), so look there first.
    local icon
    icon=$(find "$_TMOG_APP" -maxdepth 1 \( -iname "*.png" -o -iname "*.svg" \) 2>/dev/null | head -1)

    cat > "$_TMOG_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=TMOG
Comment=Native Qt task manager with real-time system metrics
Exec=$_TMOG_WRAPPER
Icon=${icon:-utilities-system-monitor}
Terminal=false
Categories=System;Monitor;Utility;
EOF
    refresh_desktop_caches

    info "TMOG installed to ${_TMOG_DIR}. Launch it from your application menu or run 'tmog'."
}

install_tmog() {
    info "Installing TMOG..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url tmpfile
            url=$(_tmog_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find the TMOG .deb download URL on tmog.org."
                return 1
            fi
            tmpfile=$(mktemp /tmp/tmog-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download the TMOG .deb."; return 1; }
            verify_download "$tmpfile" "deb" "TMOG" || return 1
            pkg_install_local "$tmpfile" || { error "Failed to install the TMOG .deb."; return 1; }
            ;;
        fedora|rhel|suse|arch)
            # No .rpm, no repo package, no AUR entry — the AppImage is the
            # only option on these families.
            _tmog_install_appimage || return 1
            ;;
        *)
            warn "TMOG installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu (.deb), Fedora/RHEL/Arch/openSUSE (AppImage)."
            return 1
            ;;
    esac
    info "TMOG installed."
}

uninstall_tmog() {
    info "Uninstalling TMOG..."
    if [[ -d "$_TMOG_DIR" ]]; then
        rm -rf "$_TMOG_DIR"
        rm -f "$_TMOG_WRAPPER" "$_TMOG_DESKTOP"
        refresh_desktop_caches
    else
        case "$PKG_MGR" in
            apt) sudo apt-get purge --autoremove -y taskmanagerog 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.config/TMOG"
}

update_tmog() {
    info "Updating TMOG..."
    if [[ -d "$_TMOG_APP" ]]; then
        # Check the current filename before pulling the AppImage down again.
        local latest current
        latest=$(_tmog_latest_url "AppImage" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        current=$(cat "$_TMOG_VERSION_FILE" 2>/dev/null)
        if [[ -n "$latest" && "$latest" == "$current" ]]; then
            info "TMOG is already at the latest release (${current})."
            return 0
        fi
        _tmog_install_appimage
    else
        install_tmog
    fi
}

get_version_tmog() {
    _ver_from_pkg taskmanagerog || cat "$_TMOG_VERSION_FILE" 2>/dev/null || echo ""
}
