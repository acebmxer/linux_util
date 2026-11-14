#!/bin/bash
# restic installer functions
#
# Fast, encrypted, deduplicating command-line backup to a local folder, SFTP,
# S3 and many cloud stores. The distro package (EPEL on RHEL clones 9 and
# newer); not offered on Rocky/Alma 8, which have none.

# --- restic ---

check_restic() { _check_standard restic restic ""; }

install_restic() {
    info "Installing restic..."
    ensure_epel
    pkg_install restic || return 1
    info "restic installed."
}

# Your repositories and passwords are not touched.
uninstall_restic() {
    info "Uninstalling restic..."
    pkg_remove restic
}

update_restic() {
    info "Updating restic..."
    pkg_upgrade restic
}

get_version_restic() { _ver_from_pkg restic || echo ""; }
