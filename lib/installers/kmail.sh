#!/bin/bash
# KMail installer functions

# --- KMail (KDE Mail Client) ---
# KMail is part of the KDE Kontact PIM suite.

check_kmail() {
    command -v kmail &>/dev/null || pkg_check_installed kmail
}

install_kmail() {
    info "Installing KMail..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y kmail
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y kmail
            ;;
        arch)
            pkg_install kmail
            ;;
        suse)
            sudo zypper install -y kmail
            ;;
    esac
}

uninstall_kmail() {
    info "Uninstalling KMail..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y kmail
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y kmail
            ;;
        arch)
            pkg_remove kmail
            ;;
        suse)
            sudo zypper remove -y kmail
            ;;
    esac
    rm -rf ~/.local/share/kmail2
    rm -rf ~/.config/kmail2rc
    rm -rf ~/.config/kmail2
}

update_kmail() {
    info "Updating KMail..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y kmail
            ;;
        arch)
            pkg_install kmail
            ;;
        *)
            pkg_upgrade kmail
            ;;
    esac
}

get_version_kmail() {
    kmail --version 2>/dev/null | grep -oP 'kmail\s+\K[0-9]+\.[0-9]+(\.[0-9]+)?' || \
        dpkg -s kmail 2>/dev/null | grep -oP '^Version:\s+\K[0-9]+\.[0-9]+(\.[0-9]+)?' || \
        rpm -q --queryformat '%{VERSION}' kmail 2>/dev/null || echo ""
}
