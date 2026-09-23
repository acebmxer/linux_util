#!/bin/bash
# bspwm window manager installer functions

# --- bspwm ---

check_bspwm() { _check_standard bspwm bspwm ""; }

install_bspwm() {
    info "Installing bspwm..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install bspwm sxhkd ;;
        fedora)      pkg_install bspwm sxhkd ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install bspwm sxhkd 2>/dev/null || {
                warn "bspwm not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install bspwm sxhkd ;;
        suse)        pkg_install bspwm sxhkd ;;
    esac
    info "bspwm installed (with sxhkd for keybindings). Log out and select bspwm from your display manager."
}

uninstall_bspwm() {
    info "Uninstalling bspwm..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove bspwm sxhkd ;;
        fedora|rhel) pkg_remove bspwm sxhkd ;;
        arch)        pkg_remove bspwm sxhkd ;;
        suse)        pkg_remove bspwm sxhkd ;;
    esac
}

update_bspwm() {
    info "Updating bspwm..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade bspwm sxhkd ;;
        fedora|rhel) pkg_upgrade bspwm sxhkd ;;
        arch)        pkg_upgrade bspwm sxhkd ;;
        suse)        pkg_upgrade bspwm sxhkd ;;
    esac
}

get_version_bspwm() {
    _ver_from_cmd bspwm -v || _ver_from_pkg bspwm || echo ""
}
