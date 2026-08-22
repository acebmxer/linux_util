#!/bin/bash
# Stacer installer functions
# https://github.com/QuentiumYT/Stacer
#
# Tracks QuentiumYT/Stacer, not the original oguzhaninan/Stacer. The original
# is dormant -- last release v1.1.0 in 2019, last push February 2024 -- and
# every workaround this file used to carry existed only to cope with that 2019
# build. The fork is the same codebase carried forward (oguzhaninan is still its
# top contributor at 524 commits, QuentiumYT has 138 on top), is ported to Qt6,
# and releases regularly: ten releases between May 2025 and v1.7.0 in May 2026.
# Of the 100 forks of the original it is the only one with any activity -- the
# runner-up has two stars and was last pushed in 2017 -- and both AUR packages
# (stacer-bin and stacer, different maintainers) independently point at it.
#
# What the move to a maintained upstream bought back:
#
#   - fedora/rhel: the .rpm installs normally again. The 2019 rpm predated rpm
#     payload digests, so rpm >= 6 (Fedora 41+) rejected it with "does not
#     verify: no digest" and there was no bypass short of lowering
#     %_pkgverify_level system-wide. The current rpm verifies clean
#     ("Payload SHA256 digest: OK") and its Requires are Fedora-named
#     (qt6-qtbase, qt6-qtbase-gui, qt6-qtcharts, qt6-qtsvg), so dnf resolves
#     them from the distro repos. This replaces the AppImage workaround.
#   - debian: a current build instead of one from 2019.
#   - arch: the AppImage, extracted per-user. No AUR.
#
# openSUSE and Arch both get the AppImage. openSUSE because the rpm
# hard-requires the Fedora package names above, which do not exist there; Arch
# because it has no repo package and the AUR is disabled in this tool -- and
# stacer-bin was only ever a repack of the same .deb this release publishes,
# so the AppImage loses nothing.
#
# Why NOT Flatpak, which the original file also warned about:
#
#   Stacer is still on no Flathub remote. com.oguzhaninan.Stacer never was, and
#   the fork's fr.quentium.stacer is not either -- the appstream API 404s on all
#   of them and a Flathub search for "stacer" returns only unrelated monitors.
#   Do not "restore" a Flathub branch here; it fails on every retry.
#
#   The fork DOES publish a .flatpak bundle file per release, which is why this
#   note is worth keeping. It is deliberately unused. Installing it means
#   pulling the whole org.kde.Platform 6.10 runtime for a 1 MB app, and the
#   result is a crippled Stacer, because a sandbox is the wrong shape for a
#   system optimizer. Its manifest grants only:
#
#       shared=network;ipc;
#       filesystems=home;/var/log;xdg-config/autostart;/var/crash;/var/cache;
#
#   with no system bus policy at all. Startup entries, log viewing and user
#   cache cleanup would work; the package uninstaller cannot run the host
#   package manager, services management has no systemd to talk to, and the
#   process list reports the sandbox's own PID namespace rather than the host's
#   -- which is Stacer's headline feature. The native packages below run
#   unconfined and see the real system.
#
# The AppImage is EXTRACTED rather than run in place, which needs no root and
# sidesteps its runtime's libfuse.so.2 dependency. Note the Qt6 build still
# bundles only libqxcb.so -- there is no Wayland platform plugin in it -- so the
# wrapper keeps pinning QT_QPA_PLATFORM=xcb. Under a session exporting
# QT_QPA_PLATFORM=wayland, Qt would otherwise abort with "could not find or load
# the Qt platform plugin".

# --- Stacer ---

_STACER_REPO_API="https://api.github.com/repos/QuentiumYT/Stacer/releases/latest"
_STACER_DIR="$HOME/.local/share/stacer"
_STACER_APP="$_STACER_DIR/squashfs-root"
_STACER_VERSION_FILE="$_STACER_DIR/version"
_STACER_WRAPPER="$HOME/.local/bin/stacer"
_STACER_DESKTOP="$HOME/.local/share/applications/stacer.desktop"

check_stacer() {
    [[ -x "$_STACER_APP/AppRun" ]] && return 0
    _check_standard stacer stacer "" stacer-bin
}

# Print the download URL for a release asset of type $1 (deb|rpm|AppImage).
#
# Asset names differ in shape per type -- stacer_1.7.0-1_amd64.deb,
# stacer-1.7.0.x86_64.rpm, Stacer-1.7.0-x86_64.AppImage -- so the machine
# architecture has to be matched per type rather than by excluding "arm".
_stacer_latest_url() {
    local ext="$1" pattern machine
    machine=$(uname -m)

    case "${ext}:${machine}" in
        deb:x86_64)            pattern='_amd64\.deb$' ;;
        deb:aarch64|deb:arm64) pattern='_arm64\.deb$' ;;
        rpm:x86_64)            pattern='\.x86_64\.rpm$' ;;
        rpm:aarch64|rpm:arm64) pattern='\.aarch64\.rpm$' ;;
        AppImage:x86_64)            pattern='x86_64\.AppImage$' ;;
        AppImage:aarch64|AppImage:arm64) pattern='aarch64\.AppImage$' ;;
        *) return 1 ;;
    esac

    curl -fsSL "$_STACER_REPO_API" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -m1 -E "$pattern"
}

# Qt6 runtime for the .deb, which declares no Depends at all -- apt therefore
# pulls nothing, and the binary needs libQt6Core/Gui/Widgets/Network/Charts.
# Names are best-effort: Debian's time_t transition renamed several of these
# with a t64 suffix, so each is tried individually and a miss is not fatal.
_stacer_install_deb_deps() {
    local dep
    for dep in libqt6core6t64 libqt6core6 libqt6gui6t64 libqt6gui6 \
               libqt6widgets6t64 libqt6widgets6 libqt6network6t64 libqt6network6 \
               libqt6charts6 libqt6svg6; do
        pkg_check_installed "$dep" && continue
        sudo apt install -y "$dep" >/dev/null 2>&1 || true
    done
    return 0
}

# Download the upstream AppImage, unpack it into ~/.local/share/stacer, and put
# a wrapper plus a menu entry in place. Needs no root and no FUSE.
_stacer_install_appimage() {
    local url
    url=$(_stacer_latest_url "AppImage")
    if [[ -z "$url" ]]; then
        error "Could not find Stacer AppImage release URL."
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/stacer-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")
    local tmpfile="$tmpdir/stacer.AppImage"

    wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer AppImage."; return 1; }
    verify_download "$tmpfile" "AppImage" "Stacer" || return 1
    github_verify_checksum "$_STACER_REPO_API" "$(basename "$url")" "$tmpfile" || return 1
    chmod +x "$tmpfile"

    # --appimage-extract always writes ./squashfs-root relative to the working
    # directory, so run it inside the temp dir rather than next to the install.
    if ! (cd "$tmpdir" && "$tmpfile" --appimage-extract >/dev/null 2>&1); then
        error "Failed to extract the Stacer AppImage."
        return 1
    fi
    if [[ ! -x "$tmpdir/squashfs-root/AppRun" ]]; then
        error "Extracted Stacer AppImage is missing its AppRun entry point."
        return 1
    fi

    # Swap the payload in only once extraction has succeeded, so a failed
    # update cannot leave a half-removed install behind.
    mkdir -p "$_STACER_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
    rm -rf "$_STACER_APP"
    mv "$tmpdir/squashfs-root" "$_STACER_APP" || {
        error "Failed to install Stacer to ${_STACER_APP}."
        return 1
    }

    # Stacer's binary never reports a usable version (it opens a GUI window
    # instead), so record the version from the asset name for get_version.
    basename "$url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > "$_STACER_VERSION_FILE"

    cat > "$_STACER_WRAPPER" <<EOF
#!/bin/bash
# Only the xcb platform plugin is bundled in this AppImage — see stacer.sh.
export QT_QPA_PLATFORM=xcb
exec "$_STACER_APP/AppRun" "\$@"
EOF
    chmod +x "$_STACER_WRAPPER"

    # Icon by absolute path: nothing installs the extracted tree's icons into a
    # system hicolor directory. The fork moved them -- there is no longer a
    # stacer.png at the root of the AppImage, only icons/hicolor/<size>/apps/.
    cat > "$_STACER_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Stacer
Comment=Linux System Optimizer and Monitoring
Exec=$_STACER_WRAPPER
Icon=$_STACER_APP/icons/hicolor/256x256/apps/stacer.png
Terminal=false
Categories=System;Monitor;Utility;
EOF
    refresh_desktop_caches

    info "Stacer installed to ${_STACER_DIR}. Launch it from your application menu or run 'stacer'."
}

install_stacer() {
    info "Installing Stacer..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_stacer_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find Stacer .deb release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/stacer-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Stacer" || return 1
            github_verify_checksum "$_STACER_REPO_API" "$(basename "$url")" "$tmpfile" || return 1
            _stacer_install_deb_deps
            sudo apt install -y "$tmpfile" || { error "Failed to install Stacer .deb."; return 1; }
            ;;
        fedora|rhel)
            local url tmpfile
            url=$(_stacer_latest_url "rpm")
            if [[ -z "$url" ]]; then
                error "Could not find Stacer .rpm release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/stacer-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Stacer .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Stacer" || return 1
            github_verify_checksum "$_STACER_REPO_API" "$(basename "$url")" "$tmpfile" || return 1
            # dnf resolves qt6-qtbase/-gui/-qtcharts/-qtsvg from the distro repos.
            if ! pkg_install_local "$tmpfile"; then
                warn "Stacer .rpm install failed; falling back to the AppImage."
                _stacer_install_appimage || return 1
            fi
            ;;
        suse)
            _stacer_install_appimage || return 1
            ;;
        arch)
            # No AUR: stacer-bin repacks the very .deb this release publishes,
            # and the AppImage carries the same build with its Qt6 bundled, so
            # nothing is gained by building a package for it. A repo package is
            # still preferred if a derivative ever ships one.
            if arch_repo_has stacer && pkg_install stacer; then
                :
            else
                _stacer_install_appimage || return 1
            fi
            ;;
    esac
    info "Stacer installed."
}

uninstall_stacer() {
    info "Uninstalling Stacer..."
    if [[ -d "$_STACER_DIR" ]]; then
        rm -rf "$_STACER_DIR"
        rm -f "$_STACER_WRAPPER" "$_STACER_DESKTOP"
        refresh_desktop_caches
    else
        case "$DISTRO_FAMILY" in
            debian)     sudo apt purge --autoremove -y stacer ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y stacer 2>/dev/null || true ;;
            # stacer-bin is the old AUR name, tried only so an install
            # predating the AppImage path is still removed.
            arch)       sudo pacman -Rs --noconfirm stacer-bin 2>/dev/null || sudo pacman -Rs --noconfirm stacer 2>/dev/null || true ;;
            suse)       sudo zypper remove -y stacer 2>/dev/null || true ;;
        esac
    fi
    rm -rf "$HOME/.config/stacer"
}

update_stacer() {
    info "Updating Stacer..."

    # An AppImage tree on an rpm family is a leftover from when the 2019 .rpm
    # could not be installed at all. That is fixed, so migrate rather than keep
    # refreshing the extracted copy: tear the tree out and install the package.
    if [[ -d "$_STACER_APP" && ( "$DISTRO_FAMILY" == "fedora" || "$DISTRO_FAMILY" == "rhel" ) ]]; then
        info "Replacing the extracted AppImage with the upstream .rpm..."
        rm -rf "$_STACER_DIR"
        rm -f "$_STACER_WRAPPER" "$_STACER_DESKTOP"
        refresh_desktop_caches
        install_stacer
        return $?
    fi

    if [[ -d "$_STACER_APP" ]]; then
        # Check the tag before pulling ~38 MB down again on every update run.
        local latest current
        latest=$(_stacer_latest_url "AppImage" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        current=$(cat "$_STACER_VERSION_FILE" 2>/dev/null)
        if [[ -n "$latest" && "$latest" == "$current" ]]; then
            info "Stacer is already at the latest release (${current})."
            return 0
        fi
        _stacer_install_appimage
    else
        case "$DISTRO_FAMILY" in
            debian|fedora|rhel|suse) install_stacer ;;
            arch)                    install_stacer ;;
        esac
    fi
}

get_version_stacer() {
    # Do NOT call stacer --version — it launches a full GUI window instead of
    # printing anything.
    _ver_from_pkg stacer || cat "$_STACER_VERSION_FILE" 2>/dev/null || echo ""
}
