#!/bin/bash
# Nix package manager installer functions
#
# Nix is a powerful, cross-distro, purely-functional package manager. It works
# alongside the native package manager on all supported families.
#
# We use the Determinate Systems nix-installer rather than the official
# nixos.org script: it installs non-interactively (--no-confirm) and, crucially,
# provides a clean `nix-installer uninstall` path. The upstream installer's
# teardown is manual and error-prone.
# Project: https://github.com/DeterminateSystems/nix-installer

# --- Nix ---

_NIX_INSTALLER_BIN="/nix/nix-installer"

check_nix() { command -v nix &>/dev/null || [[ -x "$_NIX_INSTALLER_BIN" ]]; }

install_nix() {
    info "Installing Nix (via the Determinate Systems installer)..."
    if [[ $EUID -eq 0 ]]; then
        error "Run this tool as a normal user to install Nix; the installer will use sudo where needed."
        return 1
    fi
    ensure_tools
    # Multi-user (daemon) install, no interactive confirmation.
    if ! curl --proto '=https' --tlsv1.2 -sSfL https://install.determinate.systems/nix \
            | sh -s -- install --no-confirm; then
        error "Nix installation failed."
        return 1
    fi
    info "Nix installed. Open a new shell (the installer wires up your profile) then try: nix --version"
    info "Search/install packages with: nix profile install nixpkgs#<package>"
}

uninstall_nix() {
    info "Uninstalling Nix..."
    warn "This removes the Nix store and everything installed through it."
    if [[ -x "$_NIX_INSTALLER_BIN" ]]; then
        sudo "$_NIX_INSTALLER_BIN" uninstall --no-confirm 2>/dev/null \
            || sudo "$_NIX_INSTALLER_BIN" uninstall 2>/dev/null \
            || { error "Automatic uninstall failed. See https://github.com/DeterminateSystems/nix-installer#uninstalling"; return 1; }
    else
        error "nix-installer not found at ${_NIX_INSTALLER_BIN}; cannot uninstall automatically."
        error "If Nix was installed another way, follow that installer's uninstall steps."
        return 1
    fi
}

update_nix() {
    info "Updating Nix and channels..."
    nix-channel --update 2>/dev/null || true
    # Upgrade the nix package itself (daemon installs need root).
    sudo nix upgrade-nix 2>/dev/null || nix upgrade-nix 2>/dev/null || \
        warn "Could not upgrade the nix binary automatically; channels were refreshed."
}

get_version_nix() {
    _ver_from_cmd nix --version || echo ""
}
