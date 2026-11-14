#!/bin/bash
# nvtop installer functions
#
# nvtop: htop-style monitor for GPUs (NVIDIA, AMD, Intel). In the distro
# repositories everywhere except Alpine; on RHEL clones it comes from EPEL.
# The NVIDIA Drivers installer also installs this package.

# --- nvtop ---

check_nvtop() { _check_standard nvtop nvtop ""; }

install_nvtop() {
    info "Installing nvtop..."
    ensure_epel
    pkg_install nvtop || return 1
    info "nvtop installed."
}

uninstall_nvtop() {
    info "Uninstalling nvtop..."
    pkg_remove nvtop
}

update_nvtop() {
    info "Updating nvtop..."
    pkg_upgrade nvtop
}

get_version_nvtop() { _ver_from_pkg nvtop || _ver_from_cmd nvtop || echo ""; }
