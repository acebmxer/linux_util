#!/bin/bash
# rsnapshot installer functions
#
# Scheduled, space-saving snapshots of folders using rsync and hard links. The
# distro package everywhere (EPEL on RHEL clones). It is set up in
# /etc/rsnapshot.conf and a cron or timer entry, neither of which this
# creates.

# --- rsnapshot ---

check_rsnapshot() { _check_standard rsnapshot rsnapshot ""; }

install_rsnapshot() {
    info "Installing rsnapshot..."
    ensure_epel
    pkg_install rsnapshot || return 1
    info "rsnapshot installed."
}

# Your /etc/rsnapshot.conf is kept.
uninstall_rsnapshot() {
    info "Uninstalling rsnapshot..."
    pkg_remove rsnapshot
}

update_rsnapshot() {
    info "Updating rsnapshot..."
    pkg_upgrade rsnapshot
}

get_version_rsnapshot() { _ver_from_pkg rsnapshot || echo ""; }
