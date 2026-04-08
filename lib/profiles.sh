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
#                "Num Lock at Boot"  "Local Time Zone / Locale"
#                "Create Snapshot"  "Restore Snapshot"
#                "Command-Not-Found Prompt" (Ubuntu/Kubuntu/Neon)
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
# Developer Workstation — targets a software-developer desktop: firewall,
# SSH server, containers, editor, version control tooling, API testing,
# database GUI, password manager, and a polished shell environment.
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
    _profile_select_task        "UFW Firewall"
    _profile_select_for_install "OpenSSH Server"
    _profile_select_for_install "Docker"
    _profile_select_for_install "Visual Studio Code"
    _profile_select_for_install "GitHub CLI"
    _profile_select_for_install "NVM"
    _profile_select_for_install "Postman"
    _profile_select_for_install "DBeaver"
    _profile_select_for_install "Bitwarden Client"
    _profile_select_for_install "Btop"
    _profile_select_for_install "Zsh + Oh My Zsh"
    _profile_select_for_install "Fastfetch"
}
register_profile "Custom Profile 1" \
    _profile_custom_1 \
    "Developer workstation: UFW, OpenSSH Server, Docker, VSCode, GitHub CLI, NVM, Postman, DBeaver, Bitwarden Client, Btop, Zsh + Oh My Zsh, Fastfetch."

# ----------------------------------------------------------------------------
# Profile 5 — Custom Profile 2
#
# Home Desktop — privacy- and productivity-focused daily-driver profile:
# open-source browser, email, messaging, office suite, image editor,
# cloud sync, notes, torrent client, VPN, and a polished shell environment.
# ----------------------------------------------------------------------------
_profile_custom_2() {
    _profile_select_task        "Flatpak Setup"
    _profile_select_for_install "Firefox"
    _profile_select_for_install "Thunderbird"
    _profile_select_for_install "Signal Desktop"
    _profile_select_for_install "LibreOffice"
    _profile_select_for_install "GIMP"
    _profile_select_for_install "Nextcloud Desktop"
    _profile_select_for_install "Bitwarden Client"
    _profile_select_for_install "Joplin Client"
    _profile_select_for_install "QBittorrent"
    _profile_select_for_install "ProtonVPN"
    _profile_select_for_install "Btop"
    _profile_select_for_install "Zsh + Oh My Zsh"
    _profile_select_for_install "Fastfetch"
}
register_profile "Custom Profile 2" \
    _profile_custom_2 \
    "Home desktop: Flatpak, Firefox, Thunderbird, Signal, LibreOffice, GIMP, Nextcloud Desktop, Bitwarden Client, Joplin Client, QBittorrent, ProtonVPN, Btop, Zsh + Oh My Zsh, Fastfetch."

# ============================================================================
# Profile Export / Import
# ============================================================================

# Export the currently registered profiles — or a single named profile — to a
# JSON file that can be shared between machines and re-applied with
# --import-profile.
#
# The JSON schema:
#   {
#     "linux_util_profile_export": true,
#     "version": 1,
#     "exported_at": "<ISO-8601 timestamp>",
#     "profiles": [
#       {
#         "label": "<display name>",
#         "description": "<one-line description>",
#         "utilities": ["Utility A", "Utility B", ...]
#       },
#       ...
#     ]
#   }
#
# Usage: profile_export "<profile label>" "<output file>"
#        profile_export ""               "<output file>"   # all profiles
profile_export() {
    local target_label="$1" outfile="$2"

    if [[ -z "$outfile" ]]; then
        echo "Error: --export-profile requires: <profile name> <output file>" >&2
        return 1
    fi

    # Collect matching profile indices
    local -a indices=()
    local i total=${#PROFILES[@]}
    if [[ -z "$target_label" ]]; then
        for (( i=0; i<total; i++ )); do indices+=("$i"); done
    else
        for (( i=0; i<total; i++ )); do
            if [[ "${PROFILES[$i]}" == "$target_label" ]]; then
                indices+=("$i")
            fi
        done
        if [[ ${#indices[@]} -eq 0 ]]; then
            echo "Error: No profile found matching '${target_label}'." >&2
            echo "Available profiles:" >&2
            for (( i=0; i<total; i++ )); do
                echo "  ${PROFILES[$i]}" >&2
            done
            return 1
        fi
    fi

    # Build JSON — pure bash, no external deps required.
    # For each profile, utility names are captured by running the profile
    # function in a process-substitution subshell with stub helpers that
    # simply echo each name to stdout. The parent shell's functions and
    # arrays are unaffected.
    local json
    json="{\n"
    json+="  \"linux_util_profile_export\": true,\n"
    json+="  \"version\": 1,\n"
    json+="  \"exported_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\n"
    json+="  \"profiles\": [\n"

    local first_profile=true
    for idx in "${indices[@]}"; do
        local label="${PROFILES[$idx]}"
        local desc="${PROFILE_DESC[$idx]:-}"
        local func="${PROFILE_FUNCS[$idx]:-}"

        # Collect utility names by running the profile function in a subshell
        # with stub helpers — zero side effects on the live selection state.
        local -a _util_names=()
        if [[ -n "$func" ]] && declare -f "$func" &>/dev/null; then
            mapfile -t _util_names < <(
                _profile_select_for_install() { echo "$1"; }
                _profile_select_for_update()  { echo "$1"; }
                _profile_select_task()        { echo "$1"; }
                "$func"
            )
        fi

        [[ "$first_profile" == "true" ]] || json+=",\n"
        first_profile=false

        json+="    {\n"
        json+="      \"label\": $(printf '%s' "\"${label//\"/\\\"}\""),\n"
        json+="      \"description\": $(printf '%s' "\"${desc//\"/\\\"}\""),\n"
        json+="      \"utilities\": ["

        local first_util=true
        for uname in "${_util_names[@]}"; do
            [[ "$first_util" == "true" ]] || json+=", "
            first_util=false
            json+="\"${uname//\"/\\\"}\""
        done
        json+="]\n"
        json+="    }"
    done

    json+="\n  ]\n}"

    # Write output
    printf "%b" "$json" > "$outfile"
    echo "Profile(s) exported to: ${outfile}"
}

# Import profiles from a JSON file produced by profile_export / --export-profile.
# For each profile entry in the file, pre-selects utilities for install/update
# then runs linux_util.sh non-interactively (respecting --dry-run).
#
# Usage: profile_import "<input file>"
profile_import() {
    local infile="$1"

    if [[ -z "$infile" ]]; then
        echo "Error: --import-profile requires an input file path." >&2
        return 1
    fi
    if [[ ! -f "$infile" ]]; then
        echo "Error: File not found: ${infile}" >&2
        return 1
    fi

    # Basic integrity check — must look like our export format
    if ! grep -q '"linux_util_profile_export": true' "$infile" 2>/dev/null; then
        echo "Error: ${infile} does not appear to be a linux_util profile export." >&2
        return 1
    fi

    echo "Importing profile from: ${infile}"

    # Extract utility names using only grep/sed (no jq required).
    # Works for the flat JSON structure produced by profile_export.
    local -a utilities=()
    mapfile -t utilities < <(
        grep '"utilities"' -A 9999 "$infile" |
        grep -oP '"[^"]+"' |
        grep -v '"utilities"' |
        sed 's/^"//;s/"$//'
    )

    if [[ ${#utilities[@]} -eq 0 ]]; then
        echo "Warning: No utilities found in ${infile}. Nothing to do." >&2
        return 0
    fi

    echo "Utilities to install/update (${#utilities[@]}):"
    local u
    for u in "${utilities[@]}"; do
        echo "  - ${u}"
    done
    echo ""

    local failed=0
    for u in "${utilities[@]}"; do
        local resolved
        resolved=$(resolve_utility_name "$u" 2>/dev/null) || {
            echo "  Skipping unknown utility: ${u}"
            continue
        }
        local install_func="${INSTALL_FUNCS[$resolved]:-}"
        if [[ -z "$install_func" ]] || ! declare -f "$install_func" &>/dev/null; then
            echo "  Skipping (no install function): ${resolved}"
            continue
        fi
        echo "Installing: ${resolved}"
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            echo "  (dry-run — skipped)"
        else
            _cli_op install "$resolved" "$install_func" || (( failed++ )) || true
        fi
    done

    echo ""
    echo "Import complete. Failed: ${failed}."
    return $(( failed > 0 ? 1 : 0 ))
}
