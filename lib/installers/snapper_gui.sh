#!/bin/bash
# Snapper GUI installer functions (Debian/Ubuntu and Arch)
#
# Arch has no non-AUR path for this one, and unlike the other AUR-only entries
# that is not going to change: upstream (ricardomv/snapper-gui) is a frozen
# Python/GTK source tree with no releases and no binary artifacts, so there is
# nothing to download and install directly. snapper-gui-git builds it from the
# git checkout, which is the only sane way to install it.
#
# The name matters: the plain `snapper-gui` package this used to ask for does
# not exist in the AUR or in any Arch repo, so every Arch install failed. Only
# snapper-gui-git exists (51 votes, last touched 2024-03-26). Its dependencies
# are all ordinary current packages -- python3, gtk3, python-dbus,
# python-gobject, python-setuptools, gtksourceview3, snapper -- so the build
# itself is sound. Debian/Ubuntu do carry a real `snapper-gui` package.

# --- Snapper GUI ---

check_snapper_gui() {
    _have_cmd snapper-gui
}

install_snapper_gui() {
    echo "Installing Snapper GUI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y snapper-gui || return 1
            ;;
        arch)
            repo_or_aur snapper-gui-git || return 1
            ;;
        *)
            warn "Snapper GUI is not available for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Arch/Manjaro."
            return 1
            ;;
    esac
    echo "Snapper GUI installed successfully."
}

uninstall_snapper_gui() {
    echo "Uninstalling Snapper GUI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y snapper-gui
            sudo apt autoclean
            ;;
        arch)
            # Plain snapper-gui is tried too: it never existed as a package,
            # but a user who installed one by hand should still be cleaned up.
            sudo pacman -Rs --noconfirm snapper-gui-git 2>/dev/null || \
            sudo pacman -Rs --noconfirm snapper-gui 2>/dev/null || true
            ;;
    esac
}

update_snapper_gui() {
    echo "Updating Snapper GUI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade snapper-gui
            ;;
        arch)
            # A -git package only moves when it is rebuilt, which pkg_upgrade
            # cannot do -- that needs the AUR helper.
            repo_or_aur snapper-gui-git
            ;;
    esac
}

get_version_snapper_gui() {
    _ver_from_pkg snapper-gui || _ver_from_pkg snapper-gui-git || echo ""
}
