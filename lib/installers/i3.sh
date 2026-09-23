#!/bin/bash
# i3 window manager installer functions

# --- i3 ---

check_i3() { _check_standard i3 i3 ""; }

install_i3() {
    info "Installing i3..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install i3 ;;
        fedora)      pkg_install i3 ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install i3 2>/dev/null || {
                warn "i3 not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install i3-wm ;;
        suse)        pkg_install i3 ;;
    esac
    info "i3 installed. Log out and select i3 from your display manager."
}

uninstall_i3() {
    info "Uninstalling i3..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove i3 ;;
        fedora|rhel) pkg_remove i3 ;;
        arch)        pkg_remove i3-wm ;;
        suse)        pkg_remove i3 ;;
    esac
}

update_i3() {
    info "Updating i3..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade i3 ;;
        fedora|rhel) pkg_upgrade i3 ;;
        arch)        pkg_upgrade i3-wm ;;
        suse)        pkg_upgrade i3 ;;
    esac
}

get_version_i3() {
    _ver_from_cmd i3 --version || _ver_from_pkg i3 || _ver_from_pkg i3-wm || echo ""
}
