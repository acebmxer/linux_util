#!/bin/bash
# Neovim text editor installer functions

# --- Neovim ---

check_neovim() { _check_standard nvim neovim ""; }

install_neovim() {
    info "Installing Neovim..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y neovim 2>/dev/null || {
                # Debian/Ubuntu repos sometimes carry very old neovim; fall back to AppImage
                warn "neovim from apt is too old or unavailable. Installing from GitHub releases..."
                _install_neovim_appimage
            }
            ;;
        fedora)
            sudo "$PKG_MGR" install -y neovim
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y neovim 2>/dev/null || {
                warn "neovim not in repos. Installing from GitHub releases..."
                _install_neovim_appimage
            }
            ;;
        arch)
            sudo pacman -S --noconfirm neovim
            ;;
        suse)
            sudo zypper install -y neovim 2>/dev/null || {
                warn "neovim not in repos. Installing from GitHub releases..."
                _install_neovim_appimage
            }
            ;;
    esac
    info "Neovim installed."
}

# Install the stable AppImage from GitHub releases
_install_neovim_appimage() {
    local tmpfile install_dir="/usr/local/bin"
    tmpfile=$(mktemp /tmp/nvim-XXXXXX.appimage)
    CLEANUP_FILES+=("$tmpfile")
    if ! wget -qO "$tmpfile" \
        "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"; then
        error "Failed to download Neovim AppImage."
        return 1
    fi
    sudo install -m 755 "$tmpfile" "$install_dir/nvim"
    info "Neovim AppImage installed to $install_dir/nvim."
}

uninstall_neovim() {
    info "Uninstalling Neovim..."
    # Remove AppImage if installed that way
    if [[ -f /usr/local/bin/nvim ]]; then
        sudo rm -f /usr/local/bin/nvim
    fi
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y neovim 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y neovim 2>/dev/null || true ;;
        arch)        sudo pacman -Rs --noconfirm neovim 2>/dev/null || true ;;
        suse)        sudo zypper remove -y neovim 2>/dev/null || true ;;
    esac
    rm -rf "$HOME/.config/nvim" "$HOME/.local/share/nvim"
}

update_neovim() {
    info "Updating Neovim..."
    if [[ -f /usr/local/bin/nvim ]]; then
        _install_neovim_appimage
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade neovim ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y neovim ;;
            arch)        sudo pacman -S --noconfirm neovim ;;
            suse)        sudo zypper update -y neovim ;;
        esac
    fi
}

get_version_neovim() {
    _ver_from_cmd nvim || _ver_from_pkg neovim || echo ""
}
