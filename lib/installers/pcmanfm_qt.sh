#!/bin/bash
# PCManFM-Qt (LXQt) installer functions

# --- PCManFM-Qt ---

check_pcmanfm_qt() { _check_standard pcmanfm-qt pcmanfm-qt ""; }

install_pcmanfm_qt() {
    info "Installing PCManFM-Qt..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y pcmanfm-qt ;;
        fedora)      sudo "$PKG_MGR" install -y pcmanfm-qt ;;
        arch)        sudo pacman -S --noconfirm pcmanfm-qt ;;
        suse)        sudo zypper install -y pcmanfm-qt ;;
        rhel)
            warn "pcmanfm-qt is not packaged for RHEL-based distros."
            return 1
            ;;
    esac
    info "PCManFM-Qt installed."
}

uninstall_pcmanfm_qt() {
    info "Uninstalling PCManFM-Qt..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y pcmanfm-qt ;;
        fedora)      sudo "$PKG_MGR" remove -y pcmanfm-qt ;;
        arch)        sudo pacman -Rs --noconfirm pcmanfm-qt ;;
        suse)        sudo zypper remove -y pcmanfm-qt ;;
    esac
}

update_pcmanfm_qt() {
    info "Updating PCManFM-Qt..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade pcmanfm-qt ;;
        fedora)      sudo "$PKG_MGR" upgrade -y pcmanfm-qt ;;
        arch)        sudo pacman -S --noconfirm pcmanfm-qt ;;
        suse)        sudo zypper update -y pcmanfm-qt ;;
    esac
}

get_version_pcmanfm_qt() {
    _ver_from_pkg pcmanfm-qt || echo ""
}
