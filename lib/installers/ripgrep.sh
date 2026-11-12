#!/bin/bash
# ripgrep installer functions
#
# rg: searches a directory tree for a pattern, much faster than grep -r, and
# skips files listed in .gitignore. Every supported distro packages it (RHEL
# clones through EPEL).

# --- ripgrep ---

check_ripgrep() { _check_standard rg ripgrep ""; }

install_ripgrep() {
    info "Installing ripgrep..."
    [[ "$DISTRO_FAMILY" == "rhel" ]] && { pkg_install epel-release 2>/dev/null || true; }
    pkg_install ripgrep || return 1
    info "ripgrep installed."
}

uninstall_ripgrep() {
    info "Uninstalling ripgrep..."
    pkg_remove ripgrep
}

update_ripgrep() {
    info "Updating ripgrep..."
    pkg_upgrade ripgrep
}

get_version_ripgrep() {
    _ver_from_cmd rg || echo ""
}
