#!/bin/bash
# Neovim text editor installer functions

# --- Neovim ---

check_neovim() { _check_standard nvim neovim ""; }

install_neovim() {
    info "Installing Neovim..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install neovim 2>/dev/null || {
                # Debian/Ubuntu repos sometimes carry very old neovim; fall back to AppImage
                warn "neovim from apt is too old or unavailable. Installing from GitHub releases..."
                _install_neovim_appimage
            }
            ;;
        fedora)
            pkg_install neovim
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install neovim 2>/dev/null || {
                warn "neovim not in repos. Installing from GitHub releases..."
                _install_neovim_appimage
            }
            ;;
        arch)
            pkg_install neovim
            ;;
        suse)
            pkg_install neovim 2>/dev/null || {
                warn "neovim not in repos. Installing from GitHub releases..."
                _install_neovim_appimage
            }
            ;;
    esac
    info "Neovim installed."
}

# Install the stable AppImage from GitHub releases
_install_neovim_appimage() {
    local tmpdir tmpfile install_dir="/usr/local/bin"
    tmpdir=$(mktemp -d /tmp/nvim-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    # Checked against the SHA-256 GitHub publishes for the release file.
    tmpfile=$(github_asset_download neovim/neovim 'nvim-linux-x86_64\.appimage' "$tmpdir") || {
        error "Failed to download Neovim AppImage."
        return 1
    }
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
        debian)      pkg_remove neovim 2>/dev/null || true ;;
        fedora|rhel) pkg_remove neovim 2>/dev/null || true ;;
        arch)        pkg_remove neovim 2>/dev/null || true ;;
        suse)        pkg_remove neovim 2>/dev/null || true ;;
    esac
    # Your own configuration and plugins stay (issue #101).
    info "Your Neovim settings in ~/.config/nvim and ~/.local/share/nvim were kept."
}

update_neovim() {
    info "Updating Neovim..."
    if [[ -f /usr/local/bin/nvim ]]; then
        _install_neovim_appimage
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade neovim ;;
            fedora|rhel) pkg_upgrade neovim ;;
            arch)        pkg_upgrade neovim ;;
            suse)        pkg_upgrade neovim ;;
        esac
    fi
}

get_version_neovim() {
    _ver_from_cmd nvim || _ver_from_pkg neovim || echo ""
}
