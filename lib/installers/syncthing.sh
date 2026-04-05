#!/bin/bash
# Syncthing installer functions

# --- Syncthing ---

check_syncthing() { _check_standard syncthing syncthing ""; }

install_syncthing() {
    echo "Installing Syncthing..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo \
                "https://syncthing.net/release-key.gpg" \
                "/etc/apt/keyrings/syncthing-archive-keyring.gpg" \
                "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" \
                "/etc/apt/sources.list.d/syncthing.list"
            sudo apt install -y syncthing
            ;;
        fedora)
            # Syncthing is included in official Fedora repos by default
            sudo "$PKG_MGR" install -y syncthing
            ;;
        rhel)
            # Syncthing is in EPEL, not the base RHEL/Alma/Rocky repos
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y syncthing
            ;;
        arch)
            # Syncthing is available in the community repository
            sudo pacman -S --noconfirm syncthing
            ;;
        suse)
            # Install from official repository
            sudo zypper install -y syncthing
            ;;
    esac

    # Enable and start the user service (all distros)
    systemctl --user enable syncthing.service
    systemctl --user start syncthing.service

    echo ""
    echo "Syncthing installed successfully!"
    echo "Service has been enabled and started."
    echo "Access the web GUI at: http://127.0.0.1:8384"
}

uninstall_syncthing() {
    echo "Uninstalling Syncthing..."

    # Stop and disable the service if running
    systemctl --user stop syncthing.service 2>/dev/null || true
    systemctl --user disable syncthing.service 2>/dev/null || true

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y syncthing
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/syncthing.list
            sudo rm -f /etc/apt/keyrings/syncthing-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y syncthing
            sudo rm -f /etc/yum.repos.d/syncthing.repo
            ;;
        arch)
            sudo pacman -Rs --noconfirm syncthing
            ;;
        suse)
            sudo zypper remove -y syncthing
            ;;
    esac
    rm -rf ~/.config/syncthing
    rm -rf ~/.syncthing
    echo "Syncthing has been uninstalled."
}

update_syncthing() {
    echo "Updating Syncthing..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y syncthing
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y syncthing
            ;;
        arch)
            sudo pacman -S --noconfirm syncthing
            ;;
        suse)
            sudo zypper update -y syncthing
            ;;
    esac
}
get_version_syncthing() {
    _ver_from_cmd syncthing || echo ""
}
