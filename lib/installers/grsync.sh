#!/bin/bash
# Grsync installer functions
#
# Graphical front-end for rsync: sync and back up folders with presets. The
# distro package (EPEL on RHEL clones); not offered on Alpine.

# --- Grsync ---

check_grsync() { _check_standard grsync grsync ""; }

install_grsync() {
    info "Installing Grsync..."
    ensure_epel
    pkg_install grsync || return 1
    info "Grsync installed."
}

# Your saved sessions are kept.
uninstall_grsync() {
    info "Uninstalling Grsync..."
    pkg_remove grsync
}

update_grsync() {
    info "Updating Grsync..."
    pkg_upgrade grsync
}

get_version_grsync() { _ver_from_pkg grsync || echo ""; }
