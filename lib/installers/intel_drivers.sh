#!/bin/bash
# Intel GPU Driver installer functions

# --- Intel Drivers ---

# Whether lspci reports an Intel GPU. Only the vendor text is matched (the
# class prefix is stripped) so other devices' names are not picked up.
_intel_gpu_present() {
    lspci 2>/dev/null | grep -E 'VGA|3D controller|Display controller' | \
        sed 's/^[^:]*:[^:]*: //' | grep -q '\bIntel\b'
}

check_intel_drivers() {
    # Check an Intel GPU is present and its VA-API video driver is installed
    _intel_gpu_present || return 1
    pkg_check_installed intel-media-driver 2>/dev/null || \
    pkg_check_installed intel-media-va-driver-non-free 2>/dev/null || \
    pkg_check_installed intel-media-va-driver 2>/dev/null
}

install_intel_drivers() {
    info "Installing Intel GPU drivers, Vulkan and video acceleration support..."
    ensure_tools

    # Check that an Intel GPU is present before proceeding
    if ! _intel_gpu_present; then
        warn "No Intel GPU detected. Skipping driver installation."
        return 1
    fi

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            # Mesa open-source driver stack + Vulkan
            pkg_install mesa-vulkan-drivers mesa-utils libgl1-mesa-dri libglx-mesa0 vulkan-tools libvulkan1 vainfo

            # VA-API video acceleration: the non-free driver (Debian non-free /
            # Ubuntu multiverse) has the full set of hardware encoders
            pkg_install intel-media-va-driver-non-free 2>/dev/null || {
                warn "intel-media-va-driver-non-free needs Debian's non-free (Ubuntu: multiverse) component."
                warn "Installing the free intel-media-va-driver instead, which has fewer hardware encoders."
                pkg_install intel-media-va-driver
            }
            ;;
        fedora)
            # RPM Fusion nonfree carries the full-codec intel-media-driver;
            # Fedora's own libva-intel-media-driver is the codec-reduced build.
            # It installs to /usr/lib64/dri-nonfree, which libva searches first.
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            fi
            pkg_install mesa-dri-drivers mesa-vulkan-drivers vulkan-tools vulkan-loader intel-media-driver libva-utils
            ;;
        rhel)
            # RPM Fusion for EL (which needs EPEL) carries intel-media-driver
            pkg_install epel-release 2>/dev/null || true
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm"
            fi
            pkg_install mesa-dri-drivers mesa-vulkan-drivers vulkan-tools vulkan-loader intel-media-driver 2>/dev/null || true
            pkg_install libva-utils 2>/dev/null || true
            ;;
        arch)
            pkg_install mesa vulkan-intel intel-media-driver libva-utils

            # 32-bit support (multilib)
            if grep -q "^\[multilib\]" /etc/pacman.conf; then
                pkg_install lib32-mesa lib32-vulkan-intel 2>/dev/null || true
            fi
            ;;
        suse)
            pkg_install Mesa Mesa-libGL1 Mesa-dri libvulkan1 libvulkan_intel vulkan-tools intel-media-driver libva-utils 2>/dev/null || true
            ;;
    esac

    info "Intel drivers installed. A reboot may be required for changes to take effect."
}

uninstall_intel_drivers() {
    warn "Intel GPU drivers are tightly integrated with the system graphics stack."
    warn "Removing them will break desktop rendering. This operation is not supported."
    info "If you need to switch GPU drivers, consult your distro's documentation."
    return 1
}

update_intel_drivers() {
    info "Updating Intel GPU drivers..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 mesa-utils \
                intel-media-va-driver-non-free intel-media-va-driver 2>/dev/null || true
            ;;
        fedora|rhel)
            pkg_upgrade mesa-dri-drivers mesa-vulkan-drivers intel-media-driver 2>/dev/null || true
            ;;
        arch)
            pkg_upgrade mesa vulkan-intel intel-media-driver 2>/dev/null || true
            ;;
        suse)
            pkg_upgrade Mesa Mesa-libGL1 libvulkan1 intel-media-driver 2>/dev/null || true
            ;;
    esac
    info "Intel drivers updated."
}

get_version_intel_drivers() {
    # Report the Mesa version as the driver version
    local pkg
    case "$DISTRO_FAMILY" in
        debian)      pkg=libgl1-mesa-dri ;;
        fedora|rhel) pkg=mesa-dri-drivers ;;
        arch)        pkg=mesa ;;
        suse)        pkg=Mesa-dri ;;
        *)           echo ""; return 0 ;;
    esac
    pkg_check_installed "$pkg" || { echo ""; return 0; }
    # Strip the epoch (Arch "1:") and the release/distro suffix
    pkg_get_version "$pkg" | sed 's/^[0-9]*://; s/[-+~].*//'
}
