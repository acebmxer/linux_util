#!/bin/bash

# ============================================================================
# Linux Utilities - AUR Module
# Provides Arch User Repository (AUR) functions for Arch/Manjaro systems
# ============================================================================

has_aur_helper() {
    command -v yay &>/dev/null || command -v paru &>/dev/null
}

# Internal: run yay or paru with the given arguments. Returns 1 if neither is found.
_aur_helper_run() {
    if command -v yay &>/dev/null; then
        yay "$@"
    elif command -v paru &>/dev/null; then
        paru "$@"
    else
        return 1
    fi
}

aur_install() {
    has_aur_helper || { echo "Error: No AUR helper found. Please install yay or paru first."; return 1; }
    _aur_helper_run -S --noconfirm "$@" || { echo "Error: Failed to install from AUR: $*"; return 1; }
}

aur_upgrade() {
    aur_install "$@"
}

# Install or upgrade a package from AUR, using yay/paru if available, otherwise build from source.
aur_ensure() {
    if has_aur_helper; then
        aur_install "$@"
    else
        aur_build "$@"
    fi
}

aur_remove() {
    _aur_helper_run -Rs --noconfirm "$@" || sudo pacman -Rs --noconfirm "$@"
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
    [[ "$pkg_name" =~ ^[a-zA-Z0-9._-]+$ ]] || { warn "Invalid package name: $pkg_name"; return 1; }
    ensure_aur_build_deps
    local build_dir
    build_dir=$(mktemp -d) || { warn "Failed to create temp build directory"; return 1; }
    # Trap cleans up on any exit path (success, error, or signal) so partial
    # build artifacts never linger even if git clone or makepkg fails.
    # shellcheck disable=SC2064
    trap "rm -rf '$build_dir'" RETURN
    git clone "https://aur.archlinux.org/${pkg_name}.git" "$build_dir/${pkg_name}" || {
        warn "Failed to clone AUR package: $pkg_name"
        return 1
    }
    (cd "$build_dir/${pkg_name}" && makepkg -si --noconfirm)
}
