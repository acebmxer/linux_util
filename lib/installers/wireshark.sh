#!/bin/bash
# Wireshark installer functions
#
# Packet analyser. Debian/Ubuntu: wireshark, with the question about letting
# non-root users capture answered yes; Fedora, RHEL clones, Arch: the Qt
# window and the command-line tools; openSUSE and Alpine: wireshark. The
# installing user joins the wireshark group so they can capture without root;
# that applies after logging out and in.

# --- Wireshark ---

_ws_pkgs() {
    case "$DISTRO_FAMILY" in
        fedora|rhel) echo "wireshark wireshark-cli" ;;
        arch)        echo "wireshark-qt wireshark-cli" ;;
        *)           echo "wireshark" ;;
    esac
}

check_wireshark() { _check_standard wireshark "$(_ws_pkgs | cut -d" " -f1)" ""; }

install_wireshark() {
    info "Installing Wireshark..."
    local pkgs
    pkgs=$(_ws_pkgs)
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        # Without this the package asks on a terminal; yes lets the wireshark
        # group capture without root.
        echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections 2>/dev/null || true
    fi
    # shellcheck disable=SC2086  # the list is intentionally split
    pkg_install $pkgs || return 1
    if getent group wireshark >/dev/null 2>&1; then
        sudo usermod -aG wireshark "${SUDO_USER:-$USER}" 2>/dev/null \
            && info "Added ${SUDO_USER:-$USER} to the wireshark group; log out and back in to capture without root."
    fi
    info "Wireshark installed."
}

uninstall_wireshark() {
    info "Uninstalling Wireshark..."
    local pkgs
    pkgs=$(_ws_pkgs)
    # shellcheck disable=SC2086
    pkg_remove $pkgs
}

update_wireshark() {
    info "Updating Wireshark..."
    local pkgs
    pkgs=$(_ws_pkgs)
    # shellcheck disable=SC2086
    pkg_upgrade $pkgs
}

get_version_wireshark() { _ver_from_pkg "$(_ws_pkgs | cut -d" " -f1)" || echo ""; }
