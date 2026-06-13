#!/bin/bash
# Mainline — Ubuntu mainline-kernel installer (the cappelikan/bkw777 fork of ukuu).
#
# A GTK GUI (mainline-gtk) plus a CLI (mainline) that downloads and installs
# mainline kernel packages from kernel.ubuntu.com, lists installed/available
# kernels, and removes old ones. Debian/Ubuntu family only: it is a .deb app
# built against Ubuntu's libvte/libgee with no upstream package for Arch,
# Fedora, or openSUSE.
#
# Install strategy (debian family only):
#   Ubuntu & derivatives → add ppa:cappelikan/ppa, then apt install mainline.
#                          add-apt-repository resolves dependencies and pulls the
#                          codename-matched build automatically (preferred path).
#   Plain Debian / no PPA → install the latest .deb from the bkw777/mainline
#                          GitHub release via apt (best-effort: upstream publishes
#                          an amd64 build; apt resolves its dependencies).

# --- Mainline ---

MAINLINE_PPA="ppa:cappelikan/ppa"
MAINLINE_DEB_API="https://api.github.com/repos/bkw777/mainline/releases/latest"

check_mainline() {
    _check_standard mainline mainline ""
}

# The cappelikan PPA only publishes builds for Ubuntu codenames, so the PPA path
# is used on Ubuntu and its derivatives only. UBUNTU_CODENAME in os-release is
# the reliable catch-all (Mint, Pop!_OS, Zorin, elementary, KDE neon all set it).
_mainline_is_ubuntu_based() {
    case "$DISTRO_ID" in ubuntu|kubuntu|neon|pop|linuxmint|elementary|zorin) return 0 ;; esac
    [[ "$DISTRO_ID_LIKE" == *ubuntu* ]] && return 0
    grep -q '^UBUNTU_CODENAME=' /etc/os-release 2>/dev/null
}

get_version_mainline() {
    _ver_from_pkg mainline || _ver_from_cmd mainline --version || echo ""
}

# Download the latest published .deb from the bkw777/mainline GitHub release and
# install it via apt (apt resolves dependencies). Used on plain Debian, or on any
# apt system where the cappelikan PPA could not be added.
_mainline_install_from_deb() {
    local url
    url=$(curl -fsSL "$MAINLINE_DEB_API" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.deb' \
        | grep -iE 'amd64|_all' | head -1)
    if [[ -z "$url" ]]; then
        error "Could not find a Mainline .deb in the latest GitHub release."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp "/tmp/mainline-XXXXXX.deb")
    CLEANUP_FILES+=("$tmpfile")

    info "Downloading Mainline from: $url"
    download_file "$url" "$tmpfile" || { error "Failed to download the Mainline .deb."; return 1; }
    verify_download "$tmpfile" "deb" "Mainline" || return 1

    sudo apt install -y "$tmpfile" \
        || sudo apt-get install -y -f \
        || { error "Failed to install the Mainline .deb."; return 1; }
}

install_mainline() {
    info "Installing Mainline (Ubuntu mainline-kernel installer)..."

    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        warn "Mainline only installs Ubuntu mainline kernels, so it is a Debian/Ubuntu-only tool."
        warn "On Arch try 'CachyOS Kernel Manager'; on Fedora try 'Fedora Mainline Kernel'."
        return 1
    fi

    ensure_tools

    # Preferred path on Ubuntu & derivatives: the cappelikan PPA. add-apt-repository
    # selects the codename-matched build and resolves dependencies. On failure the
    # PPA is removed again so it can't break later apt-get updates.
    if command -v add-apt-repository &>/dev/null && _mainline_is_ubuntu_based; then
        info "Adding the Mainline PPA (${MAINLINE_PPA})..."
        if run_as_root add-apt-repository -y "$MAINLINE_PPA" 2>/dev/null && run_as_root apt-get update; then
            if pkg_install mainline; then
                info "Mainline installed. Launch the GUI with 'mainline-gtk', or use the 'mainline' CLI."
                return 0
            fi
        fi
        warn "PPA install did not complete — removing the PPA and falling back to the upstream .deb."
        run_as_root add-apt-repository -r -y "$MAINLINE_PPA" 2>/dev/null || true
        run_as_root apt-get update 2>/dev/null || true
    fi

    # Fallback: the published .deb (plain Debian, or PPA path unavailable/failed).
    _mainline_install_from_deb || return 1
    info "Mainline installed. Launch the GUI with 'mainline-gtk', or use the 'mainline' CLI."
}

uninstall_mainline() {
    info "Uninstalling Mainline..."
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        info "Mainline is only installed on Debian/Ubuntu — nothing to do."
        return 0
    fi
    pkg_remove mainline 2>/dev/null || true
    # Drop the PPA if add-apt-repository added it (harmless if it was never added).
    if command -v add-apt-repository &>/dev/null; then
        run_as_root add-apt-repository -r -y "$MAINLINE_PPA" 2>/dev/null || true
    fi
    rm -rf "$HOME/.config/mainline"
    # Mainline only manages kernels; installed kernels are intentionally left in place.
}

update_mainline() {
    info "Updating Mainline..."
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        warn "Mainline is a Debian/Ubuntu-only tool."
        return 1
    fi
    if pkg_check_installed mainline && command -v add-apt-repository &>/dev/null; then
        pkg_upgrade mainline
    else
        install_mainline
    fi
}
