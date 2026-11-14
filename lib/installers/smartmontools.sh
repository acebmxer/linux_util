#!/bin/bash
# smartmontools installer functions
#
# smartctl reads a drive's SMART health data; smartd watches it in the
# background. The package is in every supported distro's own repositories.
# Services are left as the package sets them: Debian starts smartd by itself,
# the others leave it off until you configure it.

# --- smartmontools ---

check_smartmontools() { _check_standard "" smartmontools ""; }

install_smartmontools() {
    info "Installing smartmontools..."
    pkg_install smartmontools || return 1
    info "smartmontools installed. Check a drive with: sudo smartctl -a /dev/sda"
}

uninstall_smartmontools() {
    info "Uninstalling smartmontools..."
    pkg_remove smartmontools
}

update_smartmontools() {
    info "Updating smartmontools..."
    pkg_upgrade smartmontools
}

get_version_smartmontools() { _ver_from_pkg smartmontools || echo ""; }
