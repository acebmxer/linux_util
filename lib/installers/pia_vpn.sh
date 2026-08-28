#!/bin/bash
# PIA VPN installer functions
#
# Every family except openSUSE installs from upstream's own .run bundle, which
# is self-contained and distro-agnostic — it unpacks into /opt/piavpn and
# registers a systemd unit rather than going through any package manager.
#
# Arch used to call repo_or_aur privateinternetaccess-bin. That package is gone
# from the AUR — an AUR search for "privateinternetaccess" returns no results at
# all — so the call could only fail: pacman has no such package, and the AUR
# fallback cloned a repository that does not exist. Since the .run bundle was
# already in this file for debian/fedora/rhel, Arch now uses it too.

# --- PIA VPN ---

_PIA_UNINSTALL="/opt/piavpn/bin/uninstall.sh"

check_pia_vpn() {
    _have_cmd piactl || \
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
            _pia_install_via_run || return 1
            ;;
        suse)
            # For openSUSE, try Flatpak as primary method
            if has_flatpak; then
                sudo flatpak install -y flathub com.privateinternetaccess.PIA
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
    local pia_installer pia_url page matches
    pia_installer=$(mktemp /tmp/pia-XXXXXX.run)
    CLEANUP_FILES+=("$pia_installer")
    # Scrape the current x64 .run download URL from the PIA website. The page is
    # captured before it is filtered: piping curl into `head -1` closes the pipe
    # early and curl reports that as "(23) Failure writing output to destination".
    page=$(curl -fsSL "https://www.privateinternetaccess.com/download/linux-vpn")
    matches=$(printf '%s\n' "$page" | grep -oE 'https://[^"]+pia-linux-[0-9][^"]*\.run')
    pia_url="${matches%%$'\n'*}"
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
    verify_download "$pia_installer" "run" "PIA VPN" || return 1
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
    # The .run bundle never registers with a package manager, so its own script
    # is the only thing that can remove it. Checked first on every family,
    # because debian/fedora/rhel install from the bundle too — the package
    # manager branches below only ever match a copy that came from a repo.
    if [[ -x "$_PIA_UNINSTALL" ]]; then
        sudo "$_PIA_UNINSTALL" || true
        rm -rf ~/.config/privateinternetaccess ~/.privateinternetaccess
        echo "PIA VPN has been uninstalled."
        return 0
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y privateinternetaccess
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/pia.list
            sudo rm -f /usr/share/keyrings/pia-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y privateinternetaccess
            ;;
        arch)
            # Only reachable for an install predating the switch to the .run
            # bundle; privateinternetaccess-bin no longer exists in the AUR.
            sudo pacman -Rs --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -Rs --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y --user com.privateinternetaccess.PIA 2>/dev/null || \
                sudo flatpak uninstall -y --system com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/privateinternetaccess
    rm -rf ~/.privateinternetaccess
    echo "PIA VPN has been uninstalled."
}

update_pia_vpn() {
    echo "Updating PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel|arch)
            _pia_install_via_run || return 1
            ;;
        suse)
            flatpak update -y --user com.privateinternetaccess.PIA 2>/dev/null || \
                sudo flatpak update -y --system com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
}

get_version_pia_vpn() {
    _run_native piactl --version 2>/dev/null || echo ""
}
