#!/bin/bash
# PCManFM-Qt (LXQt) installer functions

# --- PCManFM-Qt ---

check_pcmanfm_qt() { _check_standard pcmanfm-qt pcmanfm-qt ""; }

install_pcmanfm_qt() {
    info "Installing PCManFM-Qt..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install pcmanfm-qt ;;
        fedora)      pkg_install pcmanfm-qt ;;
        arch)        pkg_install pcmanfm-qt ;;
        suse)        pkg_install pcmanfm-qt ;;
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
        debian)      pkg_remove pcmanfm-qt ;;
        fedora)      pkg_remove pcmanfm-qt ;;
        arch)        pkg_remove pcmanfm-qt ;;
        suse)        pkg_remove pcmanfm-qt ;;
    esac
}

update_pcmanfm_qt() {
    info "Updating PCManFM-Qt..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade pcmanfm-qt ;;
        fedora)      pkg_upgrade pcmanfm-qt ;;
        arch)        pkg_upgrade pcmanfm-qt ;;
        suse)        pkg_upgrade pcmanfm-qt ;;
    esac
}

get_version_pcmanfm_qt() {
    _ver_from_pkg pcmanfm-qt || echo ""
}
