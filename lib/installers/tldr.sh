#!/bin/bash
# tldr installer functions
#
# Short, example-first help pages for shell commands: `tldr tar`. Installs the
# command-line client the distro carries, in this order: tealdeer (Debian 13 and
# 12, Ubuntu 26.04, Arch, openSUSE Tumbleweed), tlrc (openSUSE Leap), tldr (the
# Python client: Fedora, Rocky/Alma through EPEL, Ubuntu 22.04). All of them
# provide the `tldr` command. Alpine has none, so it is not offered there.

# --- tldr ---

_TLDR_CANDIDATES=(tealdeer tlrc tldr)

# The client package this system's repositories carry; prints nothing if none.
_tldr_package() {
    local p
    for p in "${_TLDR_CANDIDATES[@]}"; do
        pkg_in_repo "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

# The client package that is installed right now.
_tldr_installed_package() {
    local p
    for p in "${_TLDR_CANDIDATES[@]}"; do
        pkg_check_installed "$p" && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

check_tldr() { _tldr_installed_package >/dev/null; }

install_tldr() {
    info "Installing tldr..."
    pkg_refresh
    ensure_epel
    local pkg
    pkg=$(_tldr_package) || { error "No tldr client is in the ${DISTRO_NAME:-system} repositories."; return 1; }
    pkg_install "$pkg" || return 1
    info "tldr installed (package ${pkg}). Try: tldr tar"
}

uninstall_tldr() {
    info "Uninstalling tldr..."
    local pkg
    pkg=$(_tldr_installed_package) || return 0
    pkg_remove "$pkg"
}

update_tldr() {
    info "Updating tldr..."
    local pkg
    pkg=$(_tldr_installed_package) || return 1
    pkg_upgrade "$pkg"
}

get_version_tldr() {
    local pkg
    pkg=$(_tldr_installed_package) || { echo ""; return 0; }
    _ver_from_pkg "$pkg" || echo ""
}
