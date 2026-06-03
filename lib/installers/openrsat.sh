#!/bin/bash
# OpenRSAT installer functions
# https://github.com/tranquilit/OpenRSAT
#
# OpenRSAT is a cross-platform Active Directory management console (Microsoft
# RSAT-like) from Tranquil IT. Upstream publishes only GitHub release artifacts
# (no apt/dnf repo, no AUR, no Flatpak):
#   .deb  — amd64, arm64, armhf, i386
#   .rpm  — x86_64
#   raw Linux binaries — OpenRSAT-linux-{x64,arm64,i386,arm32}
#
# Strategy by family:
#   debian       → matching .deb installed via apt (resolves dependencies)
#   fedora|rhel  → x86_64 .rpm installed via the native package manager
#   suse         → standalone binary to /usr/local/bin + .desktop launcher
#   arch / other → unsupported (no upstream package for these)

# --- OpenRSAT ---

OPENRSAT_REPO="tranquilit/OpenRSAT"
OPENRSAT_API="https://api.github.com/repos/${OPENRSAT_REPO}/releases/latest"
OPENRSAT_BIN="/usr/local/bin/openrsat"
OPENRSAT_DESKTOP="/usr/share/applications/openrsat.desktop"

# Installed if the command is on PATH, the package is registered (either casing),
# or the standalone binary exists.
check_openrsat() {
    _check_standard openrsat openrsat "" && return 0
    pkg_check_installed OpenRSAT && return 0
    [[ -x "$OPENRSAT_BIN" ]] && return 0
    return 1
}

# Print the browser_download_url of the latest release asset whose filename
# matches the given extended-regex. Empty output means no match / API failure.
# Usage: _openrsat_asset_url <regex>
_openrsat_asset_url() {
    curl -fsSL "$OPENRSAT_API" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -iE "$1" \
        | head -1
}

# OpenRSAT's .deb/.rpm postinst runs update-desktop-database, which ships in
# desktop-file-utils. Upstream does not declare this as a dependency, so on a
# minimal system the postinst fails with exit 127 and leaves the package
# half-configured. Install it explicitly first. The package name is the same on
# apt, dnf/yum, pacman, and zypper, so no per-distro mapping is needed.
_openrsat_ensure_desktop_utils() {
    command -v update-desktop-database >/dev/null 2>&1 && return 0
    info "Installing prerequisite 'desktop-file-utils' for OpenRSAT..."
    pkg_install desktop-file-utils
    command -v update-desktop-database >/dev/null 2>&1 || \
        warn "desktop-file-utils unavailable; OpenRSAT post-install steps may fail."
}

# Download the matching .deb/.rpm to a temp file and install it.
# Usage: _openrsat_install_pkg <deb|rpm> <arch-regex>
_openrsat_install_pkg() {
    local pkg_type="$1" arch_regex="$2"
    local url
    url=$(_openrsat_asset_url "${arch_regex}\\.${pkg_type}\$")
    if [[ -z "$url" ]]; then
        error "Could not find an OpenRSAT .${pkg_type} for this architecture in the latest GitHub release."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp "/tmp/openrsat-XXXXXX.${pkg_type}")
    CLEANUP_FILES+=("$tmpfile")

    info "Downloading OpenRSAT from: $url"
    if ! download_file "$url" "$tmpfile"; then
        error "Failed to download OpenRSAT .${pkg_type}."
        return 1
    fi
    verify_download "$tmpfile" "$pkg_type" "OpenRSAT" || return 1
    # Best-effort checksum check (upstream may not publish one).
    github_verify_checksum "$OPENRSAT_API" "$(basename "$url")" "$tmpfile" || return 1

    _openrsat_ensure_desktop_utils

    case "$pkg_type" in
        deb)
            sudo apt install -y "$tmpfile" \
                || sudo apt-get install -y -f \
                || { error "Failed to install OpenRSAT .deb."; return 1; }
            ;;
        rpm)
            sudo "$PKG_MGR" install -y "$tmpfile" || \
                sudo rpm -Uvh --replacefiles "$tmpfile" || { error "Failed to install OpenRSAT .rpm."; return 1; }
            ;;
    esac
}

# Install the standalone binary plus a desktop launcher (suse fallback).
# Usage: _openrsat_install_binary <asset-suffix>   e.g. "x64", "arm64"
_openrsat_install_binary() {
    local suffix="$1"
    local url
    url=$(_openrsat_asset_url "OpenRSAT-linux-${suffix}\$")
    if [[ -z "$url" ]]; then
        error "Could not find the OpenRSAT-linux-${suffix} binary in the latest GitHub release."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp "/tmp/openrsat-XXXXXX")
    CLEANUP_FILES+=("$tmpfile")

    info "Downloading OpenRSAT from: $url"
    if ! download_file "$url" "$tmpfile"; then
        error "Failed to download the OpenRSAT binary."
        return 1
    fi
    # Plain ELF executable rather than a package archive. The "AppImage" verifier
    # checks for ELF magic bytes (soft-warns rather than failing on mismatch).
    verify_download "$tmpfile" "AppImage" "OpenRSAT" || return 1
    github_verify_checksum "$OPENRSAT_API" "$(basename "$url")" "$tmpfile" || return 1

    sudo install -Dm755 "$tmpfile" "$OPENRSAT_BIN" || {
        error "Failed to install OpenRSAT to ${OPENRSAT_BIN}."
        return 1
    }

    # Minimal launcher so the GUI app appears in application menus.
    sudo tee "$OPENRSAT_DESKTOP" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=OpenRSAT
Comment=Active Directory management console
Exec=${OPENRSAT_BIN}
Terminal=false
Categories=System;Network;RemoteAccess;
EOF
}

install_openrsat() {
    info "Installing OpenRSAT..."
    ensure_tools

    local arch
    arch="$(uname -m)"

    case "$DISTRO_FAMILY" in
        debian)
            local arch_regex
            case "$arch" in
                x86_64)         arch_regex="amd64" ;;
                aarch64|arm64)  arch_regex="arm64" ;;
                armv7l|armv6l)  arch_regex="armhf" ;;
                i?86)           arch_regex="i386" ;;
                *)
                    error "OpenRSAT does not provide a .deb for architecture '${arch}'."
                    return 1
                    ;;
            esac
            _openrsat_install_pkg "deb" "$arch_regex" || return 1
            ;;
        fedora|rhel)
            if [[ "$arch" != "x86_64" ]]; then
                error "OpenRSAT only provides an .rpm for x86_64 (this system is '${arch}')."
                return 1
            fi
            _openrsat_install_pkg "rpm" "x86_64" || return 1
            ;;
        suse)
            # No openSUSE package upstream — use the standalone Linux binary.
            local suffix
            case "$arch" in
                x86_64)         suffix="x64" ;;
                aarch64|arm64)  suffix="arm64" ;;
                armv7l|armv6l)  suffix="arm32" ;;
                i?86)           suffix="i386" ;;
                *)
                    error "OpenRSAT does not provide a Linux binary for architecture '${arch}'."
                    return 1
                    ;;
            esac
            _openrsat_install_binary "$suffix" || return 1
            ;;
        *)
            error "OpenRSAT installation is not supported on this distribution."
            return 1
            ;;
    esac

    info "OpenRSAT installed successfully."
}

uninstall_openrsat() {
    info "Uninstalling OpenRSAT..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y openrsat 2>/dev/null || \
                pkg_remove openrsat 2>/dev/null || pkg_remove OpenRSAT 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y openrsat 2>/dev/null || \
                sudo "$PKG_MGR" remove -y OpenRSAT 2>/dev/null || true
            ;;
        suse|*)
            # Binary install (or leftover) — remove the binary and launcher.
            sudo rm -f "$OPENRSAT_BIN" "$OPENRSAT_DESKTOP"
            ;;
    esac

    # In case a package install was later replaced by a binary install, clean both.
    [[ -e "$OPENRSAT_BIN" ]] && sudo rm -f "$OPENRSAT_BIN"
    [[ -e "$OPENRSAT_DESKTOP" ]] && sudo rm -f "$OPENRSAT_DESKTOP"

    rm -rf "$HOME/.config/openrsat" "$HOME/.config/OpenRSAT"
}

update_openrsat() {
    info "Updating OpenRSAT..."
    # No upstream repo to upgrade from — re-download the latest release.
    install_openrsat
}

get_version_openrsat() {
    _ver_from_pkg openrsat || _ver_from_pkg OpenRSAT || \
        _ver_from_cmd openrsat --version || echo ""
}
