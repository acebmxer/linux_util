#!/bin/bash
# Wine installer functions

# --- Wine ---

check_wine() { _have_cmd wine; }

install_wine() {
    info "Installing Wine..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Remove any stale WineHQ repo files left by a previous failed install.
            # Without this, apt update errors on the broken URL before we can fix it.
            sudo rm -f /etc/apt/sources.list.d/winehq-*.list \
                       /etc/apt/keyrings/winehq-archive.key

            # Wine requires 32-bit architecture support
            sudo dpkg --add-architecture i386
            sudo apt update

            # Select the WineHQ repo base URL (Ubuntu vs Debian build tree)
            local _wine_repo_base
            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" || "$DISTRO_ID" == "neon" ]]; then
                _wine_repo_base="https://dl.winehq.org/wine-builds/ubuntu"
            else
                _wine_repo_base="https://dl.winehq.org/wine-builds/debian"
            fi

            local _codename="${DISTRO_VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null)}"
            if [[ -z "$_codename" ]]; then
                error "Could not determine distro codename; cannot configure WineHQ repository."
                return 1
            fi

            # Only attempt the WineHQ repo if it actually publishes packages for this codename.
            # New/pre-release distro versions often lag behind WineHQ's release schedule.
            # If the current codename is unsupported, fall back to the newest codename that is.
            local _winehq_codename=""
            # Try current codename first
            if curl -fsSI "${_wine_repo_base}/dists/${_codename}/Release" &>/dev/null; then
                _winehq_codename="$_codename"
            else
                # Walk through recent Ubuntu codenames (newest → oldest) to find the best match
                local _fallbacks=("questing" "plucky" "oracular" "noble" "jammy")
                for _fb in "${_fallbacks[@]}"; do
                    if curl -fsSI "${_wine_repo_base}/dists/${_fb}/Release" &>/dev/null; then
                        _winehq_codename="$_fb"
                        info "WineHQ does not yet support '${_codename}'; using '${_fb}' packages."
                        break
                    fi
                done
            fi

            if [[ -n "$_winehq_codename" ]]; then
                _add_apt_repo \
                    "https://dl.winehq.org/wine-builds/winehq.key" \
                    "/etc/apt/keyrings/winehq-archive.key" \
                    "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.key] ${_wine_repo_base}/ ${_winehq_codename} main" \
                    "/etc/apt/sources.list.d/winehq-${_codename}.list"
                if sudo apt install -y --install-recommends winehq-stable; then
                    return 0
                fi
                # winehq-stable install failed — clean up the broken repo and fall back
                warn "WineHQ stable install failed; falling back to distro Wine package."
                sudo rm -f "/etc/apt/sources.list.d/winehq-${_codename}.list" \
                           /etc/apt/keyrings/winehq-archive.key
                sudo apt update -qq 2>/dev/null || true
            else
                info "WineHQ has no compatible repository; installing distro Wine package."
            fi
            # Fallback: distro-packaged wine
            sudo apt install -y wine || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y wine || return 1
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y wine || return 1
            ;;
        arch)
            if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
                info "Enabling multilib repository (required for Wine 32-bit support)..."
                sudo bash -c 'printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >> /etc/pacman.conf'
                sudo pacman -Sy
            fi
            sudo pacman -S --noconfirm wine wine-mono || return 1
            ;;
        suse)
            sudo zypper install -y wine || return 1
            ;;
    esac
    info "Wine installed."
}

uninstall_wine() {
    info "Uninstalling Wine..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y winehq-stable 2>/dev/null || \
                sudo apt purge --autoremove -y wine 2>/dev/null || true
            local _codename="${DISTRO_VERSION_CODENAME:-}"
            if [[ -n "$_codename" ]]; then
                sudo rm -f "/etc/apt/sources.list.d/winehq-${_codename}.list"
            else
                sudo rm -f /etc/apt/sources.list.d/winehq-*.list
            fi
            sudo rm -f /etc/apt/keyrings/winehq-archive.key
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y wine 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rs --noconfirm wine wine-mono 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y wine 2>/dev/null || true
            ;;
    esac
    rm -rf "$HOME/.wine"
}

update_wine() {
    info "Updating Wine..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade winehq-stable 2>/dev/null || \
                sudo apt-get install -y --only-upgrade wine 2>/dev/null || true
            ;;
        arch)
            sudo pacman -S --noconfirm wine wine-mono
            ;;
        *)
            pkg_upgrade wine
            ;;
    esac
}

get_version_wine() {
    _run_native wine --version 2>/dev/null | sed 's/^wine-//' || echo ""
}
