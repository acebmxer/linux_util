#!/bin/bash

# ============================================================================
# Linux Utilities - AUR Module
# Provides Arch User Repository (AUR) functions for Arch/Manjaro systems
# ============================================================================

has_aur_helper() {
    command -v yay &>/dev/null || command -v paru &>/dev/null
}

aur_install() {
    if command -v yay &>/dev/null; then
        yay -S --noconfirm "$@"
    elif command -v paru &>/dev/null; then
        paru -S --noconfirm "$@"
    else
        echo "Error: No AUR helper found. Please install yay or paru first."
        return 1
    fi
}

aur_remove() {
    if command -v yay &>/dev/null; then
        yay -Rs --noconfirm "$@"
    elif command -v paru &>/dev/null; then
        paru -Rs --noconfirm "$@"
    else
        sudo pacman -Rs --noconfirm "$@"
    fi
}

aur_upgrade() {
    if command -v yay &>/dev/null; then
        yay -S --noconfirm "$@"
    elif command -v paru &>/dev/null; then
        paru -S --noconfirm "$@"
    else
        echo "Error: No AUR helper found. Please install yay or paru first."
        return 1
    fi
}

# Ensure packages required to build AUR packages are present (Arch/Manjaro only)
ensure_aur_build_deps() {
    if [[ "$PKG_MGR" != "pacman" ]]; then
        return 0
    fi
    echo "Ensuring AUR build dependencies (base-devel, git)..."
    sudo pacman -S --noconfirm --needed base-devel git
}

# Build and install a package from AUR without a helper (yay/paru).
# Usage: aur_build <aur-package-name>
aur_build() {
    local pkg_name="$1"
    ensure_aur_build_deps
    local build_dir
    build_dir=$(mktemp -d)
    CLEANUP_FILES+=("$build_dir")
    git clone "https://aur.archlinux.org/${pkg_name}.git" "$build_dir/${pkg_name}"
    (cd "$build_dir/${pkg_name}" && makepkg -si --noconfirm)
    rm -rf "$build_dir"
}
