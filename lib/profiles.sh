#!/bin/bash

# ============================================================================
# Linux Utilities - Profiles Module
# Provides curated selection presets ("profiles") that pre-populate the
# install/update queue for common system configurations.
#
# ── DISTRO COMPATIBILITY ──────────────────────────────────────────────────
# This project supports Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, and
# openSUSE. These profiles were designed and primarily tested on
# Ubuntu/Debian-based systems. However, all helper functions
# (_profile_select_for_install, etc.) silently skip utility names that are
# not registered on the current distro — distro-restricted utilities in
# installers.sh are conditionally registered, so they simply won't exist in
# UTILITIES[] on an incompatible system and will be no-ops here. Profiles
# are safe to apply on any supported distro; unavailable items are ignored.
#
# ── HOW TO CUSTOMISE A PROFILE ───────────────────────────────────────────
# 1. Find the _profile_<name>() function below and edit its body.
# 2. Add _profile_select_for_install / _profile_select_for_update /
#    _profile_select_task calls to match your desired setup.
# 3. Update the register_profile description string to match your changes.
# 4. No other files need to be modified — restart menu to see changes.
#
# ── HOW TO ADD A NEW PROFILE ─────────────────────────────────────────────
# 1. Define a new function following the _profile_<slug>() naming pattern.
# 2. Add a corresponding register_profile call at the bottom of this file.
#
# ── AVAILABLE UTILITY NAMES (pass to helpers exactly as shown) ───────────
# System Tasks:  "Full System Upgrade/Update"  "System Updates"
#                "NVIDIA Drivers"  "XEN Guest Utilities"  "Enable RDP"
#                "AMD Drivers"  "Flatpak Setup"  "UFW Firewall"
#                "Num Lock at Boot"  "Create Snapshot"  "Restore Snapshot"
#                "Local MOTD"  "Command-Not-Found Prompt" (Ubuntu/Kubuntu/Neon)
# Utilities:     "Bitwarden Client"  "Bitwarden Extension"  "Bottles"
#                "Brave Browser"  "Btop"  "Claude Code"  "Cursor IDE"
#                "DBeaver"  "Devolutions RDM"  "Discord"  "Docker"
#                "Fastfetch"  "Feral Gamemode"  "FileZilla"
#                "Firefox"  "GIMP"  "GitHub CLI"  "Google Chrome"
#                "Heroic Games Launcher"  "JetBrains Toolbox"
#                "Joplin Client"  "Joplin Web Clipper"  "KMail"
#                "LibreOffice"  "Lutris"  "MangoHud"  "Nextcloud Desktop"
#                "NVM"  "OBS Studio"  "Obsidian"  "OnlyOffice"
#                "OpenSSH Server"  "PIA VPN"  "Postman"  "ProtonUp-Qt"
#                "ProtonVPN"  "QBittorrent"  "Remmina"  "Signal Desktop"
#                "SponsorBlock Extension"  "Stacer"  "Standard Notes"
#                "Steam App"  "Syncthing"  "Tailscale"  "Telegram Desktop"
#                "Termius SSH Client"  "Thorium Browser"  "Thunderbird"
#                "Timeshift"  "Visual Studio Code"  "Vivaldi Browser"
#                "WireGuard Client"  "WireGuard Server"  "WPS Office"
#                "Zsh + Oh My Zsh"
# ============================================================================

# ============================================================================
# Profile Registry
# ============================================================================

# Parallel arrays — each array index is one profile entry.
declare -a PROFILES=()       # Display labels shown in the left panel
declare -a PROFILE_FUNCS=()  # Function name invoked when the profile is applied
declare -a PROFILE_DESC=()   # Single-sentence description (shown in info panel)

# Register a profile.
# Usage: register_profile "Display Label" function_name "Short description."
register_profile() {
    local label="$1" func="$2" desc="$3"
    PROFILES+=("$label")
    PROFILE_FUNCS+=("$func")
    PROFILE_DESC+=("$desc")
}

# ============================================================================
# Profile Application
# ============================================================================

# Apply a profile by 0-based index. Clears all existing SELECTED[] and
# UPDATE_SELECTED[] flags, then calls the profile function to re-populate them.
# Usage: apply_profile <index>
apply_profile() {
    local profile_idx="$1"
    local total=${#UTILITIES[@]}

    # Reset all selections before applying the new profile
    for (( i=0; i<total; i++ )); do
        SELECTED[$i]=0
        UPDATE_SELECTED[$i]=0
    done

    local func="${PROFILE_FUNCS[$profile_idx]:-}"
    if [[ -n "$func" ]] && declare -f "$func" &>/dev/null; then
        "$func"
    fi
}

# ============================================================================
# Helper Functions
# ----------------------------------------------------------------------------
# Each helper silently no-ops if the named utility/task is not registered on
# the current distro rather than producing an error. This ensures profiles are
# safe to apply across all supported distributions and during dry-run mode.
# ============================================================================

# Mark a utility for install, or for update if it is already installed.
# Silently no-ops if the utility is not registered on the current distro.
# Usage: _profile_select_for_install "Utility Name"
_profile_select_for_install() {
    local name="$1"
    local total=${#UTILITIES[@]}
    for (( i=0; i<total; i++ )); do
        if [[ "${UTILITIES[$i]}" == "$name" ]]; then
            if [[ ${INSTALLED[$i]:-0} -eq 1 ]]; then
                # Already installed — queue for update instead
                UPDATE_SELECTED[$i]=1
                SELECTED[$i]=0
            else
                SELECTED[$i]=1
                UPDATE_SELECTED[$i]=0
            fi
            return 0
        fi
    done
    # Utility not registered on this distro — silently skip
    return 0
}

# Mark an installed utility for update. Skips if not installed or not registered.
# Usage: _profile_select_for_update "Utility Name"
_profile_select_for_update() {
    local name="$1"
    local total=${#UTILITIES[@]}
    for (( i=0; i<total; i++ )); do
        if [[ "${UTILITIES[$i]}" == "$name" ]]; then
            if [[ ${INSTALLED[$i]:-0} -eq 1 ]]; then
                UPDATE_SELECTED[$i]=1
                SELECTED[$i]=0
            fi
            return 0
        fi
    done
    return 0
}

# Mark a system task for execution. Skips if not registered.
# System tasks always appear as uninstalled (check function returns false),
# so SELECTED[$i]=1 is used regardless of state.
# Usage: _profile_select_task "Task Name"
_profile_select_task() {
    local name="$1"
    local total=${#UTILITIES[@]}
    for (( i=0; i<total; i++ )); do
        if [[ "${UTILITIES[$i]}" == "$name" ]]; then
            SELECTED[$i]=1
            UPDATE_SELECTED[$i]=0
            return 0
        fi
    done
    return 0
}

# ============================================================================
# Profile Definitions
# ============================================================================

# ----------------------------------------------------------------------------
# Profile 1 — Run Me First
#
# Intended as the very first action on a freshly installed system. Installs
# Timeshift so a restore point exists before any other changes are made.
# After installation, the Timeshift installer will offer to create an initial
# snapshot immediately.
#
# DISTRO NOTE:
#   Timeshift is available on all supported distros:
#     • Debian/Ubuntu  — installed via apt
#     • Fedora         — installed via dnf/yum
#     • RHEL/Alma/Rocky — installed via EPEL (enabled automatically)
#     • Arch/Manjaro   — installed via pacman; resolves Snapper conflict on
#                        CachyOS if present
#     • openSUSE       — installed via zypper
# ----------------------------------------------------------------------------
_profile_run_me_first() {
    _profile_select_for_install "Timeshift"
}
register_profile "Run Me First" \
    _profile_run_me_first \
    "Fresh system starting point: installs Timeshift so you have a restore point before making any other changes."

# ----------------------------------------------------------------------------
# Profile 2 — Default VM Server Profile
#
# Lightweight profile for virtual machines running under a Xen hypervisor.
# Installs Xen Guest Utilities (or updates them if already present), plus
# Btop for live resource monitoring and Zsh + Oh My Zsh for an improved
# interactive shell experience.
#
# DISTRO NOTE:
#   • Xen Guest Utilities are available on all supported distros (package
#     name varies: xe-guest-utilities on Debian/Ubuntu, xen-guest-agent on
#     Fedora/RHEL, xen-guest-utilities on Arch via AUR, xen-tools on openSUSE).
#   • Btop is in the standard repositories of all supported distros.
#   • Oh My Zsh is installed via its official curl-based installer script
#     and is entirely distribution-agnostic.
# ----------------------------------------------------------------------------
_profile_default_vm_server() {
    _profile_select_for_install "XEN Guest Utilities"
    _profile_select_for_install "Btop"
    _profile_select_for_install "Zsh + Oh My Zsh"
}
register_profile "Default VM Server Profile" \
    _profile_default_vm_server \
    "Xen VM guest setup: marks Xen Guest Utilities for upgrade, installs Btop and Zsh + Oh My Zsh."

# ----------------------------------------------------------------------------
# Profile 3 — Default Physical PC
#
# Complete desktop workstation profile covering daily-driver essentials:
# system visibility tools, development, productivity, remote access, and
# gaming.
#
# DISTRO NOTE:
#   • All included utilities support Debian/Ubuntu. Most also support other
#     distros — check installer output for any per-distro caveats.
#   • Devolutions RDM has official .deb/.rpm packages; see
#     https://devolutions.net/remote-desktop-manager/linux/ for distro support.
#   • Steam App works best when the 32-bit multilib repository is enabled;
#     the Steam installer handles this automatically on Debian/Ubuntu/Arch.
#   • "Num Lock at Boot" configures the display manager (GDM, SDDM, LightDM)
#     to enable Num Lock on startup — works on all supported distros that use
#     a display manager.
# ----------------------------------------------------------------------------
_profile_default_physical_pc() {
    _profile_select_task        "Num Lock at Boot"
    _profile_select_for_install "Visual Studio Code"
    _profile_select_for_install "GitHub CLI"
    _profile_select_for_install "Steam App"
    _profile_select_for_install "Brave Browser"
    _profile_select_for_install "Devolutions RDM"
    _profile_select_for_install "Termius SSH Client"
    _profile_select_for_install "Bitwarden Extension"
    _profile_select_for_install "Joplin Client"
    _profile_select_for_install "Joplin Web Clipper"
    _profile_select_for_install "SponsorBlock Extension"
    _profile_select_for_install "Btop"
    _profile_select_for_install "Zsh + Oh My Zsh"
    _profile_select_for_install "Fastfetch"
}
register_profile "Default Physical PC" \
    _profile_default_physical_pc \
    "Desktop workstation: Num Lock, VSCode, GitHub CLI, Steam, Brave, Devolutions RDM, Termius, Bitwarden Extension, Joplin, Joplin Web Clipper, SponsorBlock Extension, Btop, Zsh + Oh My Zsh, Fastfetch."

# ----------------------------------------------------------------------------
# Profile 4 — Custom Profile 1
#
# Blank template for a user-defined profile. See the instructions below to
# customise it for your own use case.
#
# HOW TO CUSTOMISE:
#   1. Replace the ':' placeholder below with your own selections, e.g.:
#        _profile_select_for_install "Visual Studio Code"
#        _profile_select_for_install "Docker"
#        _profile_select_task        "UFW Firewall"
#   2. Update the register_profile description string further below.
#   3. Optionally rename the function and the profile label to something
#      more descriptive (update both the function definition AND the
#      register_profile call to match).
#
# AVAILABLE HELPERS:
#   _profile_select_for_install "Name"  — mark for install (skipped if installed)
#   _profile_select_for_update  "Name"  — mark for update  (skipped if not installed)
#   _profile_select_task        "Name"  — mark a system task (e.g. "UFW Firewall")
#
# UTILITY NAMES must match the exact strings used in installers.sh.
# See the reference list at the top of this file for all valid names.
# ----------------------------------------------------------------------------
_profile_custom_1() {
    # ── Replace the placeholder below with your own selections ──────────────
    :  # no-op placeholder — remove this line once you add real selections
    # _profile_select_for_install "Example Utility"
    # _profile_select_for_update  "Already Installed Utility"
    # _profile_select_task        "System Task Name"
}
register_profile "Custom Profile 1" \
    _profile_custom_1 \
    "User-defined profile. Edit _profile_custom_1() in lib/profiles.sh to add your utility selections."

# ----------------------------------------------------------------------------
# Profile 5 — Custom Profile 2
#
# Second blank template for a user-defined profile.
# See the Profile 4 comments above for full customisation instructions.
# ----------------------------------------------------------------------------
_profile_custom_2() {
    # ── Replace the placeholder below with your own selections ──────────────
    :  # no-op placeholder — remove this line once you add real selections
    # _profile_select_for_install "Example Utility"
    # _profile_select_for_update  "Already Installed Utility"
    # _profile_select_task        "System Task Name"
}
register_profile "Custom Profile 2" \
    _profile_custom_2 \
    "User-defined profile. Edit _profile_custom_2() in lib/profiles.sh to add your utility selections."
