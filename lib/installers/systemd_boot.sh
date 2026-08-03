#!/bin/bash
# systemd-boot (formerly gummiboot) installer functions

# --- systemd-boot ---

check_systemd_boot() {
    _have_cmd bootctl && bootctl is-installed &>/dev/null 2>&1
}

install_systemd_boot() {
    info "Installing systemd-boot..."

    # Not supported on Debian/Ubuntu: they don't run kernel-install hooks to
    # generate loader entries on kernel updates, so the boot menu would go stale
    # after the next kernel install. GRUB is the integrated choice there.
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        warn "systemd-boot is not supported on Debian/Ubuntu by this tool."
        warn "Debian/Ubuntu don't run kernel-install hooks to maintain its entries on"
        warn "kernel updates, so the boot menu would go stale. Use GRUB on Debian/Ubuntu."
        return 1
    fi

    if ! command -v bootctl &>/dev/null; then
        # bootctl ships with systemd; install systemd if missing
        case "$DISTRO_FAMILY" in
            debian)      sudo apt install -y systemd ;;
            fedora|rhel) sudo "$PKG_MGR" install -y systemd ;;
            arch)        sudo pacman -S --noconfirm systemd ;;
            suse)        sudo zypper install -y systemd ;;
        esac
    fi

    if ! mountpoint -q /boot/efi && ! mountpoint -q /efi && ! mountpoint -q /boot; then
        warn "No EFI System Partition appears to be mounted at /boot/efi, /efi, or /boot."
        warn "Mount your ESP first, then re-run this installer."
        return 1
    fi

    sudo bootctl install
    info "systemd-boot installed. Add boot entries under /boot/loader/entries/."
}

uninstall_systemd_boot() {
    if ! command -v bootctl &>/dev/null; then
        warn "bootctl not found — systemd-boot is not installed."
        return 1
    fi
    warn "Removing systemd-boot may leave your system unbootable. Ensure another bootloader is configured first."
    sudo bootctl remove
    info "systemd-boot removed from the ESP."
}

update_systemd_boot() {
    info "Updating systemd-boot..."
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        warn "systemd-boot is not supported on Debian/Ubuntu by this tool."
        return 1
    fi
    if command -v bootctl &>/dev/null; then
        sudo bootctl update
        info "systemd-boot updated."
    else
        warn "bootctl not found — systemd-boot does not appear to be installed."
        return 1
    fi
}

get_version_systemd_boot() {
    _run_native bootctl --version 2>/dev/null | grep -oP '[\d]+' | head -1 || echo ""
}
