#!/bin/bash
# Python installer functions
#
# The distro's own Python 3 with pip and virtual environments: python3,
# python3-pip, python3-venv and python3-dev on Debian and Ubuntu; python3,
# python3-pip and python3-devel on Fedora, RHEL clones and openSUSE; python and
# python-pip on Arch; python3, py3-pip and python3-dev on Alpine. The version is
# whatever the distro ships; pyenv (its own entry) installs others.

# --- Python ---

_python_pkgs() {
    case "$DISTRO_FAMILY" in
        debian)      echo "python3 python3-pip python3-venv python3-dev" ;;
        fedora|rhel) echo "python3 python3-pip python3-devel" ;;
        suse)        echo "python3 python3-pip python3-devel" ;;
        arch)        echo "python python-pip" ;;
        alpine)      echo "python3 py3-pip python3-dev" ;;
    esac
}

check_python() { _have_cmd python3 && { _have_cmd pip3 || _have_cmd pip || python3 -m pip --version &>/dev/null; }; }

install_python() {
    info "Installing Python..."
    local pkgs
    pkgs=$(_python_pkgs)
    # shellcheck disable=SC2086  # the list is intentionally split
    pkg_install $pkgs || return 1
    info "Python installed."
}

# Only the pip, venv and header packages go: python3 itself is needed by the
# system on most distros, so removing it would take the desktop with it.
uninstall_python() {
    info "Uninstalling Python's pip, venv and development packages..."
    local pkgs
    pkgs=$(_python_pkgs)
    # shellcheck disable=SC2086
    pkg_remove ${pkgs#* }
}

update_python() {
    info "Updating Python..."
    local pkgs
    pkgs=$(_python_pkgs)
    # shellcheck disable=SC2086
    pkg_upgrade $pkgs
}

get_version_python() { _ver_from_cmd python3 || echo ""; }
