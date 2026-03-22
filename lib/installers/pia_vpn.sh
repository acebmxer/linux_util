#!/bin/bash
# PIA VPN installer functions

# --- PIA VPN ---

check_pia_vpn() {
    command -v piactl &>/dev/null || \
        [[ -x /opt/piavpn/bin/piactl ]] || \
        pkg_check_installed privateinternetaccess
}

install_pia_vpn() {
    echo "Installing PIA VPN..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _pia_install_via_run || return 1
            ;;
        fedora|rhel)
            _pia_install_via_run || return 1
            ;;
        arch)
            # Install from AUR
            if has_aur_helper; then
                aur_install privateinternetaccess-bin
            else
                echo "Installing from AUR requires an AUR helper (yay/paru). Please install one first."
                return 1
            fi
            ;;
        suse)
            # For openSUSE, try Flatpak as primary method
            if has_flatpak; then
                flatpak install -y flathub com.privateinternetaccess.PIA
            else
                echo "PIA is not available in default openSUSE repositories."
                echo "Please install Flatpak and use: flatpak install flathub com.privateinternetaccess.PIA"
                return 1
            fi
            ;;
    esac
    echo "PIA VPN installed successfully."
}

# Download and install PIA VPN from the official website.
_pia_install_via_run() {
    local pia_installer pia_url
    pia_installer=$(mktemp /tmp/pia-XXXXXX.run)
    CLEANUP_FILES+=("$pia_installer")
    # Scrape the current x64 .run download URL from the PIA website
    pia_url=$(curl -fsSL "https://www.privateinternetaccess.com/download/linux-vpn" | \
        grep -oE 'https://[^"]+pia-linux-[0-9][^"]*\.run' | head -1)
    if [[ -z "$pia_url" ]]; then
        echo "Error: Failed to get PIA VPN download URL from website."
        rm -f "$pia_installer"
        return 1
    fi
    if ! wget -qO "$pia_installer" "$pia_url"; then
        echo "Error: Failed to download PIA VPN installer. Check network connectivity."
        rm -f "$pia_installer"
        return 1
    fi
    chmod +x "$pia_installer"
    if ! "$pia_installer" --accept --quiet; then
        echo "Error: Failed to install PIA VPN."
        rm -f "$pia_installer"
        return 1
    fi
    rm -f "$pia_installer"
}

uninstall_pia_vpn() {
    echo "Uninstalling PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y privateinternetaccess
            sudo rm -f /etc/apt/sources.list.d/pia.list
            sudo rm -f /usr/share/keyrings/pia-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y privateinternetaccess
            ;;
        arch)
            sudo pacman -Rs --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -Rs --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
    echo "PIA VPN has been uninstalled."
}

update_pia_vpn() {
    echo "Updating PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel)
            _pia_install_via_run || return 1
            ;;
        arch)
            sudo pacman -S --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -S --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak update -y com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
}

get_version_pia_vpn() {
    piactl --version 2>/dev/null || echo ""
}
