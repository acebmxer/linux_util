#!/bin/bash
# Steam App installer functions

# --- Steam App ---

check_steam() {
    command -v steam &>/dev/null || \
        pkg_check_installed steam-installer || \
        pkg_check_installed steam-launcher || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam")
}

# Helper function to ensure contrib component is enabled for Debian
ensure_debian_contrib() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi

    local _contrib_found=false

    # Check traditional sources.list format
    if [[ -f /etc/apt/sources.list ]] && \
       grep -qE "^deb .*debian.* main" /etc/apt/sources.list 2>/dev/null; then
        if grep -E "^deb .*debian.* main" /etc/apt/sources.list | grep -q "contrib"; then
            _contrib_found=true
        else
            echo "Steam requires the 'contrib' component in Debian repositories."
            echo "Enabling 'contrib' component in /etc/apt/sources.list..."
            sudo cp /etc/apt/sources.list "/etc/apt/sources.list.backup-$(date +%Y%m%d-%H%M%S)"
            sudo sed -i 's/^\(deb .*debian.* main\)\(.*\)/\1 contrib\2/' /etc/apt/sources.list
            # Deduplicate 'contrib' if it appeared twice
            sudo sed -i 's/contrib contrib/contrib/g' /etc/apt/sources.list
            _contrib_found=true
        fi
    fi

    # Check DEB822 format (.sources files, Debian 12+)
    local _sources_file
    for _sources_file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$_sources_file" ]] || continue
        if grep -qP '^Components:.*\bmain\b' "$_sources_file" 2>/dev/null; then
            if grep -qP '^Components:.*\bcontrib\b' "$_sources_file" 2>/dev/null; then
                _contrib_found=true
            else
                echo "Adding 'contrib' component to $(basename "$_sources_file")..."
                sudo cp "$_sources_file" "${_sources_file}.backup-$(date +%Y%m%d-%H%M%S)"
                sudo sed -i 's/^\(Components:.*main\)/\1 contrib/' "$_sources_file"
                _contrib_found=true
            fi
        fi
    done

    if [[ "$_contrib_found" == "true" ]]; then
        echo "'contrib' component enabled. Updating package lists..."
        sudo apt update
    fi
}

# Helper function to detect mixed repository issues
detect_debian_repo_mix() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi
    
    local has_stable=false
    local has_testing=false
    local has_unstable=false
    
    # Check for different Debian releases in sources.list
    if grep -qE "^deb .*(bookworm|bullseye|buster)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_stable=true
    fi
    if grep -qE "^deb .*(trixie|testing)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_testing=true
    fi
    if grep -qE "^deb .*(sid|unstable)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_unstable=true
    fi
    
    local mix_count=0
    $has_stable && ((mix_count++))
    $has_testing && ((mix_count++))
    $has_unstable && ((mix_count++))
    
    if [[ $mix_count -gt 1 ]]; then
        echo "⚠️  WARNING: Mixed Debian repositories detected!"
        echo "Your system has multiple Debian releases configured:"
        $has_stable && echo "  - Stable (Bookworm/Bullseye)"
        $has_testing && echo "  - Testing (Trixie)"
        $has_unstable && echo "  - Unstable (Sid)"
        echo "This can cause package version conflicts and dependency issues."
        echo "Consider using a single Debian release for better stability."
        echo ""
        return 1
    fi
    return 0
}
install_steam() {
    echo "Installing Steam..."

    # Steam requires NVIDIA 32-bit GL libraries to launch on NVIDIA systems.
    # Check whether they are present and install them if not.
    if check_nvidia_drivers; then
        if check_nvidia_i386_libs; then
            echo "NVIDIA 32-bit libraries already installed."
        else
            echo "NVIDIA drivers detected. Installing required 32-bit libraries for Steam..."
            install_nvidia_i386_libs || warn "Failed to install NVIDIA 32-bit libraries. Steam may not function correctly."
        fi
    fi

    case "$DISTRO_FAMILY" in
        debian)
            # Enable 32-bit architecture support
            sudo dpkg --add-architecture i386
            sudo apt update

            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                # Ubuntu / Kubuntu: install Steam via the multiverse repository
                echo "Enabling multiverse repository..."
                sudo add-apt-repository multiverse -y
                sudo apt update
                echo "Installing Steam..."
                if ! sudo apt install -y steam; then
                    echo "Error: Steam installation failed."
                    return 1
                fi
            else
                # Debian and other derivatives: download the official .deb installer
                echo "Downloading Steam installer from store.steampowered.com..."
                local steam_deb
                steam_deb=$(mktemp /tmp/steam-XXXXXX.deb)
                CLEANUP_FILES+=("$steam_deb")
                if ! wget -O "$steam_deb" "https://cdn.akamai.steamstatic.com/client/installer/steam.deb"; then
                    echo "Error: Failed to download Steam installer."
                    rm -f "$steam_deb"
                    return 1
                fi

                # Install Steam - prompts will be shown for user to accept/decline
                echo "Installing Steam (follow any on-screen prompts)..."
                sudo apt install -y "$steam_deb"
                local install_result=$?
                rm -f "$steam_deb"

                if [[ $install_result -ne 0 ]]; then
                    echo "Error: Steam installation failed."
                    return 1
                fi
            fi
            ;;
        fedora)
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                echo "Enabling RPM Fusion repositories (required for Steam)..."
                if ! sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; then
                    echo "Error: Failed to enable RPM Fusion repositories."
                    return 1
                fi
                sudo "$PKG_MGR" makecache
            fi
            echo "Installing Steam from RPM Fusion..."
            if ! sudo "$PKG_MGR" install -y steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install graphics libraries for better compatibility
            echo "Installing graphics libraries (Vulkan, Mesa)..."
            sudo "$PKG_MGR" install -y mesa-vulkan-drivers vulkan-loader 2>/dev/null || true
            ;;
        rhel)
            echo "Steam is not officially available for RHEL-based distributions."
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.valvesoftware.Steam
            else
                echo "Consider installing Flatpak: https://flatpak.org/setup/"
                return 1
            fi
            ;;
        arch)
            if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
                echo "Enabling multilib repository (required for 32-bit support)..."
                sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
                sudo pacman -Sy
            fi
            echo "Installing Steam..."
            if ! sudo pacman -S --noconfirm steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install 32-bit graphics libraries for better compatibility
            echo "Installing 32-bit graphics libraries (Vulkan, Mesa)..."
            sudo pacman -S --noconfirm lib32-mesa lib32-vulkan-icd-loader lib32-vulkan-intel \
                lib32-vulkan-radeon lib32-nvidia-utils 2>/dev/null || true
            ;;
        suse)
            echo "Installing Steam..."
            if ! sudo zypper install -y steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install graphics libraries for better compatibility
            echo "Installing graphics libraries (Vulkan, Mesa)..."
            sudo zypper install -y libvulkan1 libvulkan1-32bit \
                Mesa-libGL1 Mesa-libGL1-32bit 2>/dev/null || true
            ;;
    esac
}
uninstall_steam() {
    echo "Uninstalling Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak uninstall -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y steam steam-installer steam-launcher
                sudo apt autoclean
                ;;
            *)      pkg_remove steam 2>/dev/null || true ;;
        esac
    fi
    rm -rf ~/.config/steam
    rm -rf ~/.steam
}
update_steam() {
    echo "Updating Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak update -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt update
                sudo apt upgrade -y steam
                ;;
            *)
                pkg_upgrade steam
                ;;
        esac
    fi
}
get_version_steam() {
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak list 2>/dev/null | grep -i "com.valvesoftware.Steam" | awk -F'\t' '{print $3}'
    elif pkg_check_installed steam-installer; then
        pkg_get_version steam-installer | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed steam-launcher; then
        pkg_get_version steam-launcher | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed steam; then
        pkg_get_version steam | sed 's/^[0-9]*://; s/-.*//'
    else
        echo ""
    fi
}
