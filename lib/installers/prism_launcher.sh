#!/bin/bash
# Prism Launcher installer functions
#
# The distro package where a repository has one (Ubuntu 26.04, Arch, openSUSE,
# Alpine); everywhere else Prism's own Flathub listing. Minecraft launcher
# with separate instances per game version and mod loader.

# --- Prism Launcher ---

check_prism_launcher() { _check_standard prismlauncher prismlauncher org.prismlauncher.PrismLauncher; }

install_prism_launcher() {
    info "Installing Prism Launcher..."
    native_or_flatpak_install org.prismlauncher.PrismLauncher prismlauncher || return 1
    info "Prism Launcher installed."
}

# Your instances, worlds and accounts are kept.
uninstall_prism_launcher() {
    info "Uninstalling Prism Launcher..."
    native_or_flatpak_uninstall org.prismlauncher.PrismLauncher prismlauncher
}

update_prism_launcher() {
    info "Updating Prism Launcher..."
    native_or_flatpak_update org.prismlauncher.PrismLauncher prismlauncher
}

get_version_prism_launcher() { native_or_flatpak_version org.prismlauncher.PrismLauncher prismlauncher; }
