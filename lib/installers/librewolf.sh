#!/bin/bash
# LibreWolf privacy-hardened browser installer functions
#
# Arch does NOT go through the AUR: librewolf is packaged in extra, and the old
# librewolf-bin fallback no longer exists in the AUR at all (an AUR search finds
# only add-ons and themes under that prefix, no browser package). Flathub stays
# as the fallback for a derivative whose repos lack it.

# --- LibreWolf ---

check_librewolf() { _check_standard librewolf "" io.gitlab.librewolf-community.librewolf; }

install_librewolf() {
    info "Installing LibreWolf..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official LibreWolf apt repository
            sudo apt install -y wget gnupg lsb-release apt-transport-https ca-certificates
            wget -O- https://deb.librewolf.net/keyring.gpg | \
                sudo gpg --dearmor -o /usr/share/keyrings/librewolf.gpg
            sudo tee /etc/apt/sources.list.d/librewolf.sources <<EOF
Types: deb
URIs: https://deb.librewolf.net
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/librewolf.gpg
EOF
            sudo apt update
            sudo apt install -y librewolf
            ;;
        fedora)
            # COPR repository for LibreWolf on Fedora
            sudo "$PKG_MGR" install -y 'dnf-command(copr)' 2>/dev/null || true
            sudo "$PKG_MGR" copr enable -y bgstack15/librewolf 2>/dev/null || \
                sudo "$PKG_MGR" copr enable -y librewolf/librewolf 2>/dev/null || true
            sudo "$PKG_MGR" install -y librewolf
            ;;
        rhel)
            if has_flatpak; then
                sudo flatpak install -y flathub io.gitlab.librewolf-community.librewolf
            else
                error "LibreWolf requires Flatpak on this RHEL-based system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            if arch_repo_has librewolf && pkg_install librewolf; then
                :
            elif has_flatpak && ensure_flatpak; then
                sudo flatpak install -y flathub io.gitlab.librewolf-community.librewolf
            else
                error "LibreWolf is not in this system's repos and Flatpak is not installed."
                return 1
            fi
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub io.gitlab.librewolf-community.librewolf
            else
                error "LibreWolf requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "LibreWolf installed."
}

uninstall_librewolf() {
    info "Uninstalling LibreWolf..."
    if flatpak_is_installed "io.gitlab.librewolf-community.librewolf"; then
        flatpak uninstall -y io.gitlab.librewolf-community.librewolf
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y librewolf
                sudo rm -f /etc/apt/sources.list.d/librewolf.sources
                sudo rm -f /usr/share/keyrings/librewolf.gpg
                ;;
            fedora)
                sudo "$PKG_MGR" remove -y librewolf
                sudo "$PKG_MGR" copr disable -y bgstack15/librewolf 2>/dev/null || true
                ;;
            arch)
                # librewolf-bin is the dead AUR name, tried only so an install
                # predating the switch to the repo package still uninstalls.
                pkg_check_installed librewolf && \
                    pkg_remove librewolf 2>/dev/null
                pkg_check_installed librewolf-bin && \
                    sudo pacman -Rs --noconfirm librewolf-bin 2>/dev/null
                true
                ;;
        esac
    fi
    rm -rf "$HOME/.librewolf"
}

update_librewolf() {
    info "Updating LibreWolf..."
    if flatpak_is_installed "io.gitlab.librewolf-community.librewolf"; then
        flatpak update -y io.gitlab.librewolf-community.librewolf
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade librewolf ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y librewolf ;;
            arch)        pkg_install librewolf ;;
            suse)        sudo zypper update -y librewolf ;;
        esac
    fi
}

get_version_librewolf() {
    _ver_from_cmd librewolf || _ver_from_flatpak io.gitlab.librewolf-community.librewolf || _ver_from_pkg librewolf || echo ""
}
