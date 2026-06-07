#!/bin/bash
# AMD Driver installer functions

# --- AMD Drivers ---

check_amd_drivers() {
    # Check if amdgpu is the active GPU driver and Mesa is installed
    lspci 2>/dev/null | grep -qi "AMD\|Radeon\|ATI" || return 1
    lsmod 2>/dev/null | grep -q "^amdgpu" || return 1
    command -v glxinfo &>/dev/null && glxinfo 2>/dev/null | grep -qi "AMD\|Radeon\|RADV" && return 0
    # At minimum, check Mesa is present
    pkg_check_installed mesa-utils 2>/dev/null || \
    pkg_check_installed libgl1-mesa-dri 2>/dev/null || \
    pkg_check_installed mesa-dri-drivers 2>/dev/null
}

install_amd_drivers() {
    info "Installing AMD GPU drivers and Vulkan support..."
    ensure_tools

    # Check that an AMD GPU is present before proceeding
    if ! lspci 2>/dev/null | grep -qi "AMD\|Radeon\|ATI"; then
        warn "No AMD GPU detected. Skipping driver installation."
        return 1
    fi

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            # Mesa open-source driver stack + Vulkan
            sudo apt install -y \
                mesa-vulkan-drivers \
                mesa-utils \
                libgl1-mesa-dri \
                libglx-mesa0 \
                vulkan-tools \
                libvulkan1

            # 32-bit Vulkan support for Steam/Wine (best-effort)
            sudo dpkg --add-architecture i386 2>/dev/null || true
            sudo apt update
            sudo apt install -y mesa-vulkan-drivers:i386 libvulkan1:i386 2>/dev/null || \
                warn "32-bit Vulkan libs not available on this system."

            # Optional: amdgpu-pro firmware extras if available
            sudo apt install -y firmware-amd-graphics 2>/dev/null || true
            ;;
        fedora)
            sudo "$PKG_MGR" install -y \
                mesa-dri-drivers \
                mesa-vulkan-drivers \
                vulkan-tools \
                vulkan-loader \
                xorg-x11-drv-amdgpu

            # RPM Fusion provides 32-bit Mesa (lib32-mesa) for Steam
            if rpm -q rpmfusion-free-release &>/dev/null; then
                sudo "$PKG_MGR" install -y mesa-vulkan-drivers.i686 vulkan-loader.i686 2>/dev/null || true
            fi
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y \
                mesa-dri-drivers \
                mesa-vulkan-drivers \
                vulkan-tools \
                vulkan-loader 2>/dev/null || true
            ;;
        arch)
            sudo pacman -S --noconfirm \
                mesa \
                vulkan-radeon \
                libva-mesa-driver \
                mesa-vdpau \
                xf86-video-amdgpu

            # 32-bit support (multilib)
            if grep -q "^\[multilib\]" /etc/pacman.conf; then
                sudo pacman -S --noconfirm \
                    lib32-mesa \
                    lib32-vulkan-radeon \
                    lib32-libva-mesa-driver \
                    lib32-mesa-vdpau 2>/dev/null || true
            fi
            ;;
        suse)
            sudo zypper install -y \
                Mesa \
                Mesa-libGL1 \
                Mesa-dri \
                libvulkan1 \
                vulkan-tools \
                xf86-video-amdgpu 2>/dev/null || true
            ;;
    esac

    info "AMD drivers installed. A reboot may be required for changes to take effect."
}

uninstall_amd_drivers() {
    warn "AMD GPU drivers are tightly integrated with the system graphics stack."
    warn "Removing them will break desktop rendering. This operation is not supported."
    info "If you need to switch GPU drivers, consult your distro's documentation."
    return 1
}

update_amd_drivers() {
    info "Updating AMD GPU drivers..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 mesa-utils 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y mesa-dri-drivers mesa-vulkan-drivers 2>/dev/null || true
            ;;
        arch)
            sudo pacman -S --noconfirm mesa vulkan-radeon 2>/dev/null || true
            ;;
        suse)
            sudo zypper update -y Mesa Mesa-libGL1 libvulkan1 2>/dev/null || true
            ;;
    esac
    info "AMD drivers updated."
}

get_version_amd_drivers() {
    # Report the Mesa version as the driver version
    glxinfo 2>/dev/null | grep -oP 'Mesa \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    pkg_get_version mesa-dri-drivers 2>/dev/null | sed 's/-.*//' || \
    pkg_get_version libgl1-mesa-dri 2>/dev/null | sed 's/-.*//' || \
    echo ""
}
