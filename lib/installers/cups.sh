#!/bin/bash
# CUPS installer functions
#
# CUPS: the printing system. Installs the print server and starts it at boot;
# printers are then added at http://localhost:631 or in the desktop's printer
# settings. In every supported distro's repositories, Alpine included (its
# OpenRC service is called cupsd).

# --- CUPS ---

# The service is named cups on systemd and cupsd on Alpine's OpenRC.
_cups_service() { [[ "${DISTRO_FAMILY:-}" == "alpine" ]] && echo cupsd || echo cups; }

check_cups() { _check_standard "" cups ""; }

install_cups() {
    info "Installing CUPS..."
    pkg_install cups || return 1
    svc_enable_now "$(_cups_service)" || warn "Could not start the CUPS service; it will start at the next boot."
    info "CUPS installed. Add a printer at http://localhost:631"
}

uninstall_cups() {
    info "Uninstalling CUPS..."
    svc_disable_now "$(_cups_service)" 2>/dev/null || true
    pkg_remove cups
}

update_cups() {
    info "Updating CUPS..."
    pkg_upgrade cups
}

get_version_cups() { _ver_from_pkg cups || echo ""; }
