#!/bin/bash
# Termius SSH Client installer functions
# https://termius.com/
#
# Upstream publishes exactly two Linux artifacts: a .deb and a snap. There is no
# .rpm, no AppImage and no plain tarball (every other guessable name under
# https://www.termius.com/download/linux/ returns 404), which shapes the whole
# file:
#
#   - debian: the upstream .deb installs directly.
#   - arch:   termius-deb in the AUR (repacks the same .deb).
#   - fedora/rhel/suse: the .deb payload is unpacked natively into /opt.
#
# Why NOT Flatpak on the rpm families (this used to be a Flathub install):
#
#   A terminal client's whole job is to exec host binaries, and a sandbox is
#   structurally bad at that. Inside the Flatpak, /usr belongs to the
#   org.freedesktop.Platform runtime, not to the host — so /usr/bin/zsh does not
#   exist no matter what filesystem permissions are granted, and the host copy
#   is only reachable at /run/host/usr/bin/zsh (and only after
#   --filesystem=host). $SHELL is not passed through either, so Termius's
#   first-run detection falls back to /bin/sh and pins that into its
#   "Local Terminal Path" setting permanently. The result is a login shell the
#   user never chose, with none of their PATH or shell config.
#
#   Unpacking the .deb sidesteps all of it: the app runs unconfined, sees the
#   real /usr, and auto-detects $SHELL exactly as it does on Debian.
#
# The payload is a self-contained Electron bundle — verified with ldd against a
# current Fedora system, every linked library resolves from the runtime deps
# installed below. Only two things from the .deb are deliberately dropped:
# the AppArmor postinst (Debian-only; rpm families use SELinux) and
# /etc/cron.daily/termius-app, which is an apt-repo self-updater that would be
# dead weight at best on a system with no apt.

# --- Termius SSH Client ---

_TERMIUS_DEB_URL="https://www.termius.com/download/linux/Termius.deb"
_TERMIUS_PREFIX="/opt/Termius"
_TERMIUS_APP="$_TERMIUS_PREFIX/termius-app"
_TERMIUS_LAUNCHER="/usr/local/bin/termius-app"
_TERMIUS_DESKTOP="/usr/share/applications/termius-app.desktop"
# Kept inside the payload dir so uninstalling the tree takes the marker with it.
_TERMIUS_VERSION_FILE="$_TERMIUS_PREFIX/.linux_util-version"

check_termius() {
    [[ -x "$_TERMIUS_APP" ]] && return 0
    command -v termius &>/dev/null || \
        command -v termius-app &>/dev/null || \
        pkg_check_installed termius || \
        pkg_check_installed termius-deb || \
        pkg_check_installed termius-app || \
        (has_snap && snap list termius-app &>/dev/null) || \
        (flatpak_is_installed termius)
}

# Runtime libraries for the bundled Electron, translated from the .deb's own
# Depends: line (libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils
# libatspi2.0-0 libuuid1 libsecret-1-0), plus libgbm and libasound — both are
# linked by termius-app but missing from Depends upstream.
#
# Names are best-effort per family: a rename upstream should not abort the
# install, because a desktop system almost always has these already — the ldd
# check after staging is what actually decides whether the result is usable.
_termius_install_runtime_deps() {
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
    esac
    (( ${#deps[@]} == 0 )) && return 0

    local dep
    local -a missing=()
    for dep in "${deps[@]}"; do
        pkg_check_installed "$dep" || missing+=("$dep")
    done
    (( ${#missing[@]} == 0 )) && return 0

    # One transaction for the whole set — installing these one at a time means
    # a separate depsolve per package. If the batch fails, the likely cause is
    # a single name being wrong for this release, so retry individually rather
    # than let one bad name cost the user all the others.
    if ! pkg_install "${missing[@]}"; then
        for dep in "${missing[@]}"; do
            pkg_check_installed "$dep" && continue
            pkg_install "$dep" || \
                verbose "Termius: optional runtime dependency '${dep}' unavailable — continuing."
        done
    fi
    return 0
}

# refresh_desktop_caches only covers ~/.local/share, but the native install
# writes under /usr/share. Rebuilding mimeinfo.cache here is what actually
# activates the x-scheme-handler/termius registration carried in upstream's
# .desktop file.
_termius_refresh_system_caches() {
    command -v update-desktop-database &>/dev/null && \
        sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    command -v gtk-update-icon-cache &>/dev/null && \
        sudo gtk-update-icon-cache -qf /usr/share/icons/hicolor 2>/dev/null || true
    return 0
}

# Report any unresolved shared libraries in the staged binary. Non-fatal: it
# names the missing sonames instead of letting the app fail silently at launch.
_termius_check_libs() {
    command -v ldd &>/dev/null || return 0
    local missing
    missing=$(ldd "$_TERMIUS_APP" 2>/dev/null | awk '/not found/{print $1}' | sort -u | tr '\n' ' ')
    if [[ -n "${missing// /}" ]]; then
        warn "Termius is missing shared libraries: ${missing}"
        warn "Install the packages providing them, or Termius will not start."
    fi
}

# Extract one member of a .deb into a directory.
#
# tar cannot sniff compression when it is reading a pipe — it bails with
# "Archive is compressed. Use -J option" rather than auto-detecting, because it
# has no way to rewind. The member name is the only reliable signal, so
# dispatch the decompressor off the suffix. Upstream has changed this before
# (gz -> xz, and today control.tar.gz sits next to data.tar.xz in the same
# archive), hence handling the whole set rather than hardcoding one.
_termius_extract_member() {
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

# Download the upstream .deb and unpack its payload into /opt. No dpkg involved
# — the archive is opened with ar + tar, which is why binutils is ensured first.
_termius_install_native() {
    if ! command -v ar &>/dev/null; then
        info "Installing binutils (needed to unpack the Termius .deb)..."
        pkg_install binutils || { error "Could not install binutils."; return 1; }
        command -v ar &>/dev/null || { error "'ar' still unavailable after installing binutils."; return 1; }
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/termius-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    local deb="$tmpdir/Termius.deb"

    info "Downloading Termius..."
    wget -qO "$deb" "$_TERMIUS_DEB_URL" || { error "Failed to download Termius."; return 1; }
    verify_download "$deb" "deb" "Termius" || return 1

    # Member names are matched rather than hardcoded so a compression change
    # upstream only alters which decompressor _termius_extract_member picks.
    local data_member control_member
    data_member=$(ar t "$deb" 2>/dev/null | grep '^data\.tar' | head -1)
    control_member=$(ar t "$deb" 2>/dev/null | grep '^control\.tar' | head -1)
    if [[ -z "$data_member" ]]; then
        error "Termius .deb has no data member — the download is not a Debian package."
        return 1
    fi

    mkdir -p "$tmpdir/payload" "$tmpdir/control"
    if ! _termius_extract_member "$deb" "$data_member" "$tmpdir/payload"; then
        error "Failed to unpack the Termius .deb payload."
        return 1
    fi
    if [[ ! -x "$tmpdir/payload/opt/Termius/termius-app" ]]; then
        error "Unpacked Termius payload is missing opt/Termius/termius-app."
        return 1
    fi

    # The Electron binary answers --version with its bundled Node version, so
    # the package metadata is the only real source for the app version.
    local version=""
    if [[ -n "$control_member" ]] && \
       _termius_extract_member "$deb" "$control_member" "$tmpdir/control"; then
        version=$(awk '/^Version:/{print $2; exit}' "$tmpdir/control/control" 2>/dev/null)
    fi

    _termius_install_runtime_deps

    # Swap in only after unpacking succeeded, so a failed download cannot leave
    # a half-removed install behind.
    info "Installing Termius to ${_TERMIUS_PREFIX}..."
    sudo rm -rf "$_TERMIUS_PREFIX"
    sudo mkdir -p /opt
    sudo cp -a "$tmpdir/payload/opt/Termius" /opt/ || {
        error "Failed to install Termius to ${_TERMIUS_PREFIX}."
        return 1
    }
    sudo chown -R root:root "$_TERMIUS_PREFIX"

    # cp -a implies --preserve=all, which includes the SELinux context, so the
    # tree arrives in /opt still labelled with the staging directory's tmp type.
    # Relabel it to what the /opt policy says it should be; best-effort, since
    # non-SELinux hosts have no restorecon at all.
    command -v restorecon &>/dev/null && \
        sudo restorecon -RF "$_TERMIUS_PREFIX" 2>/dev/null || true

    # Chromium's SUID sandbox helper. It ships 0755 in the .deb and upstream's
    # postinst never touches it — that maintainer script only renders an
    # AppArmor profile — so on Debian the sandbox rides entirely on
    # unprivileged user namespaces being enabled. setuid-root is the other
    # configuration Chromium documents, and it also works where userns are
    # restricted; without one of the two Chromium refuses to start rather than
    # dropping the sandbox.
    [[ -f "$_TERMIUS_PREFIX/chrome-sandbox" ]] && sudo chmod 4755 "$_TERMIUS_PREFIX/chrome-sandbox"

    sudo ln -sf "$_TERMIUS_APP" "$_TERMIUS_LAUNCHER"

    # Upstream's own .desktop already points Exec at /opt/Termius/termius-app
    # and registers the x-scheme-handler/termius URL handler, so it is used
    # verbatim rather than regenerated.
    if [[ -f "$tmpdir/payload/usr/share/applications/termius-app.desktop" ]]; then
        sudo install -Dm644 "$tmpdir/payload/usr/share/applications/termius-app.desktop" \
            "$_TERMIUS_DESKTOP"
    fi

    local icon rel
    for icon in "$tmpdir"/payload/usr/share/icons/hicolor/*/apps/termius-app.png; do
        [[ -f "$icon" ]] || continue
        rel="${icon#"$tmpdir"/payload/usr/share/icons/}"
        sudo install -Dm644 "$icon" "/usr/share/icons/$rel"
    done

    # Written unconditionally — even with no parsed version — because uninstall
    # keys off this file's existence to tell a native install apart from a
    # distro-packaged one. Debian's .deb and Arch's termius-deb unpack to the
    # same /opt/Termius, so the directory alone proves nothing.
    if [[ -n "$version" ]]; then
        printf '%s\n' "$version" | sudo tee "$_TERMIUS_VERSION_FILE" >/dev/null
    else
        sudo touch "$_TERMIUS_VERSION_FILE"
    fi

    _termius_refresh_system_caches
    refresh_desktop_caches
    _termius_check_libs

    info "Termius installed natively — it will pick up \$SHELL (${SHELL:-unset}) on first run."
}

# Warn when a sandboxed copy is left over from the old Flathub/snap path: it
# keeps its own settings tree, so the user can end up staring at the stale
# /bin/sh terminal in the wrong copy of the app.
_termius_warn_sandboxed_copy() {
    if flatpak_is_installed termius; then
        warn "A Flatpak copy of Termius is also installed and still uses /bin/sh for its local terminal."
        warn "Remove it with: flatpak uninstall -y com.termius.Termius"
    fi
    if has_snap && snap list termius-app &>/dev/null; then
        warn "A snap copy of Termius is also installed."
        warn "Remove it with: sudo snap remove termius-app"
    fi
}

# Fallback path only (unknown distro family). Grant the sandbox access to the
# host filesystem so the host shell is at least reachable, and say where it is
# — /usr inside the sandbox belongs to the runtime, so the host path is the
# only one that works in Termius's "Local Terminal Path" field.
_termius_flatpak_shell_hint() {
    flatpak override --user --filesystem=host com.termius.Termius 2>/dev/null || \
        sudo flatpak override --filesystem=host com.termius.Termius 2>/dev/null || true
    warn "Termius is sandboxed here, so it cannot see the host /usr."
    warn "In Settings -> Terminal, set 'Local Terminal Path' to:"
    warn "    /run/host${SHELL:-/bin/bash}"
    warn "Host binaries are not on PATH inside the sandbox; add this to your shell rc if needed:"
    warn "    [[ -d /run/host/usr/bin ]] && export PATH=\"/run/host/usr/bin:\$PATH\""
}

install_termius() {
    info "Installing Termius SSH Client..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmp_deb
            tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            wget -q "$_TERMIUS_DEB_URL" -O "$tmp_deb"
            verify_download "$tmp_deb" "deb" "Termius" || return 1
            sudo apt install -y "$tmp_deb"
            rm -f "$tmp_deb"
            ;;
        fedora|rhel|suse)
            _termius_install_native || return 1
            _termius_warn_sandboxed_copy
            ;;
        arch)
            aur_ensure termius-deb
            ;;
        *)
            if has_snap; then
                sudo snap install termius-app
            elif ensure_flatpak; then
                sudo flatpak install -y flathub com.termius.Termius
                _termius_flatpak_shell_hint
            else
                error "snap or flatpak is required to install Termius on ${DISTRO_NAME}."
                return 1
            fi
            ;;
    esac
}

uninstall_termius() {
    info "Uninstalling Termius SSH Client..."
    # Tracked explicitly and returned at the end: the trailing config cleanup
    # below always succeeds, so without this the caller would read a removal
    # failure as success.
    local rc=0
    # Gate on the marker, never on /opt/Termius alone: the Debian .deb and the
    # Arch termius-deb package own that same directory, and tearing it out from
    # under them would leave dpkg/pacman holding a registered but gutted
    # package (and delete package-owned icons).
    if [[ -f "$_TERMIUS_VERSION_FILE" ]]; then
        sudo rm -rf "$_TERMIUS_PREFIX" || rc=1
        sudo rm -f "$_TERMIUS_LAUNCHER" "$_TERMIUS_DESKTOP" || rc=1
        sudo rm -f /usr/share/icons/hicolor/*/apps/termius-app.png || rc=1
        _termius_refresh_system_caches
        refresh_desktop_caches
    elif pkg_check_installed termius-deb; then
        pkg_remove termius-deb || rc=1
    elif pkg_check_installed termius; then
        pkg_remove termius || rc=1
    elif pkg_check_installed termius-app; then
        pkg_remove termius-app || rc=1
    elif has_snap && snap list termius-app &>/dev/null; then
        sudo snap remove termius-app || rc=1
    elif flatpak_is_installed termius; then
        # install_termius installs system-wide via sudo, and a system-scope
        # Flatpak cannot be removed by an unprivileged user — it fails with
        # "Flatpak system operation Uninstall not allowed for user". Try user
        # scope first for copies installed that way, then fall back to system.
        # --delete-data drops ~/.var/app/com.termius.Termius, matching the
        # config cleanup this function already does for native installs.
        flatpak uninstall -y --user --delete-data com.termius.Termius 2>/dev/null || \
            sudo flatpak uninstall -y --system --delete-data com.termius.Termius || rc=1
    else
        echo "Termius installation not found."
    fi
    rm -rf ~/.config/Termius
    rm -rf ~/.termius
    return $rc
}

update_termius() {
    info "Updating Termius SSH Client..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmp_deb
            tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            wget -q "$_TERMIUS_DEB_URL" -O "$tmp_deb"
            verify_download "$tmp_deb" "deb" "Termius" || return 1
            sudo apt install -y "$tmp_deb"
            rm -f "$tmp_deb"
            ;;
        fedora|rhel|suse)
            # The download URL carries no version, so there is nothing to
            # compare against without fetching the package itself — just
            # reinstall over the top.
            if [[ -f "$_TERMIUS_VERSION_FILE" ]]; then
                _termius_install_native || return 1
            else
                install_termius
            fi
            ;;
        arch)
            aur_ensure termius-deb
            ;;
        *)
            if has_snap && snap list termius-app &>/dev/null; then
                sudo snap refresh termius-app
            elif flatpak_is_installed termius; then
                # Same scope split as uninstall — a system-wide Flatpak cannot
                # be updated by an unprivileged user.
                flatpak update -y --user com.termius.Termius 2>/dev/null || \
                    sudo flatpak update -y --system com.termius.Termius
            else
                error "Termius installation not found or no supported update method."
                return 1
            fi
            ;;
    esac
}

get_version_termius() {
    # Do NOT call termius-app --version — the Electron binary reports the
    # version of its bundled Node runtime, not the Termius release.
    # -s, not -r: the marker is created even when the version could not be
    # parsed, so an empty one must fall through to the packaged-install checks.
    if [[ -s "$_TERMIUS_VERSION_FILE" && -r "$_TERMIUS_VERSION_FILE" ]]; then
        sed 's/^[0-9]*://; s/-.*//' "$_TERMIUS_VERSION_FILE"
    elif pkg_check_installed termius-deb; then
        pkg_get_version termius-deb | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed termius; then
        pkg_get_version termius | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed termius-app; then
        pkg_get_version termius-app | sed 's/^[0-9]*://; s/-.*//'
    elif _ver_from_snap termius-app; then
        return
    elif flatpak_is_installed termius; then
        _ver_from_flatpak termius
    else
        echo ""
    fi
}
