#!/bin/bash
# TLP installer functions
#
# TLP: laptop battery and power tuning that works with its defaults and starts
# at boot. In the distro repositories everywhere; on RHEL clones from EPEL
# (EPEL 10 does not carry it, so it is not offered on Rocky/Alma 10).
# TLP replaces power-profiles-daemon and must not run beside auto-cpufreq.

# --- TLP ---

check_tlp() { _check_standard "" tlp ""; }

install_tlp() {
    info "Installing TLP..."
    if _have_cmd auto-cpufreq || [[ -e /opt/auto-cpufreq/current ]]; then
        error "auto-cpufreq is installed, and the two fight over the same CPU settings. Uninstall auto-cpufreq first."
        return 1
    fi
    if pkg_check_installed power-profiles-daemon; then
        warn "TLP replaces power-profiles-daemon (the desktop's power-mode switch); the package manager will remove it."
    fi
    ensure_epel
    pkg_install tlp || return 1
    svc_enable_now tlp || warn "Could not start the tlp service; it will start at the next boot."
    info "TLP installed. Show its state with: sudo tlp-stat -s"
}

uninstall_tlp() {
    info "Uninstalling TLP..."
    svc_disable_now tlp 2>/dev/null || true
    pkg_remove tlp
}

update_tlp() {
    info "Updating TLP..."
    pkg_upgrade tlp
}

get_version_tlp() { _ver_from_pkg tlp || echo ""; }
