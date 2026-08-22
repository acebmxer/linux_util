#!/bin/bash
# Libation installer functions

# --- Libation ---

check_libation() { _check_standard libation libation ""; }

_libation_latest_url() {
    local ext="$1"  # deb or rpm
    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) error "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac
    curl -fsSL "https://api.github.com/repos/rmcrackan/Libation/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+linux-chardonnay-'"$arch"'\.'"$ext"'(?=")' | head -1
}

# Install Libation from upstream's own .deb payload (Arch path).
#
# Libation is not in any Arch repo and is not on Flathub. Upstream publishes a
# .deb and .rpm per release; the .deb carries a self-contained .NET build under
# /usr/lib/libation with no Depends field at all, so the payload is simply
# unpacked rather than handed to a package manager.
_LIBATION_GH_API="https://api.github.com/repos/rmcrackan/Libation/releases/latest"
_LIBATION_PREFIX="/usr/lib/libation"
_LIBATION_LINK="/usr/local/bin/libation"
_LIBATION_CLI_LINK="/usr/local/bin/libationcli"
_LIBATION_DESKTOP="/usr/share/applications/libation.desktop"

_libation_install_deb_payload() {
    local machine pattern url tmpdir deb member
    machine=$(uname -m)
    case "$machine" in
        x86_64)        pattern='linux-chardonnay-amd64\.deb$' ;;
        aarch64|arm64) pattern='linux-chardonnay-arm64\.deb$' ;;
        *) error "Unsupported architecture for Libation: ${machine}"; return 1 ;;
    esac

    if ! command -v ar &>/dev/null; then
        info "Installing binutils (needed to unpack the Libation .deb)..."
        pkg_install binutils || { error "Could not install binutils."; return 1; }
    fi

    url=$(curl -fsSL "$_LIBATION_GH_API" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' | grep -m1 -E "$pattern")
    [[ -z "$url" ]] && { error "Could not find a Libation .deb release asset."; return 1; }

    tmpdir=$(mktemp -d /tmp/libation-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    deb="$tmpdir/libation.deb"

    info "Downloading Libation..."
    wget -qO "$deb" "$url" || { error "Failed to download Libation."; return 1; }
    verify_download "$deb" "deb" "Libation" || return 1

    # Match the member rather than hardcoding the compression: upstream ships
    # data.tar.xz today, and this survives a switch to zst or gz.
    member=$(ar t "$deb" 2>/dev/null | grep '^data\.tar' | head -1)
    [[ -z "$member" ]] && { error "Libation .deb has no data member."; return 1; }

    mkdir -p "$tmpdir/payload"
    case "$member" in
        *.xz)  ar p "$deb" "$member" | tar xJ -C "$tmpdir/payload" ;;
        *.zst) ar p "$deb" "$member" | zstd -dc | tar x -C "$tmpdir/payload" ;;
        *.gz)  ar p "$deb" "$member" | tar xz -C "$tmpdir/payload" ;;
        *)     error "Unsupported compression on '${member}'."; return 1 ;;
    esac || { error "Failed to unpack the Libation payload."; return 1; }

    if [[ ! -x "$tmpdir/payload/usr/lib/libation/Libation" ]]; then
        error "Unpacked Libation payload is missing usr/lib/libation/Libation."
        return 1
    fi

    info "Installing Libation to ${_LIBATION_PREFIX}..."
    sudo rm -rf "$_LIBATION_PREFIX"
    sudo mkdir -p /usr/lib
    sudo cp -a "$tmpdir/payload/usr/lib/libation" "$_LIBATION_PREFIX" || {
        error "Failed to install Libation."
        return 1
    }
    command -v restorecon &>/dev/null && sudo restorecon -RF "$_LIBATION_PREFIX" 2>/dev/null || true

    sudo ln -sf "$_LIBATION_PREFIX/Libation" "$_LIBATION_LINK"
    sudo ln -sf "$_LIBATION_PREFIX/LibationCli" "$_LIBATION_CLI_LINK"

    local d
    d=$(find "$tmpdir/payload/usr/share/applications" -name '*.desktop' 2>/dev/null | head -1)
    [[ -f "$d" ]] && sudo install -Dm644 "$d" "$_LIBATION_DESKTOP"
    refresh_desktop_caches
    return 0
}

install_libation() {
    info "Installing Libation..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_libation_latest_url "deb")
            if [[ -z "$url" ]]; then
                error "Could not find Libation .deb release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/libation-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Libation .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Libation" || return 1
            github_verify_checksum "https://api.github.com/repos/rmcrackan/Libation/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel|suse)
            local url
            url=$(_libation_latest_url "rpm")
            if [[ -z "$url" ]]; then
                error "Could not find Libation .rpm release URL."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/libation-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Libation .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Libation" || return 1
            github_verify_checksum "https://api.github.com/repos/rmcrackan/Libation/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            if [[ "$DISTRO_FAMILY" == "suse" ]]; then
                sudo zypper install -y --allow-unsigned-rpm "$tmpfile"
            else
                sudo "$PKG_MGR" install -y "$tmpfile"
            fi
            ;;
        arch)
            # repos -> (not on Flathub) -> upstream .deb payload -> AUR.
            arch_install_ordered "libation" "" "_libation_install_deb_payload" "libation"
            ;;
    esac
    info "Libation installed."
}

uninstall_libation() {
    info "Uninstalling Libation..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y libation
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y libation
            ;;
        suse)
            sudo zypper remove -y libation
            ;;
        arch)
            aur_remove libation 2>/dev/null || \
                sudo pacman -Rs --noconfirm libation 2>/dev/null || true
            ;;
    esac
    # ~/Libation and the Books folder hold the user's library database and
    # downloaded audiobooks — intentionally left untouched.
    rm -rf "$HOME/.config/Libation"
}

update_libation() {
    info "Updating Libation..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel|suse) install_libation ;;
        arch)
            # repos -> (not on Flathub) -> upstream .deb payload -> AUR.
            arch_install_ordered "libation" "" "_libation_install_deb_payload" "libation"
            ;;
    esac
}

get_version_libation() {
    # Do NOT call libation --version — it launches the full GUI window.
    _ver_from_pkg libation || echo ""
}
