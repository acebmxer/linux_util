#!/bin/bash
# Intel CPU microcode and thermal management functions
# Supports: 10th Gen (Comet Lake/Ice Lake) through Core Ultra 2 (Arrow Lake, Core Ultra 270K)
# Covers Intel 400/500/600/700/800 series chipsets (LGA1200, LGA1700, LGA1851)

# --- Intel CPU Microcode & Thermal ---

check_intel_chipset_drivers() {
    # Require an Intel CPU to be present
    grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null || return 1
    # Check microcode is installed
    pkg_check_installed intel-microcode 2>/dev/null || \
    pkg_check_installed intel-ucode 2>/dev/null || \
    pkg_check_installed ucode-intel 2>/dev/null || \
    pkg_check_installed microcode_ctl 2>/dev/null
}

get_version_intel_chipset_drivers() {
    # Report the currently loaded CPU microcode revision
    local rev
    rev=$(grep -m1 "microcode" /proc/cpuinfo 2>/dev/null | grep -oP '0x[0-9a-fA-F]+')
    if [[ -n "$rev" ]]; then
        echo "$rev"
        return
    fi
    # Fallback: package version
    pkg_get_version intel-microcode 2>/dev/null | sed 's/-.*//' || \
    pkg_get_version intel-ucode    2>/dev/null | sed 's/-.*//' || \
    pkg_get_version ucode-intel    2>/dev/null | sed 's/-.*//' || \
    echo ""
}

install_intel_chipset_drivers() {
    info "Installing Intel CPU microcode and thermal management..."

    # Verify an Intel CPU is present before proceeding
    if ! grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        warn "No Intel CPU detected. Skipping Intel chipset driver installation."
        return 1
    fi

    case "$DISTRO_FAMILY" in
        debian)
            # Enable non-free/contrib repositories if needed for intel-microcode
            if ! apt-cache show intel-microcode &>/dev/null; then
                info "Enabling non-free repository for intel-microcode..."
                if grep -q "bookworm\|bullseye\|buster" /etc/os-release 2>/dev/null; then
                    sudo apt-get install -y software-properties-common 2>/dev/null || true
                    sudo apt-add-repository -y non-free 2>/dev/null || true
                    sudo apt-get update
                fi
            fi
            sudo apt-get install -y \
                intel-microcode \
                thermald
            ;;
        fedora)
            # microcode_ctl handles Intel (and AMD) microcode on Fedora
            sudo "$PKG_MGR" install -y \
                microcode_ctl \
                thermald
            ;;
        rhel)
            sudo "$PKG_MGR" install -y \
                microcode_ctl \
                thermald 2>/dev/null || \
            sudo "$PKG_MGR" install -y microcode_ctl
            ;;
        arch)
            sudo pacman -S --noconfirm \
                intel-ucode \
                thermald
            # Trigger initramfs rebuild so the new microcode is picked up at next boot
            if command -v mkinitcpio &>/dev/null; then
                info "Regenerating initramfs to include updated microcode..."
                sudo mkinitcpio -P
            fi
            ;;
        suse)
            sudo zypper install -y \
                ucode-intel \
                thermald 2>/dev/null || \
            sudo zypper install -y ucode-intel
            ;;
        *)
            warn "Intel chipset driver installation is not implemented for ${DISTRO_NAME}."
            warn "Please install 'intel-microcode' (or equivalent) and 'thermald' manually."
            return 1
            ;;
    esac

    # Enable and start thermald if available
    if command -v thermald &>/dev/null || pkg_check_installed thermald 2>/dev/null; then
        info "Enabling thermald service..."
        sudo systemctl enable --now thermald 2>/dev/null || \
            warn "Could not enable thermald (may not be available on this platform)."
    fi

    info "Intel CPU microcode and thermal management installed."
    info "A reboot is recommended to activate the updated microcode."
}

uninstall_intel_chipset_drivers() {
    info "Removing Intel CPU microcode and thermal management..."

    # Stop and disable thermald
    if systemctl is-active thermald &>/dev/null; then
        sudo systemctl stop thermald 2>/dev/null || true
    fi
    if systemctl is-enabled thermald &>/dev/null; then
        sudo systemctl disable thermald 2>/dev/null || true
    fi

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get remove -y intel-microcode thermald 2>/dev/null || true
            sudo apt-get autoremove -y 2>/dev/null || true
            ;;
        fedora|rhel)
            # microcode_ctl is shared with AMD — only remove thermald
            warn "Skipping removal of microcode_ctl (shared with AMD microcode on this distro)."
            sudo "$PKG_MGR" remove -y thermald 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rns --noconfirm intel-ucode thermald 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y ucode-intel thermald 2>/dev/null || true
            ;;
        *)
            warn "Uninstall not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac

    info "Intel CPU microcode removed. Reboot to revert to BIOS-provided microcode."
}

update_intel_chipset_drivers() {
    info "Updating Intel CPU microcode and thermal management..."
    local pkg_updated=0
    case "$DISTRO_FAMILY" in
        debian)
            local apt_out
            apt_out=$(sudo apt-get install -y --only-upgrade intel-microcode thermald 2>&1 || \
                      sudo apt-get upgrade -y intel-microcode thermald 2>&1 || true)
            printf '%s\n' "$apt_out"
            # apt reports "0 upgraded, 0 newly installed" when nothing changed
            echo "$apt_out" | grep -q "^0 upgraded, 0 newly installed" || pkg_updated=1
            ;;
        fedora|rhel)
            local pkg_out
            pkg_out=$(sudo "$PKG_MGR" upgrade -y microcode_ctl thermald 2>&1 || true)
            printf '%s\n' "$pkg_out"
            echo "$pkg_out" | grep -qi "nothing to do" || pkg_updated=1
            ;;
        arch)
            sudo pacman -S --noconfirm intel-ucode thermald 2>/dev/null || true
            if command -v mkinitcpio &>/dev/null; then
                sudo mkinitcpio -P 2>/dev/null || true
            fi
            pkg_updated=1
            ;;
        suse)
            local zyp_out
            zyp_out=$(sudo zypper update -y ucode-intel thermald 2>&1 || true)
            printf '%s\n' "$zyp_out"
            echo "$zyp_out" | grep -qi "nothing to do\|no packages" || pkg_updated=1
            ;;
    esac
    if [[ $pkg_updated -eq 1 ]]; then
        info "Intel CPU microcode and thermald updated. Reboot to activate the changes."
    else
        info "Intel CPU microcode and thermald are already up to date."
    fi
}
