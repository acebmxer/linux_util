#!/bin/bash
# LACT (Linux AMDGPU Top) installer functions
# https://github.com/ilya-zlobintsev/LACT

# --- LACT ---

check_lact() { _check_standard lact lact ""; }

_lact_latest_deb_url() {
    local all_debs
    all_debs=$(curl -fsSL "https://api.github.com/repos/ilya-zlobintsev/LACT/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+\.deb' \
        | grep -v 'dbg\|dev\|doc\|headless')

    # Build distro-specific suffix: ubuntu-2604, debian-13, etc.
    # LACT names Ubuntu builds by major+minor only (e.g. ubuntu-2604), so strip
    # any appended point release (DISTRO_VERSION_ID may be "26.04.0") before
    # compacting — otherwise "26.04.0" → "26040" and the exact match is missed.
    local distro_suffix=""
    case "$DISTRO_ID" in
        ubuntu|kubuntu|linuxmint|pop|neon)
            local ver_major_minor ver_compact
            ver_major_minor=$(echo "$DISTRO_VERSION_ID" | grep -oP '^[0-9]+\.[0-9]+')
            ver_compact=$(echo "$ver_major_minor" | tr -d '.')
            distro_suffix="ubuntu-${ver_compact}"
            ;;
        debian)
            distro_suffix="debian-${DISTRO_VERSION_ID%%.*}"
            ;;
    esac

    # Exact match first
    if [[ -n "$distro_suffix" ]]; then
        local matched
        matched=$(echo "$all_debs" | grep "${distro_suffix}" | head -1)
        [[ -n "$matched" ]] && { echo "$matched"; return 0; }
    fi

    # For Ubuntu-family systems with no exact match, pick the newest available
    # ubuntu-* build (closest compatible ABI), then fall back to debian-*
    if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
        local ubuntu_deb
        ubuntu_deb=$(echo "$all_debs" | grep "ubuntu-" | sort -V | tail -1)
        [[ -n "$ubuntu_deb" ]] && { echo "$ubuntu_deb"; return 0; }
    fi

    # Generic fallback
    echo "$all_debs" | head -1
}

install_lact() {
    info "Installing LACT (Linux AMDGPU Top)..."
    ensure_tools

    case "$DISTRO_FAMILY" in
        debian)
            local url
            url=$(_lact_latest_deb_url)
            if [[ -z "$url" ]]; then
                error "Could not find LACT .deb release URL from GitHub."
                return 1
            fi
            local tmpfile
            tmpfile=$(mktemp /tmp/lact-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            info "Downloading LACT from: $url"
            wget -qO "$tmpfile" "$url" || { error "Failed to download LACT .deb."; return 1; }
            verify_download "$tmpfile" "deb" "LACT" || return 1
            sudo apt install -y "$tmpfile" || { error "Failed to install LACT .deb."; return 1; }
            ;;
        fedora)
            # LACT is available via a COPR repository
            sudo dnf copr enable -y ilyaz/LACT || {
                error "Failed to enable LACT COPR repository."
                return 1
            }
            sudo dnf install -y lact || { error "Failed to install LACT."; return 1; }
            ;;
        rhel)
            # COPR is available on RHEL/CentOS via dnf
            sudo dnf copr enable -y ilyaz/LACT 2>/dev/null || \
            sudo yum copr enable -y ilyaz/LACT 2>/dev/null || {
                error "Failed to enable LACT COPR repository. Ensure 'dnf-plugins-core' is installed."
                return 1
            }
            sudo "$PKG_MGR" install -y lact || { error "Failed to install LACT."; return 1; }
            ;;
        arch)
            repo_or_aur lact
            ;;
        suse)
            # LACT is available via the hardware OBS repository
            local obs_distro
            if [[ "$DISTRO_ID" == "opensuse-leap" ]]; then
                obs_distro="openSUSE_Leap_${DISTRO_VERSION_ID}"
            else
                obs_distro="openSUSE_Tumbleweed"
            fi
            sudo zypper addrepo -f \
                "https://download.opensuse.org/repositories/hardware/${obs_distro}/" \
                "hardware" 2>/dev/null || true
            sudo zypper --gpg-auto-import-keys refresh
            sudo zypper install -y lact || { error "Failed to install LACT."; return 1; }
            ;;
        *)
            error "LACT installation is not supported on this distribution."
            return 1
            ;;
    esac

    # Enable and start the LACT daemon — required for the GUI to apply GPU settings
    if systemctl list-unit-files lact.service &>/dev/null 2>&1; then
        sudo systemctl enable lact.service || warn "Failed to enable lact.service"
        sudo systemctl start lact.service || warn "Failed to start lact.service; a reboot may be needed"
    fi

    info "LACT installed successfully."
    info "A reboot is required before LACT can apply GPU changes."
}

uninstall_lact() {
    info "Uninstalling LACT..."

    # Stop and disable daemon first
    sudo systemctl stop lact.service 2>/dev/null || true
    sudo systemctl disable lact.service 2>/dev/null || true

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y lact 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y lact 2>/dev/null || true
            ;;
        arch)
            aur_remove lact 2>/dev/null || \
                sudo pacman -Rs --noconfirm lact 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y lact 2>/dev/null || true
            ;;
    esac

    rm -rf "$HOME/.config/lact"
}

update_lact() {
    info "Updating LACT..."
    case "$DISTRO_FAMILY" in
        debian)
            install_lact
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y lact 2>/dev/null || install_lact
            ;;
        arch)
            repo_or_aur lact
            ;;
        suse)
            sudo zypper update -y lact 2>/dev/null || install_lact
            ;;
    esac
}

get_version_lact() {
    _ver_from_cmd lact --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
        _ver_from_pkg lact || echo ""
}
