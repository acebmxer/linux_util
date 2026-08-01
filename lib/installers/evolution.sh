#!/bin/bash
# Evolution installer functions

# --- Evolution (GNOME Mail / PIM Suite) ---
# Evolution is GNOME's personal information manager: mail, calendar, contacts,
# and tasks. Exchange (EWS) support lives in a separate evolution-ews package on
# every distro, so it is installed alongside but tolerated as optional — some
# repos ship it only in an extras channel.

check_evolution() { _check_standard evolution evolution ""; }

install_evolution() {
    info "Installing Evolution..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y evolution
            sudo apt install -y evolution-ews 2>/dev/null || \
                warn "evolution-ews unavailable; Exchange (EWS) accounts will not be offered."
            ;;
        fedora)
            sudo "$PKG_MGR" install -y evolution
            sudo "$PKG_MGR" install -y evolution-ews 2>/dev/null || \
                warn "evolution-ews unavailable; Exchange (EWS) accounts will not be offered."
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y evolution
            sudo "$PKG_MGR" install -y evolution-ews 2>/dev/null || \
                warn "evolution-ews unavailable; Exchange (EWS) accounts will not be offered."
            ;;
        arch)
            pkg_install evolution
            pkg_install evolution-ews 2>/dev/null || \
                warn "evolution-ews unavailable; Exchange (EWS) accounts will not be offered."
            ;;
        suse)
            sudo zypper install -y evolution
            sudo zypper install -y evolution-ews 2>/dev/null || \
                warn "evolution-ews unavailable; Exchange (EWS) accounts will not be offered."
            ;;
    esac
    info "Evolution installed."
}

uninstall_evolution() {
    info "Uninstalling Evolution..."
    # evolution-ews is removed separately and non-fatally: it may never have
    # been installed, and bundling it into the same command would abort the
    # whole removal on apt/pacman/zypper.
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y evolution-ews 2>/dev/null || true
            sudo apt purge --autoremove -y evolution
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y evolution-ews 2>/dev/null || true
            sudo "$PKG_MGR" remove -y evolution
            ;;
        arch)
            pkg_check_installed evolution-ews && pkg_remove evolution-ews
            pkg_remove evolution
            ;;
        suse)
            sudo zypper remove -y evolution-ews 2>/dev/null || true
            sudo zypper remove -y evolution
            ;;
    esac
    rm -rf "$HOME/.config/evolution"
    rm -rf "$HOME/.local/share/evolution"
    rm -rf "$HOME/.cache/evolution"
}

update_evolution() {
    info "Updating Evolution..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade evolution
            ;;
        arch)
            pkg_install evolution
            ;;
        *)
            pkg_upgrade evolution
            ;;
    esac
}

get_version_evolution() {
    # Package first: evolution is a GApplication, and shelling out to it from
    # the TUI risks activating a running instance rather than just printing.
    _ver_from_pkg evolution || echo ""
}
