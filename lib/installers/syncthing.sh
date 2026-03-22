#!/bin/bash
# Syncthing installer functions

# --- Syncthing ---

check_syncthing() {
    command -v syncthing &>/dev/null || pkg_check_installed syncthing
}

install_syncthing() {
    echo "Installing Syncthing..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Add the Syncthing PGP key
            sudo mkdir -p /etc/apt/keyrings
            sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg

            # Add the Syncthing repository
            echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | \
                sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null

            # Update and install
            sudo apt update
            sudo apt install -y syncthing
            ;;
        fedora|rhel)
            # Install from official Fedora repos (Syncthing is included by default)
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
            sudo apt remove -y syncthing
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
    
    echo "Syncthing has been uninstalled."
    echo "Note: Your Syncthing configuration and data (~/.config/syncthing) have been preserved."
    echo "To remove them manually, run: rm -rf ~/.config/syncthing"
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
    syncthing --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || echo ""
}
