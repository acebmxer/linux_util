#!/bin/bash
# ProtonVPN installer functions

# --- ProtonVPN ---

check_protonvpn() {
    command -v protonvpn-cli &>/dev/null || \
        command -v protonvpn &>/dev/null || \
        pkg_check_installed proton-vpn-gnome-desktop || \
        (flatpak_is_installed "com.protonvpn.www")
}

_protonvpn_get_deb_url() {
    # Scrape the official Ubuntu setup guide for the current repo-setup .deb URL
    curl -fsSL "https://protonvpn.com/support/official-linux-vpn-ubuntu/" \
        | grep -oP 'https://repo\.protonvpn\.com/debian/dists/stable/[^"]+\.deb' | head -1
}

install_protonvpn() {
    info "Installing ProtonVPN..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Use the official ProtonVPN repo
            local tmpfile
            tmpfile=$(mktemp /tmp/protonvpn-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            local deb_url
            deb_url=$(_protonvpn_get_deb_url)
            if [[ -z "$deb_url" ]]; then
                # Fallback: arch-independent repo-setup package (adds the ProtonVPN apt repo + key)
                deb_url="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
            fi
            if ! wget -qO "$tmpfile" "$deb_url"; then
                error "Failed to download ProtonVPN .deb package."
                return 1
            fi
            verify_download "$tmpfile" "deb" "ProtonVPN" || return 1
            # Install the repo-setup package (adds ProtonVPN apt repo + GPG key)
            sudo apt install -y "$tmpfile"
            sudo apt update
            sudo apt install -y proton-vpn-gnome-desktop
            ;;
        fedora)
            # Official ProtonVPN repo for Fedora
            local fedora_ver
            fedora_ver=$(rpm -E %fedora)
            sudo "$PKG_MGR" install -y \
                "https://repo.protonvpn.com/fedora-${fedora_ver}-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.2-1.noarch.rpm" \
                2>/dev/null || true
            sudo "$PKG_MGR" update -y
            sudo "$PKG_MGR" install -y proton-vpn-gnome-desktop
            ;;
        rhel)
            if has_flatpak; then
                flatpak install -y flathub com.protonvpn.www
            else
                error "ProtonVPN requires Flatpak on RHEL-based systems without the official repo."
                return 1
            fi
            ;;
        arch)
            aur_ensure protonvpn
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.protonvpn.www
            else
                error "ProtonVPN requires Flatpak on openSUSE."
                return 1
            fi
            ;;
    esac
    info "ProtonVPN installed."
}

uninstall_protonvpn() {
    info "Uninstalling ProtonVPN..."
    if flatpak_is_installed "com.protonvpn.www"; then
        flatpak uninstall -y com.protonvpn.www
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y proton-vpn-gnome-desktop protonvpn 2>/dev/null || true
                ;;
            fedora)
                sudo "$PKG_MGR" remove -y proton-vpn-gnome-desktop protonvpn 2>/dev/null || true
                sudo rm -f /etc/yum.repos.d/protonvpn-stable-release.repo
                ;;
            arch)
                aur_remove protonvpn 2>/dev/null || \
                    sudo pacman -Rs --noconfirm protonvpn 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/protonvpn"
}

update_protonvpn() {
    info "Updating ProtonVPN..."
    if flatpak_is_installed "com.protonvpn.www"; then
        flatpak update -y com.protonvpn.www
    else
        case "$DISTRO_FAMILY" in
            debian)   sudo apt-get install -y --only-upgrade proton-vpn-gnome-desktop ;;
            fedora)   sudo "$PKG_MGR" upgrade -y proton-vpn-gnome-desktop ;;
            arch)
                aur_ensure protonvpn
                ;;
        esac
    fi
}

get_version_protonvpn() {
    protonvpn-cli --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    protonvpn --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "com.protonvpn.www" | awk -F'\t' '{print $3}') || \
    echo ""
}
