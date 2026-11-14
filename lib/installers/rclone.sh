#!/bin/bash
# rclone installer functions
#
# Command-line tool that copies and syncs files to and from dozens of cloud
# storage services. The distro package (EPEL on RHEL clones 9 and newer); not
# offered on Rocky/Alma 8, which have none.

# --- rclone ---

check_rclone() { _check_standard rclone rclone ""; }

install_rclone() {
    info "Installing rclone..."
    ensure_epel
    pkg_install rclone || return 1
    info "rclone installed."
}

# Your rclone.conf (remotes and tokens) is kept.
uninstall_rclone() {
    info "Uninstalling rclone..."
    pkg_remove rclone
}

update_rclone() {
    info "Updating rclone..."
    pkg_upgrade rclone
}

get_version_rclone() { _ver_from_pkg rclone || echo ""; }
