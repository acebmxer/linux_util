#!/bin/bash
# Fastfetch installer functions

# --- Fastfetch ---

check_fastfetch() { _check_standard fastfetch fastfetch ""; }

_fastfetch_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+linux-amd64\.'"$ext"'"' | head -1
}

install_fastfetch() {
    info "Installing Fastfetch..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Available in Ubuntu 23.10+ and Debian 13+ natively; use .deb for older versions
            if sudo apt install -y fastfetch 2>/dev/null; then
                : # installed from repo
            else
                info "Installing Fastfetch from GitHub release..."
                local url
                url=$(_fastfetch_latest_url "deb")
                if [[ -z "$url" ]]; then
                    error "Could not find Fastfetch .deb release."
                    return 1
                fi
                local tmpfile
                tmpfile=$(mktemp /tmp/fastfetch-XXXXXX.deb)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Fastfetch .deb."; return 1; }
                sudo apt install -y "$tmpfile"
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y fastfetch
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y fastfetch 2>/dev/null || {
                info "Installing Fastfetch from GitHub release..."
                local url
                url=$(_fastfetch_latest_url "rpm")
                [[ -z "$url" ]] && { error "Could not find Fastfetch .rpm release."; return 1; }
                local tmpfile
                tmpfile=$(mktemp /tmp/fastfetch-XXXXXX.rpm)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Fastfetch .rpm."; return 1; }
                sudo "$PKG_MGR" install -y "$tmpfile"
            }
            ;;
        arch)
            sudo pacman -S --noconfirm fastfetch
            ;;
        suse)
            sudo zypper install -y fastfetch 2>/dev/null || {
                info "Installing Fastfetch from GitHub release..."
                local url
                url=$(_fastfetch_latest_url "rpm")
                [[ -z "$url" ]] && { error "Could not find Fastfetch .rpm release."; return 1; }
                local tmpfile
                tmpfile=$(mktemp /tmp/fastfetch-XXXXXX.rpm)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Fastfetch .rpm."; return 1; }
                sudo zypper install -y "$tmpfile"
            }
            ;;
    esac
    info "Fastfetch installed."
}

uninstall_fastfetch() {
    info "Uninstalling Fastfetch..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y fastfetch 2>/dev/null || sudo dpkg -r fastfetch 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y fastfetch ;;
        arch)    sudo pacman -Rs --noconfirm fastfetch ;;
        suse)    sudo zypper remove -y fastfetch ;;
    esac
    rm -rf "$HOME/.config/fastfetch"
}

update_fastfetch() {
    info "Updating Fastfetch..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update && sudo apt upgrade -y fastfetch 2>/dev/null || install_fastfetch
            ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y fastfetch 2>/dev/null || install_fastfetch ;;
        arch)    sudo pacman -S --noconfirm fastfetch ;;
        suse)    sudo zypper update -y fastfetch 2>/dev/null || install_fastfetch ;;
    esac
}

get_version_fastfetch() {
    _ver_from_cmd fastfetch || echo ""
}
