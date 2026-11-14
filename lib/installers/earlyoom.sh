#!/bin/bash
# earlyoom installer functions
#
# earlyoom: ends the biggest memory hog before the machine freezes, instead of
# waiting for the kernel's slow out-of-memory killer. In the distro
# repositories everywhere (EPEL on RHEL clones); started at boot.

# --- earlyoom ---

check_earlyoom() { _check_standard "" earlyoom ""; }

install_earlyoom() {
    info "Installing earlyoom..."
    ensure_epel
    pkg_install earlyoom || return 1
    svc_enable_now earlyoom || warn "Could not start the earlyoom service; it will start at the next boot."
    info "earlyoom installed."
}

uninstall_earlyoom() {
    info "Uninstalling earlyoom..."
    svc_disable_now earlyoom 2>/dev/null || true
    pkg_remove earlyoom
}

update_earlyoom() {
    info "Updating earlyoom..."
    pkg_upgrade earlyoom
}

get_version_earlyoom() { _ver_from_pkg earlyoom || echo ""; }
