#!/bin/bash
# AMD CPU microcode and platform firmware functions
# Supports: AM4 (Ryzen 1000–5000 / Threadripper / EPYC) through AM5 (Ryzen 7000–9000 series)
# Covers AMD 300/400/500/600 series chipsets (X370–X870, B350–B650, A320–A620)

# --- AMD CPU Microcode & Firmware ---

check_amd_chipset_drivers() {
    # Require an AMD CPU to be present
    grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null || return 1
    # Check microcode package is installed
    pkg_check_installed amd64-microcode 2>/dev/null || \
    pkg_check_installed amd-ucode       2>/dev/null || \
    pkg_check_installed ucode-amd       2>/dev/null || \
    pkg_check_installed microcode_ctl   2>/dev/null
}

get_version_amd_chipset_drivers() {
    # Report the currently loaded CPU microcode revision
    local rev
    rev=$(grep -m1 "microcode" /proc/cpuinfo 2>/dev/null | grep -oP '0x[0-9a-fA-F]+')
    if [[ -n "$rev" ]]; then
        echo "$rev"
        return
    fi
    # Fallback: package version
    pkg_get_version amd64-microcode 2>/dev/null | sed 's/-.*//' || \
    pkg_get_version amd-ucode       2>/dev/null | sed 's/-.*//' || \
    pkg_get_version ucode-amd       2>/dev/null | sed 's/-.*//' || \
    echo ""
}

install_amd_chipset_drivers() {
    info "Installing AMD CPU microcode and platform firmware..."

    # Verify an AMD CPU is present before proceeding
    if ! grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        warn "No AMD CPU detected. Skipping AMD chipset driver installation."
        return 1
    fi

    case "$DISTRO_FAMILY" in
        debian)
            # amd64-microcode may require non-free on older Debian releases
            if ! apt-cache show amd64-microcode &>/dev/null; then
                info "Enabling non-free repository for amd64-microcode..."
                sudo apt-get install -y software-properties-common 2>/dev/null || true
                sudo apt-add-repository -y non-free 2>/dev/null || true
                sudo apt-get update
            fi
            sudo apt-get install -y \
                amd64-microcode \
                linux-firmware
            ;;
        fedora)
            # microcode_ctl bundles AMD microcode on Fedora; linux-firmware covers PSP/SMU firmware
            sudo "$PKG_MGR" install -y \
                microcode_ctl \
                linux-firmware
            ;;
        rhel)
            sudo "$PKG_MGR" install -y microcode_ctl 2>/dev/null || true
            # linux-firmware may be a separate or split package on RHEL variants
            sudo "$PKG_MGR" install -y linux-firmware 2>/dev/null || true
            ;;
        arch)
            sudo pacman -S --noconfirm \
                amd-ucode \
                linux-firmware
            # Trigger initramfs rebuild so new microcode is loaded at next boot
            if command -v mkinitcpio &>/dev/null; then
                info "Regenerating initramfs to include updated microcode..."
                sudo mkinitcpio -P
            fi
            ;;
        suse)
            sudo zypper install -y ucode-amd 2>/dev/null || true
            # kernel-firmware-amdgpu covers PSP / SMU firmware blobs for AM4/AM5
            sudo zypper install -y \
                kernel-firmware-amdgpu \
                kernel-firmware-amd 2>/dev/null || true
            ;;
        *)
            warn "AMD chipset driver installation is not implemented for ${DISTRO_NAME}."
            warn "Please install 'amd64-microcode' (or equivalent) and 'linux-firmware' manually."
            return 1
            ;;
    esac

    info "AMD CPU microcode and platform firmware installed."
    info "A reboot is recommended to activate the updated microcode and firmware."
}

uninstall_amd_chipset_drivers() {
    info "Removing AMD CPU microcode and platform firmware..."

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get remove -y amd64-microcode 2>/dev/null || true
            sudo apt-get autoremove -y 2>/dev/null || true
            warn "Note: linux-firmware was not removed as it is required by many other system components."
            ;;
        fedora|rhel)
            warn "Skipping removal of microcode_ctl (shared with Intel microcode on this distro)."
            warn "linux-firmware was not removed as it is a core system dependency."
            ;;
        arch)
            sudo pacman -Rns --noconfirm amd-ucode 2>/dev/null || true
            warn "linux-firmware was not removed as it is required by many other system components."
            ;;
        suse)
            sudo zypper remove -y ucode-amd 2>/dev/null || true
            warn "kernel-firmware packages were not removed as they may be required by other components."
            ;;
        *)
            warn "Uninstall not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac

    info "AMD microcode removed. Reboot to revert to BIOS-provided microcode."
}

update_amd_chipset_drivers() {
    info "Updating AMD CPU microcode and platform firmware..."
    local pkg_updated=0
    case "$DISTRO_FAMILY" in
        debian)
            local apt_out
            apt_out=$(sudo apt-get install -y --only-upgrade amd64-microcode linux-firmware 2>&1 || \
                      sudo apt-get upgrade -y amd64-microcode linux-firmware 2>&1 || true)
            printf '%s\n' "$apt_out"
            echo "$apt_out" | grep -q "^0 upgraded, 0 newly installed" || pkg_updated=1
            ;;
        fedora|rhel)
            local pkg_out
            pkg_out=$(sudo "$PKG_MGR" upgrade -y microcode_ctl linux-firmware 2>&1 || true)
            printf '%s\n' "$pkg_out"
            echo "$pkg_out" | grep -qi "nothing to do" || pkg_updated=1
            ;;
        arch)
            sudo pacman -S --noconfirm amd-ucode linux-firmware 2>/dev/null || true
            if command -v mkinitcpio &>/dev/null; then
                sudo mkinitcpio -P 2>/dev/null || true
            fi
            pkg_updated=1
            ;;
        suse)
            local zyp_out
            zyp_out=$(sudo zypper update -y ucode-amd kernel-firmware-amdgpu kernel-firmware-amd 2>&1 || true)
            printf '%s\n' "$zyp_out"
            echo "$zyp_out" | grep -qi "nothing to do\|no packages" || pkg_updated=1
            ;;
    esac
    if [[ $pkg_updated -eq 1 ]]; then
        info "AMD CPU microcode and firmware updated. Reboot to activate the changes."
    else
        info "AMD CPU microcode and firmware are already up to date."
    fi
}
