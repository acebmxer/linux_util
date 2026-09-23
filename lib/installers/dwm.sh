#!/bin/bash
# dwm (suckless) window manager installer functions

# --- dwm ---

check_dwm() { _check_standard dwm dwm ""; }

install_dwm() {
    info "Installing dwm..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install dwm ;;
        fedora)      pkg_install dwm ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install dwm 2>/dev/null || {
                warn "dwm not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install dwm ;;
        suse)        pkg_install dwm ;;
    esac
    info "dwm installed. Log out and select dwm from your display manager."
    info "Note: dwm is configured by editing config.h and recompiling — the packaged binary uses upstream defaults."
}

uninstall_dwm() {
    info "Uninstalling dwm..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove dwm ;;
        fedora|rhel) pkg_remove dwm ;;
        arch)        pkg_remove dwm ;;
        suse)        pkg_remove dwm ;;
    esac
}

update_dwm() {
    info "Updating dwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade dwm ;;
        fedora|rhel) pkg_upgrade dwm ;;
        arch)        pkg_upgrade dwm ;;
        suse)        pkg_upgrade dwm ;;
    esac
}

get_version_dwm() {
    _ver_from_cmd dwm -v || _ver_from_pkg dwm || echo ""
}
