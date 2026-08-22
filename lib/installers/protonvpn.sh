#!/bin/bash
# ProtonVPN installer functions
#
# Package name differs by family: Proton's own apt/dnf repos ship
# proton-vpn-gnome-desktop, while Arch packages the same app in extra as
# proton-vpn-gtk-app (binary /usr/bin/protonvpn-app, pulling proton-vpn-daemon
# and the python-proton-* stack as real dependencies).
#
# Arch does NOT go through the AUR. This used to call repo_or_aur protonvpn,
# but the `protonvpn` AUR package no longer exists — it is gone from the AUR
# entirely, and an AUR search turns up only unrelated community forks such as
# protonvpn-cli-community. So on any system where pacman could not resolve the
# name, the fallback cloned aur.archlinux.org/protonvpn.git and failed. The
# official extra build is the correct source and needs no AUR helper.

# --- ProtonVPN ---

check_protonvpn() {
    _have_cmd protonvpn-cli || \
        _have_cmd protonvpn || \
        _have_cmd protonvpn-app || \
        pkg_check_installed proton-vpn-gnome-desktop || \
        pkg_check_installed proton-vpn-gtk-app || \
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
                sudo flatpak install -y flathub com.protonvpn.www
            else
                error "ProtonVPN requires Flatpak on RHEL-based systems without the official repo."
                return 1
            fi
            ;;
        arch)
            pkg_install proton-vpn-gtk-app || {
                error "Failed to install proton-vpn-gtk-app from the official repos."
                return 1
            }
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub com.protonvpn.www
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
                # protonvpn is the dead AUR name, kept here only so an install
                # predating the switch to the repo package still uninstalls.
                pkg_check_installed proton-vpn-gtk-app && \
                    pkg_remove proton-vpn-gtk-app 2>/dev/null
                pkg_check_installed protonvpn && \
                    sudo pacman -Rs --noconfirm protonvpn 2>/dev/null
                true
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
            arch)    pkg_install proton-vpn-gtk-app ;;
        esac
    fi
}

get_version_protonvpn() {
    # Arch's package is queried by name first: proton-vpn-gtk-app installs
    # protonvpn-app, which has no --version flag of its own.
    if pkg_check_installed proton-vpn-gtk-app; then
        pkg_get_version proton-vpn-gtk-app | sed 's/-[0-9]*$//'
        return
    fi
    _run_native protonvpn-cli --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    _run_native protonvpn --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "com.protonvpn.www" | awk -F'\t' '{print $3}') || \
    echo ""
}
