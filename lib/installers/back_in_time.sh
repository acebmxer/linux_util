#!/bin/bash
# Back In Time installer functions
#
# Simple snapshot backups of your files using rsync, with a Qt window. The
# distro package on Debian, Ubuntu, Fedora, RHEL clones 8 and 9 (EPEL) and
# openSUSE; on Arch from the AUR (only with AUR support enabled). Not offered
# on Rocky/Alma 10 or Alpine.

# --- Back In Time ---

check_back_in_time() { _check_standard backintime-qt backintime-qt "" backintime; }

install_back_in_time() {
    info "Installing Back In Time..."
    ensure_epel
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur backintime || return 1
    else
        pkg_install backintime-qt || return 1
    fi
    info "Back In Time installed."
}

# Your snapshots and profiles are kept.
uninstall_back_in_time() {
    info "Uninstalling Back In Time..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        aur_remove backintime 2>/dev/null || pkg_remove backintime
    else
        pkg_remove backintime-qt
        # The command-line part comes along as a dependency: backintime-common, or
        # plain "backintime" on openSUSE.
        local dep
        for dep in backintime-common backintime; do
            if pkg_check_installed "$dep"; then pkg_remove "$dep"; fi
        done
    fi
}

update_back_in_time() {
    info "Updating Back In Time..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur backintime
    else
        pkg_upgrade backintime-qt
    fi
}

get_version_back_in_time() { _ver_from_pkg backintime-qt || _ver_from_pkg backintime || echo ""; }
