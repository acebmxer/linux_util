#!/bin/bash
# GRUB bootloader installer functions

# --- GRUB ---

check_grub() {
    _have_cmd grub-install || _have_cmd grub2-install
}

install_grub() {
    info "Installing GRUB bootloader..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y grub-efi-amd64 grub-pc-bin grub-common
            ;;
        fedora)
            sudo dnf install -y grub2-efi-x64 grub2-pc grub2-tools
            ;;
        rhel)
            sudo "$PKG_MGR" install -y grub2-efi-x64 grub2-pc grub2-tools
            ;;
        arch)
            sudo pacman -S --noconfirm grub efibootmgr
            ;;
        suse)
            sudo zypper install -y grub2 grub2-x86_64-efi
            ;;
        *)
            error "Unsupported distribution family: $DISTRO_FAMILY"
            return 1
            ;;
    esac
    info "GRUB installed. Run 'sudo grub-install' (or grub2-install) to deploy to your boot device."
}

uninstall_grub() {
    warn "Removing GRUB may leave your system unbootable. Ensure another bootloader is configured first."
    info "Uninstalling GRUB..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y grub-efi-amd64 grub-pc grub-common ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y grub2-efi-x64 grub2-pc grub2-tools ;;
        arch)        sudo pacman -Rs --noconfirm grub ;;
        suse)        sudo zypper remove -y grub2 grub2-x86_64-efi ;;
    esac
    info "GRUB packages removed."
}

update_grub() {
    info "Updating GRUB..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade grub-efi-amd64 grub-common ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y grub2-efi-x64 grub2-tools ;;
        arch)        sudo pacman -S --noconfirm grub ;;
        suse)        sudo zypper update -y grub2 grub2-x86_64-efi ;;
    esac
    # Regenerate the GRUB config after upgrade
    if command -v update-grub &>/dev/null; then
        sudo update-grub
    elif command -v grub2-mkconfig &>/dev/null; then
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    elif command -v grub-mkconfig &>/dev/null; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
    info "GRUB updated."
}

get_version_grub() {
    _run_native grub-install --version 2>/dev/null | grep -oP '[\d.]+' | head -1 \
        || _run_native grub2-install --version 2>/dev/null | grep -oP '[\d.]+' | head -1 \
        || _ver_from_pkg grub2 \
        || _ver_from_pkg grub \
        || echo ""
}
