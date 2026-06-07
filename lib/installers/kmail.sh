#!/bin/bash
# KMail installer functions

# --- KMail (KDE Mail Client) ---
# KMail is part of the KDE Kontact PIM suite.

check_kmail() { _check_standard kmail kmail ""; }

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
            sudo apt install -y --only-upgrade kmail
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
    # Do NOT call kmail --version — KDE apps may launch a full window.
    _ver_from_pkg kmail || echo ""
}
