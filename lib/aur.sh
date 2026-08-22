#!/bin/bash

# ============================================================================
# Linux Utilities - AUR Module
# Provides Arch User Repository (AUR) functions for Arch/Manjaro systems
# ============================================================================

# AUR support is disabled by default, pending review of AUR-related security
# concerns (see the KDE Linux project's decision to drop AUR support). Set
# AUR_ENABLED=true in the environment to re-enable installing/building
# packages from the AUR. Removing already-installed AUR packages (aur_remove)
# is not affected — that's cleanup, not new AUR usage.
AUR_ENABLED="${AUR_ENABLED:-false}"

_aur_disabled_msg() {
    echo "Error: AUR support is currently disabled in this tool (pending review of AUR security concerns)."
    echo "Set AUR_ENABLED=true to re-enable it."
}

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
    [[ "$AUR_ENABLED" == "true" ]] || { _aur_disabled_msg; return 1; }
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

# True when pacman can resolve the package from a configured repo (no AUR).
# Answers are cached for the life of the run — the menu probes this for every
# AUR-only entry on each redraw, and pacman -Si is a local sync-db lookup.
declare -A _ARCH_REPO_PROBE=()
arch_repo_has() {
    local pkg="$1"
    [[ "${PKG_MGR:-}" == "pacman" ]] || return 1
    if [[ -z "${_ARCH_REPO_PROBE[$pkg]:-}" ]]; then
        if pacman -Si "$pkg" &>/dev/null; then
            _ARCH_REPO_PROBE["$pkg"]=yes
        else
            _ARCH_REPO_PROBE["$pkg"]=no
        fi
    fi
    [[ "${_ARCH_REPO_PROBE[$pkg]}" == "yes" ]]
}

# Install a package, preferring a configured repo and falling back to the AUR
# only if it is missing there.
#
# Use this instead of aur_ensure for everything. It matters in both directions:
# a derivative with a smaller repo set than Arch (aur_ensure with no helper drops
# to aur_build, which clones aur.archlinux.org/<pkg>.git — nonexistent for a
# repo-only package, so the install fails outright), and a derivative with a
# LARGER set. CachyOS ships brave-bin, google-chrome and other AUR-name packages
# in its own repos, so aur_ensure there demanded an AUR helper and AUR_ENABLED=true
# for packages plain pacman could install.
repo_or_aur() {
    sudo pacman -S --noconfirm --needed "$@" 2>/dev/null && return 0
    aur_ensure "$@"
}

# Install a package that has no official Arch repo build, preferring Flathub over
# the AUR so the system does not have to build and trust an unreviewed PKGBUILD.
#
# A native repo package beats both and is tried first: it is signed by the distro
# and needs no runtime stack. "No official Arch repo build" is only true of
# upstream Arch — derivatives such as CachyOS carry many of these packages
# themselves, so probe before falling through to Flathub.
#
# Only takes the Flatpak route when flatpak is already installed — a system with
# no flatpak has not opted into it, and pulling in the whole runtime stack to
# avoid one AUR package would be a worse trade. ensure_flatpak still runs in that
# case, but only to add the flathub remote (has_flatpak short-circuits the
# install branch inside it).
#
# Usage: flatpak_or_aur <flathub-app-id> <aur-package> [repo-package]
# repo-package defaults to <aur-package>; pass it when the repo name differs.
flatpak_or_aur() {
    local flatpak_id="$1" aur_pkg="$2" repo_pkg="${3:-$2}"
    if arch_repo_has "$repo_pkg"; then
        sudo pacman -S --noconfirm --needed "$repo_pkg" 2>/dev/null && return 0
        warn "Repo install of ${repo_pkg} failed; falling back to Flatpak/AUR."
    fi
    if has_flatpak && ensure_flatpak; then
        flatpak install -y flathub "$flatpak_id" && return 0
        warn "Flatpak install of ${flatpak_id} failed; falling back to the AUR."
    fi
    aur_ensure "$aur_pkg"
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
    [[ "$AUR_ENABLED" == "true" ]] || { _aur_disabled_msg; return 1; }
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
