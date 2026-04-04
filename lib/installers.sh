#!/bin/bash

# ============================================================================
# Linux Utilities - Installers Module
# Loads per-utility installer scripts and registers all utilities/system tasks.
#
# WHEN ADDING A NEW UTILITY, FOLLOW THIS CHECKLIST:
# ┌─ Step 1: Create a new file in lib/installers/ (e.g. lib/installers/foobar.sh)
# │  It will be sourced automatically — no loader changes needed.
# │
# ├─ Step 2: Implement required functions in that file:
# │  REQUIRED (4 functions):
# │    ├─ install_foobar()   — main installation logic
# │    ├─ check_foobar()     — returns 0 if installed, 1 if missing
# │    ├─ uninstall_foobar() — remove utility and cleanup
# │    └─ update_foobar()    — update to latest version
# │
# │  OPTIONAL (1 function):
# │    └─ get_version_foobar() — outputs clean version string "X.Y.Z"
# │
# ├─ Step 3: Add a register_utility line below (alphabetical order in the
# │  Utilities section). For system tasks, use register_system_task instead.
# │
# └─ Step 4: Test with --dry-run and verify menu rendering
# ============================================================================

# --- Source all per-utility installer scripts ---
for _installer_file in "${SCRIPT_DIR}/lib/installers/"*.sh; do
    [[ -f "$_installer_file" ]] || continue
    source "$_installer_file" || { echo "Error: Failed to source $_installer_file"; exit 1; }
done
unset _installer_file

# --- Shared helper functions ---
noop_function() {
    return 0
}

check_always_false() {
    return 1
}

# --- System Tasks (must be registered before utilities) ---
register_system_task "Full System Upgrade/Update" setup_full_update check_always_false noop_function setup_full_update
NO_RETRY["Full System Upgrade/Update"]=1
register_system_task "System Updates"     setup_system_updates    check_always_false    noop_function             setup_system_updates
register_system_task "KDE Desktop"        install_kde             check_kde             uninstall_kde             update_kde                get_version_kde
register_system_task "NVIDIA Drivers"     install_nvidia_drivers  check_nvidia_drivers  uninstall_nvidia_drivers  update_nvidia_drivers     get_version_nvidia_drivers
register_system_task "XEN Guest Utilities" setup_xen_guest_utilities check_xen_guest_utilities uninstall_xen_guest_utilities setup_xen_guest_utilities get_version_xen_guest_utilities
register_system_task "Enable RDP"         install_enable_rdp      check_enable_rdp      uninstall_enable_rdp      update_enable_rdp         get_version_enable_rdp

# Landscape MOTD (Ubuntu, Kubuntu, KDE Neon)
if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "kubuntu" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
    register_system_task "Local MOTD"    setup_local_motd        check_landscape_motd  uninstall_landscape_motd  update_landscape_motd     get_version_landscape_motd
fi

# Command-not-found auto-install prompt (Ubuntu, Kubuntu, KDE Neon)
# Prerequisite: enables interactive y/N install prompt for missing commands in bash.
# Dotfiles installer will additionally apply the zsh handler when zsh is set up.
if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "kubuntu" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
    register_system_task "Command-Not-Found Prompt" setup_command_not_found check_command_not_found uninstall_command_not_found update_command_not_found
fi

# Snapshot tasks (Create / Restore) — runtime checks for available backend
register_system_task "Create Snapshot"   setup_create_snapshot   check_always_false    noop_function             setup_create_snapshot
register_system_task "Restore Snapshot"  setup_restore_snapshot  check_always_false    noop_function             setup_restore_snapshot
NO_RETRY["Restore Snapshot"]=1

# --- Utilities (alphabetical order) ---
register_utility "Bitwarden Client"    install_bitwarden       check_bitwarden       uninstall_bitwarden       update_bitwarden          get_version_bitwarden
register_utility "Brave Browser"       install_brave           check_brave           uninstall_brave           update_brave              get_version_brave
register_utility "Claude Code"         install_claude_code     check_claude_code     uninstall_claude_code     update_claude_code        get_version_claude_code
register_utility "Devolutions RDM"     install_devolutions_rdm check_devolutions_rdm uninstall_devolutions_rdm update_devolutions_rdm    get_version_devolutions_rdm
register_utility "Docker"              setup_install_docker    check_docker          uninstall_docker          update_docker             get_version_docker
register_utility "Dotfiles"            setup_install_dotfiles  check_dotfiles        uninstall_dotfiles        setup_install_dotfiles
register_utility "Feral Gamemode"      install_gamemode        check_gamemode        uninstall_gamemode        update_gamemode            get_version_gamemode
register_utility "Joplin Client"       install_joplin          check_joplin          uninstall_joplin          update_joplin             get_version_joplin
register_utility "LibreOffice"         install_libreoffice     check_libreoffice     uninstall_libreoffice     update_libreoffice        get_version_libreoffice
register_utility "OpenSSH Server"      install_openssh_server  check_openssh_server  uninstall_openssh_server  update_openssh_server     get_version_openssh_server
register_utility "PIA VPN"             install_pia_vpn         check_pia_vpn         uninstall_pia_vpn         update_pia_vpn            get_version_pia_vpn
register_utility "QBittorrent"         install_qbittorrent     check_qbittorrent     uninstall_qbittorrent     update_qbittorrent        get_version_qbittorrent
register_utility "Steam App"           install_steam           check_steam           uninstall_steam           update_steam              get_version_steam
register_utility "Syncthing"           install_syncthing       check_syncthing       uninstall_syncthing       update_syncthing          get_version_syncthing
register_utility "Termius SSH Client"  install_termius         check_termius         uninstall_termius         update_termius            get_version_termius
register_utility "Timeshift"           install_timeshift       check_timeshift       uninstall_timeshift       update_timeshift          get_version_timeshift
register_utility "Visual Studio Code"  install_vscode          check_vscode          uninstall_vscode          update_vscode             get_version_vscode

# --- Category definitions ---
# The order here determines the tab order in the left panel.
CATEGORIES=("System Tasks" "Development" "Gaming" "Internet" "Productivity" "System Tools")

# Category assignment for each utility (System Tasks are identified by SYSTEM_TASKS array)
UTILITY_CATEGORY["Brave Browser"]="Internet"
UTILITY_CATEGORY["Claude Code"]="Development"
UTILITY_CATEGORY["Devolutions RDM"]="Productivity"
UTILITY_CATEGORY["Docker"]="Development"
UTILITY_CATEGORY["Dotfiles"]="System Tools"
UTILITY_CATEGORY["Feral Gamemode"]="Gaming"
UTILITY_CATEGORY["Joplin Client"]="Productivity"
UTILITY_CATEGORY["LibreOffice"]="Productivity"
UTILITY_CATEGORY["OpenSSH Server"]="Internet"
UTILITY_CATEGORY["PIA VPN"]="Internet"
UTILITY_CATEGORY["QBittorrent"]="Internet"
UTILITY_CATEGORY["Steam App"]="Gaming"
UTILITY_CATEGORY["Syncthing"]="Internet"
UTILITY_CATEGORY["Termius SSH Client"]="Internet"
UTILITY_CATEGORY["Timeshift"]="System Tools"
UTILITY_CATEGORY["Bitwarden Client"]="Productivity"
UTILITY_CATEGORY["Visual Studio Code"]="Development"
