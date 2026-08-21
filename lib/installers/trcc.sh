#!/bin/bash
# TRCC Linux (Thermalright LCD Control Center) installer functions
# Controls the LCD screens and RGB LED segments on Thermalright CPU coolers,
# AIO pump heads and fan hubs — a community Linux port of the Windows TRCC.
# https://github.com/Lexonight1/thermalright-trcc-linux

# --- Thermalright TRCC ---

_TRCC_API_LATEST="https://api.github.com/repos/Lexonight1/thermalright-trcc-linux/releases/latest"

# Set by _trcc_download for the caller to install.
_TRCC_PKG_FILE=""

check_trcc() {
    _have_cmd trcc && return 0
    pkg_check_installed trcc-linux && return 0
    # The PyPI route links the launcher into ~/.local/bin, which is not on PATH
    # in every shell this script may be running from.
    [[ -x "$HOME/.local/bin/trcc" ]]
}

# Print the download URL of the newest release asset matching $1 (an ERE).
#
# Every release carries two copies of each package: a versioned name and a
# stable "-latest" alias. Only the versioned names appear in SHA256SUMS.txt, so
# the aliases are filtered out — picking one would silently skip checksum
# verification, since github_verify_checksum treats "filename not in the
# checksums file" as nothing to check rather than as a failure.
_trcc_asset_url() {
    curl -fsSL "$_TRCC_API_LATEST" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -v -- '-latest' \
        | grep -m1 -E "$1" || true
}

# Download and verify the asset matching $2, leaving its path in _TRCC_PKG_FILE.
# $1 is the file extension, used both for the temp name and for the magic-byte
# check (pacman needs the real .pkg.tar.zst suffix to accept the file).
_trcc_download() {
    local ext="$1" pattern="$2" url
    _TRCC_PKG_FILE=""

    url=$(_trcc_asset_url "$pattern")
    if [[ -z "$url" ]]; then
        error "Could not find a TRCC .${ext} release asset."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp "/tmp/trcc-XXXXXX.${ext}")
    CLEANUP_FILES+=("$tmpfile")
    info "Downloading TRCC from: $url"
    wget -qO "$tmpfile" "$url" || { error "Failed to download TRCC .${ext}."; return 1; }
    verify_download "$tmpfile" "$ext" "TRCC" || return 1
    github_verify_checksum "$_TRCC_API_LATEST" "$(basename "$url")" "$tmpfile" || return 1

    _TRCC_PKG_FILE="$tmpfile"
}

# True when apt can offer the split PySide6 modules the standard .deb depends on.
#
# Upstream ships two Debian packages: the standard one depends on
# python3-pyside6.qtcore and friends (Ubuntu 24.04+, Debian 13+), and a legacy
# one that installs its Python dependencies into a venv under /opt/trcc-linux
# for releases where apt has no PySide6 at all. Asking apt which world this is
# beats matching release numbers — derivatives version themselves however they
# like, and the thing that actually decides is whether the dependency resolves.
_trcc_apt_has_pyside6() {
    apt-cache policy python3-pyside6.qtcore 2>/dev/null \
        | grep -qE 'Candidate:[[:space:]]*[^([:space:]]'
}

# Print the hard Requires of the RPM $1 that nothing in the enabled repos provides.
#
# Upstream builds the RPM on whatever Fedora they happen to run — fc43 in older
# releases, fc44 now — and it pins python(abi) to that release's interpreter, so
# it cannot resolve on any other Fedora. On top of that, as of v9.9.10 it hard-
# requires pythonX.Ydist(nvidia-ml-py): upstream's optional [nvidia] extra
# leaked into Requires, and no Fedora or RPM Fusion repo packages that module,
# so dnf refuses the package outright even on the Fedora it was built for.
#
# Both conditions are asked rather than assumed, so the RPM starts being used
# again the moment upstream fixes it. '[' is a glob metacharacter to dnf and is
# escaped before the query — without that, extras provides such as
# pythonX.Ydist(uvicorn[standard]) look unmet when they are not.
_trcc_rpm_unmet_requires() {
    local file="$1" req esc providers
    while read -r req; do
        req="${req%% *}"          # drop the version constraint
        [[ -z "$req" ]] && continue
        case "$req" in rpmlib\(*|/*) continue ;; esac
        esc="${req//\[/[[]}"
        # Captured, not piped into grep -q: under `set -o pipefail` grep -q
        # exits on the first match and SIGPIPEs repoquery, which would make the
        # pipeline fail and report a satisfied require as unmet. Same trap
        # pkg_autoremove works around in lib/pkg_manager.sh.
        providers=$("$PKG_MGR" repoquery --quiet --whatprovides "$esc" 2>/dev/null) || true
        [[ -n "$providers" ]] || printf '%s\n' "$req"
    done < <(rpm -qRp "$file" 2>/dev/null)
}

# Install the first of the listed alternatives this distro actually has.
# These are upstream's Recommends — video playback, theme archives, extra
# sensors — so a name that is in no repo is skipped instead of failing the
# install. Alternatives are tried in order and stop at the first hit, which is
# what keeps ffmpeg-free from being installed only for ffmpeg to replace it.
_trcc_install_first_available() {
    local pkg
    for pkg in "$@"; do
        pkg_check_installed "$pkg" && return 0
        if sudo "$PKG_MGR" install -y "$pkg" &>/dev/null; then
            verbose "TRCC: installed optional dependency ${pkg}"
            return 0
        fi
    done
    return 0
}

# Install from PyPI with pipx — the route for RPM distros upstream's own RPM
# cannot serve. Only genuine system libraries are installed from the package
# manager; PySide6 and the rest of the Python stack come from PyPI as wheels.
_trcc_install_pypi() {
    info "Installing TRCC from PyPI via pipx..."

    case "$DISTRO_FAMILY" in
        fedora|rhel)
            pkg_install pipx sg3_utils portaudio libusb1 xcb-util-cursor || return 1
            _trcc_install_first_available 7zip p7zip
            _trcc_install_first_available ffmpeg-free ffmpeg
            _trcc_install_first_available lm_sensors
            ;;
        suse)
            pkg_install python3-pipx sg3_utils portaudio libusb-1_0-0 libxcb-cursor0 || return 1
            _trcc_install_first_available 7zip p7zip
            _trcc_install_first_available ffmpeg
            _trcc_install_first_available sensors
            ;;
        *)
            error "The PyPI install path is not defined for ${DISTRO_NAME}."
            return 1
            ;;
    esac

    if ! command -v pipx &>/dev/null; then
        error "pipx is not available after installing it — cannot continue."
        return 1
    fi

    # No sudo here: pipx installs into the invoking user's ~/.local/share/pipx
    # and links ~/.local/bin. Run as root it would land in /root and the desktop
    # session would never see the command.
    pipx install trcc-linux || { error "pipx install trcc-linux failed."; return 1; }
    pipx ensurepath &>/dev/null || true

    # The udev rules, usb-storage quirks and modules-load entries that the
    # native packages ship are not part of the PyPI package — `system setup`
    # writes them, re-execing itself through sudo to do it.
    local trcc_bin="$HOME/.local/bin/trcc"
    [[ -x "$trcc_bin" ]] || trcc_bin=$(command -v trcc 2>/dev/null)
    if [[ -x "$trcc_bin" ]]; then
        "$trcc_bin" system setup --yes \
            || warn "'trcc system setup' failed — device access needs it; rerun it manually."
    else
        warn "Could not find the trcc launcher — run 'trcc system setup' once before using TRCC."
    fi
}

_trcc_post_install() {
    info "TRCC installed."
    info "Launch it from the application menu, or run 'trcc gui'."
    info "If your cooler is not detected, reboot — the SCSI displays need the sg module and usb-storage quirks applied at boot."
}

install_trcc() {
    info "Installing TRCC (Thermalright LCD Control Center)..."
    ensure_tools

    case "$DISTRO_FAMILY" in
        debian)
            if _trcc_apt_has_pyside6; then
                _trcc_download deb '\-[0-9]+_all\.deb$' || return 1
            else
                info "apt has no python3-pyside6 candidate — using upstream's legacy .deb, which bundles its Python dependencies in /opt/trcc-linux."
                _trcc_download deb '\.legacy_all\.deb$' || return 1
            fi
            pkg_install_local "$_TRCC_PKG_FILE" || return 1
            ;;
        fedora|rhel)
            local unmet="" have_rpm=false
            # yum has no built-in repoquery, so the requires cannot be checked
            # there; that path goes straight to PyPI rather than guessing.
            if [[ "$PKG_MGR" == "dnf" ]] && _trcc_download rpm '\.fc[0-9]+\.noarch\.rpm$'; then
                have_rpm=true
                unmet=$(_trcc_rpm_unmet_requires "$_TRCC_PKG_FILE")
            fi

            if [[ "$have_rpm" == true && -z "$unmet" ]]; then
                pkg_install_local "$_TRCC_PKG_FILE" || return 1
            else
                if [[ -n "$unmet" ]]; then
                    info "Upstream's RPM cannot be installed here — nothing provides: ${unmet//$'\n'/, }"
                fi
                info "Using upstream's PyPI package instead."
                _trcc_install_pypi || return 1
            fi
            ;;
        suse)
            # Upstream's RPM carries Fedora-namespaced pythonX.Ydist(...)
            # requires that zypper has no provider for, so openSUSE never
            # takes the RPM path.
            _trcc_install_pypi || return 1
            ;;
        arch)
            # Upstream builds a real pacman package and every dependency is in
            # the official repos, so Arch needs no AUR route.
            _trcc_download pkg.tar.zst '\-any\.pkg\.tar\.zst$' || return 1
            pkg_install_local "$_TRCC_PKG_FILE" || return 1
            ;;
        *)
            warn "TRCC installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora, RHEL, openSUSE, Arch/Manjaro."
            return 1
            ;;
    esac

    _trcc_post_install
}

# True when TRCC is present as a pipx install rather than a distro package.
_trcc_is_pipx_install() {
    command -v pipx &>/dev/null || return 1
    pipx list --short 2>/dev/null | grep -q '^trcc-linux '
}

uninstall_trcc() {
    info "Uninstalling TRCC..."

    if pkg_check_installed trcc-linux; then
        pkg_remove trcc-linux
    fi

    if _trcc_is_pipx_install; then
        pipx uninstall trcc-linux || warn "pipx uninstall trcc-linux failed."
        # On the PyPI path these were written by `trcc system setup`, so no
        # package owns them and nothing else will ever take them away. On the
        # native-package path they belong to the package and were removed
        # above, which is why this is gated on the pipx install.
        sudo rm -f /etc/udev/rules.d/99-trcc-lcd.rules \
                   /etc/modprobe.d/trcc-lcd.conf \
                   /etc/modules-load.d/trcc-sg.conf \
                   /etc/modules-load.d/trcc-rapl.conf
        sudo udevadm control --reload-rules 2>/dev/null || true
        sudo udevadm trigger 2>/dev/null || true
    fi

    # Themes, per-device settings and the overlay editor's saved layouts.
    rm -rf "$HOME/.trcc-user"

    info "TRCC has been uninstalled."
}

update_trcc() {
    info "Updating TRCC..."
    if _trcc_is_pipx_install; then
        pipx upgrade trcc-linux || return 1
        return 0
    fi
    # Every native path is "download the newest package and install over it",
    # which is exactly what a fresh install does.
    install_trcc
}

get_version_trcc() {
    local v
    v=$(_ver_from_pkg trcc-linux) && { printf '%s\n' "$v"; return 0; }
    v=$(_ver_from_cmd trcc)       && { printf '%s\n' "$v"; return 0; }
    # pipx's launcher lives in ~/.local/bin, which _ver_from_cmd only finds
    # when that directory is already on PATH.
    if [[ -x "$HOME/.local/bin/trcc" ]]; then
        v=$("$HOME/.local/bin/trcc" --version 2>/dev/null \
            | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [[ -n "$v" ]] && { printf '%s\n' "$v"; return 0; }
    fi
    echo ""
}
