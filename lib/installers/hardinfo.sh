#!/bin/bash
# HardInfo installer functions
#
# System profiler and benchmark window (CPU, memory, storage, sensors, network).
# The maintained fork is HardInfo2 (package hardinfo2); Ubuntu 22.04 only has
# the old hardinfo, which is used there. Debian, Ubuntu, Fedora, Arch and
# openSUSE use their repositories, Rocky/Alma use EPEL. Alpine has no package,
# so it is not offered there.

# --- HardInfo ---

# The package this system's repositories carry: hardinfo2 first, hardinfo next.
# Prints nothing when neither is available.
_hardinfo_package() {
    local p
    for p in hardinfo2 hardinfo; do
        pkg_in_repo "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

# The package that is installed right now, or nothing.
_hardinfo_installed_package() {
    local p
    for p in hardinfo2 hardinfo; do
        pkg_check_installed "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

check_hardinfo() { _hardinfo_installed_package >/dev/null; }

install_hardinfo() {
    info "Installing HardInfo..."
    pkg_refresh
    ensure_epel
    local pkg
    pkg=$(_hardinfo_package) || {
        error "Neither hardinfo2 nor hardinfo is in the ${DISTRO_NAME:-system} repositories."
        return 1
    }
    pkg_install "$pkg" || return 1
    info "HardInfo installed (package ${pkg})."
}

uninstall_hardinfo() {
    info "Uninstalling HardInfo..."
    local pkg
    pkg=$(_hardinfo_installed_package) || return 0
    pkg_remove "$pkg"
}

update_hardinfo() {
    info "Updating HardInfo..."
    local pkg
    pkg=$(_hardinfo_installed_package) || return 1
    pkg_upgrade "$pkg"
}

get_version_hardinfo() {
    local pkg
    pkg=$(_hardinfo_installed_package) || { echo ""; return 0; }
    _ver_from_pkg "$pkg" || echo ""
}
