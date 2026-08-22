#!/bin/bash
# Devolutions RDM installer functions

# --- Devolutions RDM ---

check_devolutions_rdm() {
    _have_cmd remotedesktopmanager || pkg_check_installed RemoteDesktopManager || pkg_check_installed remotedesktopmanager || pkg_check_installed remote-desktop-manager
}
install_devolutions_rdm() {
    echo "Installing Devolutions RDM..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Ubuntu/Debian repository setup
            echo "Setting up Cloudsmith repository for Remote Desktop Manager..."

            # KDE Neon has ID=neon which Cloudsmith's setup.deb.sh doesn't recognise.
            # Manually add the Ubuntu-based repo using the upstream Ubuntu codename.
            if [[ "$DISTRO_ID" == "neon" ]]; then
                local ubuntu_codename="${DISTRO_VERSION_CODENAME}"
                # Fallback: read from KDE Neon's upstream release file
                if [[ -z "$ubuntu_codename" && -f /etc/upstream-release/lsb-release ]]; then
                    ubuntu_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                fi
                ubuntu_codename="${ubuntu_codename:-noble}"
                echo "KDE Neon detected (Ubuntu ${ubuntu_codename} base). Configuring repository manually..."
                curl -1sLf 'https://dl.cloudsmith.io/public/devolutions/rdm/gpg.FE7407ECB26FD2FE.key' | \
                    sudo gpg --dearmor -o /usr/share/keyrings/devolutions-rdm.gpg
                echo "deb [signed-by=/usr/share/keyrings/devolutions-rdm.gpg] https://dl.cloudsmith.io/public/devolutions/rdm/deb/ubuntu ${ubuntu_codename} main" | \
                    sudo tee /etc/apt/sources.list.d/devolutions-rdm.list > /dev/null
            else
                local tmpfile
                tmpfile=$(mktemp /tmp/devolutions-setup-XXXXXX.sh)
                CLEANUP_FILES+=("$tmpfile")

                if ! curl -1sLf -o "$tmpfile" 'https://dl.cloudsmith.io/public/devolutions/rdm/setup.deb.sh'; then
                    echo "Error: Failed to download Devolutions repository setup script."
                    rm -f "$tmpfile"
                    return 1
                fi

                if [[ ! -s "$tmpfile" ]]; then
                    echo "Error: Downloaded setup script is empty."
                    rm -f "$tmpfile"
                    return 1
                fi

                sudo -E bash "$tmpfile"
            fi

            # Install required packages for repository management
            sudo apt-get install -y apt-transport-https 2>/dev/null || true

            # Update package lists and install Remote Desktop Manager
            sudo apt-get update
            sudo apt-get install -y remotedesktopmanager
            ;;
        fedora|rhel)
            # Fedora/RHEL repository setup
            echo "Setting up Cloudsmith repository for Remote Desktop Manager..."
            
            # Ensure required tools
            sudo "$PKG_MGR" install -y dnf-plugins-core pygpgme 2>/dev/null || true
            
            # Import GPG key
            sudo rpm --import 'https://dl.cloudsmith.io/public/devolutions/rdm/gpg.FE7407ECB26FD2FE.key'
            
            # Add repository
            curl -1sLf "https://dl.cloudsmith.io/public/devolutions/rdm/config.rpm.txt?distro=${DISTRO_ID}&codename=${DISTRO_VERSION_ID}" | \
                sudo tee /etc/yum.repos.d/devolutions-rdm.repo > /dev/null
            
            # Update repository cache and install
            sudo "$PKG_MGR" makecache -y
            sudo "$PKG_MGR" install -y RemoteDesktopManager
            ;;
        arch)
            # Repo package where the distro ships one (CachyOS and friends),
            # otherwise the AUR.
            repo_or_aur remote-desktop-manager
            ;;
        suse)
            # openSUSE support via Flatpak or snap (as direct repos may not be available)
            if ensure_flatpak; then
                echo "Installing via Flatpak..."
                sudo flatpak install -y flathub com.devolutions.RemoteDesktopManager
            elif has_snap; then
                echo "Installing via Snap..."
                sudo snap install remote-desktop-manager
            else
                echo "Error: Flatpak or Snap is required to install Remote Desktop Manager on this distribution."
                echo "Please install flatpak or snap first."
                return 1
            fi
            ;;
        *)
            # Fallback to Flatpak or Snap
            if ensure_flatpak; then
                echo "Installing via Flatpak..."
                sudo flatpak install -y flathub com.devolutions.RemoteDesktopManager
            elif has_snap; then
                echo "Installing via Snap..."
                sudo snap install remote-desktop-manager
            else
                echo "Error: No compatible installation method found for this distribution."
                return 1
            fi
            ;;
    esac
}
uninstall_devolutions_rdm() {
    echo "Uninstalling Devolutions RDM..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel)
            pkg_remove RemoteDesktopManager 2>/dev/null || pkg_remove remotedesktopmanager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            # Clean up repository configuration for Debian
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                sudo rm -f /etc/apt/sources.list.d/devolutions-rdm.list
                sudo rm -f /usr/share/keyrings/devolutions-rdm.gpg
            fi
            # Clean up repository configuration for RHEL/Fedora
            if [[ "$DISTRO_FAMILY" == "fedora" ]] || [[ "$DISTRO_FAMILY" == "rhel" ]]; then
                sudo rm -f /etc/yum.repos.d/devolutions-rdm.repo
            fi
            ;;
        arch)
            aur_remove remote-desktop-manager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            ;;
        *)
            if flatpak_is_installed "remote.*desktop.*manager\|RemoteDesktopManager"; then
                flatpak uninstall -y com.devolutions.RemoteDesktopManager || true
            elif has_snap && snap list 2>/dev/null | grep -qi "remote-desktop-manager"; then
                sudo snap remove remote-desktop-manager || true
            else
                pkg_remove remotedesktopmanager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            fi
            ;;
    esac
    rm -rf ~/.config/Devolutions
    rm -rf ~/.devolutions
}
update_devolutions_rdm() {
    echo "Updating Devolutions RDM..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install --only-upgrade -y remotedesktopmanager
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y RemoteDesktopManager
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade remote-desktop-manager
            else
                echo "Error: An AUR helper (yay/paru) is required."
                return 1
            fi
            ;;
        *)
            if flatpak_is_installed "remote.*desktop.*manager\|RemoteDesktopManager"; then
                flatpak update -y com.devolutions.RemoteDesktopManager
            elif has_snap && snap list 2>/dev/null | grep -qi "remote-desktop-manager"; then
                sudo snap refresh remote-desktop-manager
            else
                pkg_upgrade remotedesktopmanager 2>/dev/null || true
            fi
            ;;
    esac
}
get_version_devolutions_rdm() {
    if pkg_check_installed RemoteDesktopManager; then
        pkg_get_version RemoteDesktopManager | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed remotedesktopmanager; then
        pkg_get_version remotedesktopmanager | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed remote-desktop-manager; then
        pkg_get_version remote-desktop-manager | sed 's/^[0-9]*://; s/-.*//'
    else
        echo ""
    fi
}
