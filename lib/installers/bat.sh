#!/bin/bash
# bat installer functions
#
# A cat clone with syntax highlighting, line numbers and Git change markers.
# Every supported distro packages it (RHEL clones through EPEL). Debian and
# Ubuntu install the command as batcat, because another package already owned
# the name bat; a bat link to it is made in ~/.local/bin so the usual name works.

# --- bat ---

_BAT_LINK="$HOME/.local/bin/bat"
_BAT_BATCAT=/usr/bin/batcat

check_bat() { _check_standard bat bat ""; }

# Debian/Ubuntu only: point ~/.local/bin/bat at batcat, unless something else
# is already called bat there.
_bat_link_batcat() {
    [[ "$DISTRO_FAMILY" == "debian" ]] || return 0
    [[ -x "$_BAT_BATCAT" ]] || return 0
    [[ -e "$_BAT_LINK" || -L "$_BAT_LINK" ]] && return 0
    mkdir -p "$(dirname "$_BAT_LINK")" && ln -s "$_BAT_BATCAT" "$_BAT_LINK" && \
        info "Linked ${_BAT_LINK} to batcat so the command bat works."
}

install_bat() {
    info "Installing bat..."
    case "$DISTRO_FAMILY" in
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install bat || return 1
            ;;
        debian|fedora|arch|suse)
            pkg_install bat || return 1
            ;;
    esac
    _bat_link_batcat
    info "bat installed."
}

uninstall_bat() {
    info "Uninstalling bat..."
    pkg_remove bat
    # Only the link this installer made; a bat of the user's own is left alone.
    [[ -L "$_BAT_LINK" && "$(readlink "$_BAT_LINK")" == "$_BAT_BATCAT" ]] && rm -f "$_BAT_LINK"
    return 0
}

update_bat() {
    info "Updating bat..."
    pkg_upgrade bat
    _bat_link_batcat
}

get_version_bat() {
    _ver_from_cmd bat || _ver_from_cmd batcat || echo ""
}
