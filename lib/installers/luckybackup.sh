#!/bin/bash
# luckyBackup installer functions
#
# Graphical rsync-based backup and sync with profiles and scheduling. The
# distro package on Debian, Ubuntu, Fedora and openSUSE; on Arch from the AUR
# (only with AUR support enabled). Not offered on RHEL clones or Alpine.

# --- luckyBackup ---

check_luckybackup() { _check_standard luckybackup luckybackup ""; }

install_luckybackup() {
    info "Installing luckyBackup..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur luckybackup || return 1
    else
        pkg_install luckybackup || return 1
    fi
    info "luckyBackup installed."
}

# Your profiles and schedules are kept.
uninstall_luckybackup() {
    info "Uninstalling luckyBackup..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        aur_remove luckybackup 2>/dev/null || pkg_remove luckybackup
    else
        pkg_remove luckybackup
    fi
}

update_luckybackup() {
    info "Updating luckyBackup..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur luckybackup
    else
        pkg_upgrade luckybackup
    fi
}

get_version_luckybackup() { _ver_from_pkg luckybackup || echo ""; }
