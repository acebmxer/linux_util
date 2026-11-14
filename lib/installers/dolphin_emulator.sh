#!/bin/bash
# Dolphin Emulator installer functions
#
# GameCube and Wii emulator (registered as Dolphin Emulator because Dolphin is
# the KDE file manager's name here). The distro package on Debian, Ubuntu,
# Fedora, Arch, openSUSE and Alpine; Flathub on RHEL clones.

# --- Dolphin Emulator ---

check_dolphin_emulator() { _check_standard dolphin-emu dolphin-emu org.DolphinEmu.dolphin-emu; }

install_dolphin_emulator() {
    info "Installing Dolphin Emulator..."
    native_or_flatpak_install org.DolphinEmu.dolphin-emu dolphin-emu || return 1
    info "Dolphin Emulator installed."
}

# Your saves and settings are kept.
uninstall_dolphin_emulator() {
    info "Uninstalling Dolphin Emulator..."
    native_or_flatpak_uninstall org.DolphinEmu.dolphin-emu dolphin-emu
}

update_dolphin_emulator() {
    info "Updating Dolphin Emulator..."
    native_or_flatpak_update org.DolphinEmu.dolphin-emu dolphin-emu
}

get_version_dolphin_emulator() { native_or_flatpak_version org.DolphinEmu.dolphin-emu dolphin-emu; }
