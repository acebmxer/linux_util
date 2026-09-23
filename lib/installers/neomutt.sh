#!/bin/bash
# NeoMutt installer functions

# --- NeoMutt ---
# Terminal mail client; a maintained fork of Mutt. In the official repos of
# every supported family except RHEL, where it comes from EPEL.

check_neomutt() { _check_standard neomutt neomutt ""; }

install_neomutt() {
    info "Installing NeoMutt..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_install neomutt
            ;;
        fedora)
            pkg_install neomutt
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install neomutt
            ;;
        arch)
            pkg_install neomutt
            ;;
        suse)
            pkg_install neomutt
            ;;
    esac
    info "NeoMutt installed. It ships no default account config — create ~/.config/neomutt/neomuttrc before first use."
}

uninstall_neomutt() {
    info "Uninstalling NeoMutt..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove neomutt
            ;;
        fedora|rhel)
            pkg_remove neomutt
            ;;
        arch)
            pkg_remove neomutt
            ;;
        suse)
            pkg_remove neomutt
            ;;
    esac
    # Deliberately not removing ~/.config/neomutt, ~/.neomuttrc or ~/.mail:
    # NeoMutt config is hand-written and local Maildirs may hold the only copy
    # of the user's mail.
    info "Left ~/.config/neomutt and any local Maildirs in place — remove them by hand if you want them gone."
}

update_neomutt() {
    info "Updating NeoMutt..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade neomutt
            ;;
        arch)
            pkg_install neomutt
            ;;
        *)
            pkg_upgrade neomutt
            ;;
    esac
}

get_version_neomutt() {
    # NeoMutt versions are dates ("20260616"), not semver, so _ver_from_cmd's
    # X.Y.Z pattern never matches — read it from the package manager instead.
    _ver_from_pkg neomutt || echo ""
}
