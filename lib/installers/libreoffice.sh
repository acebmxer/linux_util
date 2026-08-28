#!/bin/bash
# LibreOffice installer functions

# --- LibreOffice ---

check_libreoffice() {
    _have_cmd libreoffice || \
        _have_cmd soffice || \
        compgen -G "/opt/libreoffice*/program/soffice" &>/dev/null || \
        pkg_check_installed libreoffice || \
        pkg_check_installed libreoffice-common || \
        pkg_check_installed libreoffice-fresh || \
        pkg_check_installed libreoffice-still || \
        dpkg -l 'libreoffice[0-9]*' 2>/dev/null | grep -q "^ii" || \
        (flatpak_is_installed libreoffice)
}
_libreoffice_install_from_site() {
    # Download and install LibreOffice .deb packages directly from the official site.
    # Usage: _libreoffice_install_from_site
    ensure_tools
    local lo_version arch_dir arch_file tmp_dir
    lo_version=$(wget -qO- "https://download.documentfoundation.org/libreoffice/stable/" \
        | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    if [[ -z "$lo_version" ]]; then
        echo "Error: Could not determine latest LibreOffice version."
        return 1
    fi
    echo "Latest LibreOffice version: $lo_version"
    case "$(uname -m)" in
        x86_64)  arch_dir="x86_64"; arch_file="x86-64" ;;
        aarch64) arch_dir="aarch64"; arch_file="aarch64" ;;
        *)
            echo "Error: Unsupported architecture $(uname -m) for direct download."
            return 1
            ;;
    esac
    local url="https://download.documentfoundation.org/libreoffice/stable/${lo_version}/deb/${arch_dir}/LibreOffice_${lo_version}_Linux_${arch_file}_deb.tar.gz"
    tmp_dir=$(mktemp -d /tmp/libreoffice-install-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")
    echo "Downloading LibreOffice ${lo_version}..."
    if ! wget -q --show-progress -O "$tmp_dir/libreoffice.tar.gz" "$url"; then
        echo "Error: Failed to download LibreOffice from $url"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "Extracting..."
    tar -xzf "$tmp_dir/libreoffice.tar.gz" -C "$tmp_dir"
    local deb_dir
    deb_dir=$(find "$tmp_dir" -type d -name "DEBS" | head -1)
    if [[ -z "$deb_dir" ]]; then
        echo "Error: Could not find DEBS directory in archive."
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "Installing .deb packages..."
    if ! sudo dpkg -i "$deb_dir"/*.deb; then
        sudo apt-get install -f -y || true
        if ! sudo dpkg -i "$deb_dir"/*.deb; then
            echo "Error: Failed to install LibreOffice .deb packages."
            rm -rf "$tmp_dir"
            return 1
        fi
    fi
    rm -rf "$tmp_dir"
    echo "LibreOffice ${lo_version} installed successfully."
}
install_libreoffice() {
    echo "Installing LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            _libreoffice_install_from_site
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" check-update >/dev/null 2>&1 || true
            sudo "$PKG_MGR" install -y libreoffice
            ;;
        arch)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        suse)
            sudo zypper install -y libreoffice
            ;;
        *)
            if has_flatpak; then
                sudo flatpak install -y flathub org.libreoffice.LibreOffice
            else
                echo "Error: Unsupported distribution and flatpak is not available."
                return 1
            fi
            ;;
    esac
}
uninstall_libreoffice() {
    echo "Uninstalling LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y 'libreoffice*'
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y 'libreoffice*'
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm libreoffice-fresh 2>/dev/null || \
                sudo pacman -Rs --noconfirm libreoffice-still 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y libreoffice
            ;;
        *)
            if flatpak_is_installed libreoffice; then
                flatpak uninstall -y --user org.libreoffice.LibreOffice 2>/dev/null || \
                    sudo flatpak uninstall -y --system org.libreoffice.LibreOffice
            fi
            ;;
    esac
    rm -rf ~/.config/libreoffice
    rm -rf ~/.libreoffice
    echo "LibreOffice has been uninstalled."
}
update_libreoffice() {
    echo "Updating LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            _libreoffice_install_from_site
            ;;
        fedora|rhel)
            # Check if libreoffice is installed, if not install it instead of upgrading
            if pkg_check_installed libreoffice; then
                sudo "$PKG_MGR" upgrade -y libreoffice
            else
                install_libreoffice
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        suse)
            sudo zypper update -y libreoffice
            ;;
        *)
            if flatpak_is_installed libreoffice; then
                flatpak update -y --user org.libreoffice.LibreOffice 2>/dev/null || \
                    sudo flatpak update -y --system org.libreoffice.LibreOffice
            fi
            ;;
    esac
}
get_version_libreoffice() {
    local lo_bin
    lo_bin=$(_native_command libreoffice 2>/dev/null || _native_command soffice 2>/dev/null || \
        compgen -G "/opt/libreoffice*/program/soffice" 2>/dev/null | sort -V | tail -1)
    # $lo_bin is already a resolved path — _native_command filtered the PATH hits.
    [[ -n "$lo_bin" ]] && "$lo_bin" --version 2>/dev/null | grep -oP 'LibreOffice \K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}
