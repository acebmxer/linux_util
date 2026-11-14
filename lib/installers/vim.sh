#!/bin/bash
# Vim installer functions
#
# The classic modal editor. In every supported distro's repositories: vim on
# Debian, Ubuntu, Arch, openSUSE and Alpine; vim-enhanced on Fedora and RHEL
# clones (their plain vim package is the minimal build).

# --- Vim ---

_vim_pkg() {
    case "$DISTRO_FAMILY" in
        fedora|rhel) echo vim-enhanced ;;
        *)           echo vim ;;
    esac
}

check_vim() { _check_standard vim "$(_vim_pkg)" ""; }

install_vim() {
    info "Installing Vim..."
    pkg_install "$(_vim_pkg)" || return 1
    info "Vim installed."
}

uninstall_vim() {
    info "Uninstalling Vim..."
    pkg_remove "$(_vim_pkg)"
}

update_vim() {
    info "Updating Vim..."
    pkg_upgrade "$(_vim_pkg)"
}

get_version_vim() { _ver_from_pkg "$(_vim_pkg)" || _ver_from_cmd vim || echo ""; }
