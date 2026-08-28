#!/bin/bash
# Steam App installer functions

# --- Steam App ---

check_steam() {
    _have_cmd steam || \
        pkg_check_installed steam-installer || \
        pkg_check_installed steam-launcher || \
        (flatpak_is_installed "com.valvesoftware.Steam")
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
# Settle Steam's vulkan-driver / lib32-vulkan-driver dependencies BEFORE asking
# pacman for steam itself.
#
# Both are virtual: nothing in a default install provides them, because mesa
# provides opengl-driver and libva-driver but not vulkan-driver. pacman
# therefore has to choose a provider, and --noconfirm makes it take the first
# one offered -- which is decided by repo order, not by suitability.
#
# On plain Arch that list begins at extra and any pick works. CachyOS inserts
# cachyos-v3 and cachyos ahead of extra, and they carry mesa-git, so provider #1
# becomes mesa-git / lib32-mesa-git. Those declare conflicts=('mesa'), which
# collides with the stable mesa CachyOS itself installed, and the whole
# transaction aborts with "unresolvable package conflicts detected". It is
# deterministic, so retrying re-runs the identical failure.
#
# vulkan-swrast (Lavapipe) settles it on ANY machine: it is a software
# rasteriser, so it needs no GPU at all -- a VM, a headless box or a system with
# no graphics hardware installs it fine -- and it conflicts with nothing.
# Installing Steam must never depend on what graphics hardware is present.
_steam_arch_settle_vulkan() {
    local virt pkg
    # pacman -T prints the dependencies that nothing installed satisfies, so
    # empty output means a provider is already present and must be left alone.
    for virt in vulkan-driver lib32-vulkan-driver; do
        [[ -z "$(pacman -T "$virt" 2>/dev/null)" ]] && continue
        pkg="vulkan-swrast"
        [[ "$virt" == lib32-* ]] && pkg="lib32-vulkan-swrast"
        echo "Installing ${pkg} to satisfy ${virt} (software rendering, no GPU required)..."
        if ! sudo pacman -S --noconfirm --needed "$pkg"; then
            echo "Error: Failed to install ${pkg}, which Steam requires."
            return 1
        fi
    done

    # The loaders are what actually dispatch to whichever ICD is present.
    for pkg in vulkan-icd-loader lib32-vulkan-icd-loader; do
        pkg_check_installed "$pkg" && continue
        sudo pacman -S --noconfirm --needed "$pkg" || \
            warn "Could not install ${pkg}; Vulkan may not work until it is present."
    done
    return 0
}

# Add the vulkan driver matching the detected GPU, on top of the swrast fallback
# already in place. Entirely best-effort: Steam is installed and working by the
# time this runs, so nothing here returns non-zero.
#
# Deliberately NOT a shotgun. The previous code installed lib32-vulkan-intel,
# lib32-vulkan-radeon and lib32-nvidia-utils together with "2>/dev/null || true",
# which pulled the NVIDIA stack onto AMD machines and -- because one bad name
# fails the whole batch -- silently installed nothing at all when it failed.
#
# A VM adapter (QXL, VMware SVGA, Bochs, VirtualBox) matches nothing here and is
# left on swrast, which is the correct answer for it.
_steam_arch_add_gpu_driver() {
    local gpu="" drivers=()

    if command -v lspci &>/dev/null; then
        gpu=$(lspci 2>/dev/null | grep -i 'vga\|3d controller\|display controller' | head -1)
    fi

    case "${gpu,,}" in
        *nvidia*)          drivers=(nvidia-utils lib32-nvidia-utils) ;;
        *amd*|*ati*|*radeon*) drivers=(vulkan-radeon lib32-vulkan-radeon) ;;
        *intel*)           drivers=(vulkan-intel lib32-vulkan-intel) ;;
        *virtio*)          drivers=(vulkan-virtio lib32-vulkan-virtio) ;;
        *)
            verbose "No hardware-specific Vulkan driver for '${gpu:-unknown GPU}' — keeping software rendering."
            return 0
            ;;
    esac

    local pkg
    for pkg in "${drivers[@]}"; do
        pkg_check_installed "$pkg" && continue
        # Individually, so one unavailable name cannot cost the other.
        sudo pacman -S --noconfirm --needed "$pkg" || \
            warn "Could not install ${pkg}; Steam will fall back to software rendering."
    done
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

            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" ]]; then
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
                verify_download "$steam_deb" "deb" "Steam" || return 1

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
                sudo flatpak install -y flathub com.valvesoftware.Steam
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

            _steam_arch_settle_vulkan || return 1

            echo "Installing Steam..."
            if ! sudo pacman -S --noconfirm steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi

            # Purely an optimisation on top of a working install -- never fatal.
            _steam_arch_add_gpu_driver
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
    if flatpak_is_installed "com.valvesoftware.Steam"; then
        flatpak uninstall -y --user com.valvesoftware.Steam 2>/dev/null || \
            sudo flatpak uninstall -y --system com.valvesoftware.Steam
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
    if flatpak_is_installed "com.valvesoftware.Steam"; then
        flatpak update -y --user com.valvesoftware.Steam 2>/dev/null || \
            sudo flatpak update -y --system com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt update
                sudo apt install -y --only-upgrade steam
                ;;
            *)
                pkg_upgrade steam
                ;;
        esac
    fi
}
get_version_steam() {
    if flatpak_is_installed "com.valvesoftware.Steam"; then
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
