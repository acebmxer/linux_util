#!/bin/bash
# Pika Backup installer functions
#
# Simple scheduled backups of your home folder with BorgBackup, in a desktop
# window. The distro package on Arch and openSUSE Tumbleweed; everywhere else
# Pika's own Flathub listing (which carries its own borg). Not offered on
# Alpine.

# --- Pika Backup ---

check_pika_backup() { _check_standard "" pika-backup org.gnome.World.PikaBackup; }

install_pika_backup() {
    info "Installing Pika Backup..."
    native_or_flatpak_install org.gnome.World.PikaBackup pika-backup || return 1
    info "Pika Backup installed."
}

# Your backup schedule and repository settings are kept.
uninstall_pika_backup() {
    info "Uninstalling Pika Backup..."
    native_or_flatpak_uninstall org.gnome.World.PikaBackup pika-backup
}

update_pika_backup() {
    info "Updating Pika Backup..."
    native_or_flatpak_update org.gnome.World.PikaBackup pika-backup
}

get_version_pika_backup() { native_or_flatpak_version org.gnome.World.PikaBackup pika-backup; }
