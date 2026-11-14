#!/bin/bash
# PHP installer functions
#
# The PHP command-line interpreter, from the distro's own packages: php-cli on
# Debian, Ubuntu, Fedora and RHEL clones; php on Arch; php8 on openSUSE; php84
# on Alpine. Versions follow the distro. Not a web
# server module: add the one you need (php-fpm, mod_php) yourself.

# --- PHP ---

_php_pkg() {
    case "$DISTRO_FAMILY" in
        arch)   echo php ;;
        suse)   echo php8 ;;
        alpine) echo php84 ;;
        *)      echo php-cli ;;
    esac
}

check_php() { _check_standard php "$(_php_pkg)" ""; }

install_php() {
    info "Installing PHP..."
    ensure_epel
    pkg_install "$(_php_pkg)" || return 1
    info "PHP installed."
}

uninstall_php() {
    info "Uninstalling PHP..."
    pkg_remove "$(_php_pkg)"
}

update_php() {
    info "Updating PHP..."
    pkg_upgrade "$(_php_pkg)"
}

get_version_php() { _ver_from_pkg "$(_php_pkg)" || _ver_from_cmd php || echo ""; }
