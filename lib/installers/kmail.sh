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
            pkg_install kmail
            ;;
        fedora|rhel)
            pkg_install kmail
            ;;
        arch)
            pkg_install kmail
            ;;
        suse)
            pkg_install kmail
            ;;
    esac
}

uninstall_kmail() {
    info "Uninstalling KMail..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove kmail
            ;;
        fedora|rhel)
            pkg_remove kmail
            ;;
        arch)
            pkg_remove kmail
            ;;
        suse)
            pkg_remove kmail
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
            pkg_upgrade kmail
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
