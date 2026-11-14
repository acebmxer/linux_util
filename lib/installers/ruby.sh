#!/bin/bash
# Ruby installer functions
#
# Ruby with the headers gems need to build native extensions, from the distro's
# own packages: ruby-full on Debian and Ubuntu; ruby and ruby-devel on Fedora,
# RHEL clones and openSUSE; ruby on Arch; ruby and ruby-dev on Alpine.

# --- Ruby ---

_ruby_pkgs() {
    case "$DISTRO_FAMILY" in
        debian) echo ruby-full ;;
        arch)   echo ruby ;;
        alpine) echo "ruby ruby-dev" ;;
        *)      echo "ruby ruby-devel" ;;
    esac
}

check_ruby() { _check_standard ruby "$(_ruby_pkgs | cut -d' ' -f1)" ""; }

install_ruby() {
    info "Installing Ruby..."
    local pkgs
    pkgs=$(_ruby_pkgs)
    # shellcheck disable=SC2086  # the list is intentionally split
    pkg_install $pkgs || return 1
    info "Ruby installed."
}

uninstall_ruby() {
    info "Uninstalling Ruby..."
    local pkgs
    pkgs=$(_ruby_pkgs)
    # shellcheck disable=SC2086
    pkg_remove $pkgs
}

update_ruby() {
    info "Updating Ruby..."
    local pkgs
    pkgs=$(_ruby_pkgs)
    # shellcheck disable=SC2086
    pkg_upgrade $pkgs
}

get_version_ruby() { _ver_from_pkg "$(_ruby_pkgs | cut -d' ' -f1)" || _ver_from_cmd ruby || echo ""; }
