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
register_system_task "Full System Upgrade/Update" setup_full_update check_always_false noop_function setup_full_update get_version_full_update
NO_RETRY["Full System Upgrade/Update"]=1
register_system_task "System Updates"     setup_system_updates    check_always_false    noop_function             setup_system_updates      get_version_system_updates
register_system_task "KDE Desktop"        install_kde             check_kde             uninstall_kde             update_kde                get_version_kde
register_system_task "NVIDIA Drivers"     install_nvidia_drivers  check_nvidia_drivers  uninstall_nvidia_drivers  update_nvidia_drivers     get_version_nvidia_drivers
register_system_task "XEN Guest Utilities" setup_xen_guest_utilities check_xen_guest_utilities uninstall_xen_guest_utilities setup_xen_guest_utilities get_version_xen_guest_utilities
register_system_task "Enable RDP"         install_enable_rdp      check_enable_rdp      uninstall_enable_rdp      update_enable_rdp         get_version_enable_rdp
register_system_task "AMD Drivers"        install_amd_drivers     check_amd_drivers     uninstall_amd_drivers     update_amd_drivers        get_version_amd_drivers
register_system_task "Flatpak Setup"      install_flatpak_setup   check_flatpak_setup   uninstall_flatpak_setup   update_flatpak_setup      get_version_flatpak_setup
register_system_task "UFW Firewall"       install_ufw             check_ufw             uninstall_ufw             update_ufw                get_version_ufw
register_system_task "Num Lock at Boot"   install_numlock_boot    check_numlock_boot    uninstall_numlock_boot    update_numlock_boot       get_version_numlock_boot

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
NO_RETRY["Create Snapshot"]=1
register_system_task "Restore Snapshot"  setup_restore_snapshot  check_always_false    noop_function             setup_restore_snapshot
NO_RETRY["Restore Snapshot"]=1

# --- Utilities (alphabetical order) ---
register_utility "Bitwarden Client"    install_bitwarden        check_bitwarden        uninstall_bitwarden        update_bitwarden           get_version_bitwarden
register_utility "Bottles"             install_bottles          check_bottles          uninstall_bottles          update_bottles             get_version_bottles
register_utility "Brave Browser"       install_brave            check_brave            uninstall_brave            update_brave               get_version_brave
register_utility "Btop"                install_btop             check_btop             uninstall_btop             update_btop                get_version_btop
register_utility "Chromium"            install_chromium         check_chromium         uninstall_chromium         update_chromium            get_version_chromium
register_utility "Claude Code"         install_claude_code      check_claude_code      uninstall_claude_code      update_claude_code         get_version_claude_code
register_utility "Cursor IDE"          install_cursor           check_cursor           uninstall_cursor           update_cursor              get_version_cursor
register_utility "DBeaver"             install_dbeaver          check_dbeaver          uninstall_dbeaver          update_dbeaver             get_version_dbeaver
register_utility "Devolutions RDM"     install_devolutions_rdm  check_devolutions_rdm  uninstall_devolutions_rdm  update_devolutions_rdm     get_version_devolutions_rdm
register_utility "Discord"             install_discord          check_discord          uninstall_discord          update_discord             get_version_discord
register_utility "Docker"              setup_install_docker     check_docker           uninstall_docker           update_docker              get_version_docker
register_utility "Dotfiles"            setup_install_dotfiles   check_dotfiles         uninstall_dotfiles         setup_install_dotfiles
register_utility "Fastfetch"           install_fastfetch        check_fastfetch        uninstall_fastfetch        update_fastfetch           get_version_fastfetch
register_utility "Feral Gamemode"      install_gamemode         check_gamemode         uninstall_gamemode         update_gamemode            get_version_gamemode
register_utility "FileZilla"           install_filezilla        check_filezilla        uninstall_filezilla        update_filezilla           get_version_filezilla
register_utility "Firefox"             install_firefox          check_firefox          uninstall_firefox          update_firefox             get_version_firefox
register_utility "GIMP"                install_gimp             check_gimp             uninstall_gimp             update_gimp                get_version_gimp
register_utility "GitHub CLI"          install_github_cli       check_github_cli       uninstall_github_cli       update_github_cli          get_version_github_cli
register_utility "Google Chrome"       install_google_chrome    check_google_chrome    uninstall_google_chrome    update_google_chrome       get_version_google_chrome
register_utility "Heroic Games Launcher" install_heroic         check_heroic           uninstall_heroic           update_heroic              get_version_heroic
register_utility "JetBrains Toolbox"   install_jetbrains_toolbox check_jetbrains_toolbox uninstall_jetbrains_toolbox update_jetbrains_toolbox get_version_jetbrains_toolbox
register_utility "Joplin Client"       install_joplin           check_joplin           uninstall_joplin           update_joplin              get_version_joplin
register_utility "KMail"               install_kmail            check_kmail            uninstall_kmail            update_kmail               get_version_kmail
register_utility "LibreOffice"         install_libreoffice      check_libreoffice      uninstall_libreoffice      update_libreoffice         get_version_libreoffice
register_utility "Lutris"              install_lutris           check_lutris           uninstall_lutris           update_lutris              get_version_lutris
register_utility "MangoHud"            install_mangohud         check_mangohud         uninstall_mangohud         update_mangohud            get_version_mangohud
register_utility "Nextcloud Desktop"   install_nextcloud_desktop check_nextcloud_desktop uninstall_nextcloud_desktop update_nextcloud_desktop get_version_nextcloud_desktop
register_utility "NVM"                 install_nvm              check_nvm              uninstall_nvm              update_nvm                 get_version_nvm
register_utility "OBS Studio"          install_obs_studio       check_obs_studio       uninstall_obs_studio       update_obs_studio          get_version_obs_studio
register_utility "Obsidian"            install_obsidian         check_obsidian         uninstall_obsidian         update_obsidian            get_version_obsidian
register_utility "OnlyOffice"          install_onlyoffice       check_onlyoffice       uninstall_onlyoffice       update_onlyoffice          get_version_onlyoffice
register_utility "OpenSSH Server"      install_openssh_server   check_openssh_server   uninstall_openssh_server   update_openssh_server      get_version_openssh_server
register_utility "PIA VPN"             install_pia_vpn          check_pia_vpn          uninstall_pia_vpn          update_pia_vpn             get_version_pia_vpn
register_utility "Postman"             install_postman          check_postman          uninstall_postman          update_postman             get_version_postman
register_utility "ProtonUp-Qt"         install_protonup_qt      check_protonup_qt      uninstall_protonup_qt      update_protonup_qt         get_version_protonup_qt
register_utility "ProtonVPN"           install_protonvpn        check_protonvpn        uninstall_protonvpn        update_protonvpn           get_version_protonvpn
register_utility "QBittorrent"         install_qbittorrent      check_qbittorrent      uninstall_qbittorrent      update_qbittorrent         get_version_qbittorrent
register_utility "Remmina"             install_remmina          check_remmina          uninstall_remmina          update_remmina             get_version_remmina
register_utility "Signal Desktop"      install_signal           check_signal           uninstall_signal           update_signal              get_version_signal
register_utility "Stacer"              install_stacer           check_stacer           uninstall_stacer           update_stacer              get_version_stacer
register_utility "Standard Notes"      install_standard_notes   check_standard_notes   uninstall_standard_notes   update_standard_notes      get_version_standard_notes
register_utility "Steam App"           install_steam            check_steam            uninstall_steam            update_steam               get_version_steam
register_utility "Syncthing"           install_syncthing        check_syncthing        uninstall_syncthing        update_syncthing           get_version_syncthing
register_utility "Tailscale"           install_tailscale        check_tailscale        uninstall_tailscale        update_tailscale           get_version_tailscale
register_utility "Telegram Desktop"    install_telegram         check_telegram         uninstall_telegram         update_telegram            get_version_telegram
register_utility "Termius SSH Client"  install_termius          check_termius          uninstall_termius          update_termius             get_version_termius
register_utility "Thorium Browser"     install_thorium          check_thorium          uninstall_thorium          update_thorium             get_version_thorium
register_utility "Thunderbird"         install_thunderbird      check_thunderbird      uninstall_thunderbird      update_thunderbird         get_version_thunderbird
register_utility "Timeshift"           install_timeshift        check_timeshift        uninstall_timeshift        update_timeshift           get_version_timeshift
register_utility "Visual Studio Code"  install_vscode           check_vscode           uninstall_vscode           update_vscode              get_version_vscode
register_utility "Vivaldi Browser"     install_vivaldi          check_vivaldi          uninstall_vivaldi          update_vivaldi             get_version_vivaldi
register_utility "WireGuard Client"    install_wireguard_client check_wireguard_client uninstall_wireguard_client update_wireguard_client    get_version_wireguard_client
register_utility "WireGuard Server"    install_wireguard_server check_wireguard_server uninstall_wireguard_server update_wireguard_server    get_version_wireguard_server
register_utility "WPS Office"          install_wps_office       check_wps_office       uninstall_wps_office       update_wps_office          get_version_wps_office
register_utility "Zsh + Oh My Zsh"     install_zsh_setup        check_zsh_setup        uninstall_zsh_setup        update_zsh_setup           get_version_zsh_setup

# --- Category definitions ---
# The order here determines the tab order in the left panel.
CATEGORIES=("System Tasks" "Development" "Gaming" "Internet" "Productivity" "System Tools")

# Category assignment for each utility (System Tasks are identified by SYSTEM_TASKS array)
UTILITY_CATEGORY["Bitwarden Client"]="Productivity"
UTILITY_CATEGORY["Bottles"]="Gaming"
UTILITY_CATEGORY["Brave Browser"]="Internet"
UTILITY_CATEGORY["Btop"]="System Tools"
UTILITY_CATEGORY["Chromium"]="Internet"
UTILITY_CATEGORY["Claude Code"]="Development"
UTILITY_CATEGORY["Cursor IDE"]="Development"
UTILITY_CATEGORY["DBeaver"]="Development"
UTILITY_CATEGORY["Devolutions RDM"]="Internet"
UTILITY_CATEGORY["Discord"]="Internet"
UTILITY_CATEGORY["Docker"]="Development"
UTILITY_CATEGORY["Dotfiles"]="System Tools"
UTILITY_CATEGORY["Fastfetch"]="System Tools"
UTILITY_CATEGORY["Feral Gamemode"]="Gaming"
UTILITY_CATEGORY["FileZilla"]="Internet"
UTILITY_CATEGORY["Firefox"]="Internet"
UTILITY_CATEGORY["GIMP"]="Productivity"
UTILITY_CATEGORY["GitHub CLI"]="Development"
UTILITY_CATEGORY["Google Chrome"]="Internet"
UTILITY_CATEGORY["Heroic Games Launcher"]="Gaming"
UTILITY_CATEGORY["JetBrains Toolbox"]="Development"
UTILITY_CATEGORY["Joplin Client"]="Productivity"
UTILITY_CATEGORY["KMail"]="Internet"
UTILITY_CATEGORY["LibreOffice"]="Productivity"
UTILITY_CATEGORY["Lutris"]="Gaming"
UTILITY_CATEGORY["MangoHud"]="Gaming"
UTILITY_CATEGORY["Nextcloud Desktop"]="Productivity"
UTILITY_CATEGORY["NVM"]="Development"
UTILITY_CATEGORY["OBS Studio"]="Productivity"
UTILITY_CATEGORY["Obsidian"]="Productivity"
UTILITY_CATEGORY["OnlyOffice"]="Productivity"
UTILITY_CATEGORY["OpenSSH Server"]="Internet"
UTILITY_CATEGORY["PIA VPN"]="Internet"
UTILITY_CATEGORY["Postman"]="Development"
UTILITY_CATEGORY["ProtonUp-Qt"]="Gaming"
UTILITY_CATEGORY["ProtonVPN"]="Internet"
UTILITY_CATEGORY["QBittorrent"]="Internet"
UTILITY_CATEGORY["Remmina"]="Internet"
UTILITY_CATEGORY["Signal Desktop"]="Internet"
UTILITY_CATEGORY["Stacer"]="System Tools"
UTILITY_CATEGORY["Standard Notes"]="Productivity"
UTILITY_CATEGORY["Steam App"]="Gaming"
UTILITY_CATEGORY["Syncthing"]="Internet"
UTILITY_CATEGORY["Tailscale"]="Internet"
UTILITY_CATEGORY["Telegram Desktop"]="Internet"
UTILITY_CATEGORY["Termius SSH Client"]="Internet"
UTILITY_CATEGORY["Thorium Browser"]="Internet"
UTILITY_CATEGORY["Thunderbird"]="Internet"
UTILITY_CATEGORY["Timeshift"]="System Tools"
UTILITY_CATEGORY["Visual Studio Code"]="Development"
UTILITY_CATEGORY["Vivaldi Browser"]="Internet"
UTILITY_CATEGORY["WireGuard Client"]="Internet"
UTILITY_CATEGORY["WireGuard Server"]="Internet"
UTILITY_CATEGORY["WPS Office"]="Productivity"
UTILITY_CATEGORY["Zsh + Oh My Zsh"]="System Tools"

# Subcategory assignments — utility name → subcategory label within the parent category
UTILITY_SUBCATEGORY["Brave Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Chromium"]="Web Browsers"
UTILITY_SUBCATEGORY["Firefox"]="Web Browsers"
UTILITY_SUBCATEGORY["Google Chrome"]="Web Browsers"
UTILITY_SUBCATEGORY["Thorium Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Vivaldi Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Discord"]="Messaging"
UTILITY_SUBCATEGORY["Signal Desktop"]="Messaging"
UTILITY_SUBCATEGORY["Telegram Desktop"]="Messaging"
UTILITY_SUBCATEGORY["KMail"]="Email Clients"
UTILITY_SUBCATEGORY["Thunderbird"]="Email Clients"
UTILITY_SUBCATEGORY["FileZilla"]="File Transfer"
UTILITY_SUBCATEGORY["Remmina"]="Remote Access"
UTILITY_SUBCATEGORY["Termius SSH Client"]="Remote Access"
UTILITY_SUBCATEGORY["OpenSSH Server"]="Remote Access"
UTILITY_SUBCATEGORY["Devolutions RDM"]="Remote Access"
UTILITY_SUBCATEGORY["PIA VPN"]="VPN"
UTILITY_SUBCATEGORY["ProtonVPN"]="VPN"
UTILITY_SUBCATEGORY["Tailscale"]="VPN"
UTILITY_SUBCATEGORY["WireGuard Client"]="VPN"
UTILITY_SUBCATEGORY["WireGuard Server"]="VPN"
UTILITY_SUBCATEGORY["LibreOffice"]="Office Suites"
UTILITY_SUBCATEGORY["OnlyOffice"]="Office Suites"
UTILITY_SUBCATEGORY["WPS Office"]="Office Suites"
UTILITY_SUBCATEGORY["Obsidian"]="Notes"
UTILITY_SUBCATEGORY["Standard Notes"]="Notes"
UTILITY_SUBCATEGORY["Joplin Client"]="Notes"
UTILITY_SUBCATEGORY["Claude Code"]="IDEs & Editors"
UTILITY_SUBCATEGORY["Cursor IDE"]="IDEs & Editors"
UTILITY_SUBCATEGORY["JetBrains Toolbox"]="IDEs & Editors"
UTILITY_SUBCATEGORY["Visual Studio Code"]="IDEs & Editors"
UTILITY_SUBCATEGORY["Steam App"]="Game Launchers"
UTILITY_SUBCATEGORY["Lutris"]="Game Launchers"
UTILITY_SUBCATEGORY["Heroic Games Launcher"]="Game Launchers"
UTILITY_SUBCATEGORY["Bottles"]="Game Launchers"
UTILITY_SUBCATEGORY["Feral Gamemode"]="Gaming Utilities"
UTILITY_SUBCATEGORY["MangoHud"]="Gaming Utilities"
UTILITY_SUBCATEGORY["ProtonUp-Qt"]="Gaming Utilities"

# --- Descriptions (shown in the info panel when an item is highlighted) ---

# System Tasks
UTILITY_DESCRIPTION["Full System Upgrade/Update"]="Performs a comprehensive system upgrade including all configured package managers and removes unused packages."
UTILITY_DESCRIPTION["System Updates"]="Installs and configures automatic system update scheduling via systemd timers or cron."
UTILITY_DESCRIPTION["KDE Desktop"]="Installs the KDE Plasma desktop environment with core applications and sensible defaults."
UTILITY_DESCRIPTION["NVIDIA Drivers"]="Installs proprietary NVIDIA GPU drivers for optimal 3D graphics and compute performance."
UTILITY_DESCRIPTION["XEN Guest Utilities"]="Installs XEN guest agent for improved virtual machine performance, clipboard sharing, and host integration."
UTILITY_DESCRIPTION["Enable RDP"]="Enables Remote Desktop Protocol access to this machine using the XRDP server."
UTILITY_DESCRIPTION["AMD Drivers"]="Installs open-source AMD GPU drivers (AMDGPU/Mesa) for optimal graphics performance."
UTILITY_DESCRIPTION["Flatpak Setup"]="Configures the Flatpak package manager and adds the Flathub repository for sandboxed applications."
UTILITY_DESCRIPTION["UFW Firewall"]="Installs and configures Uncomplicated Firewall with sensible default rules."
UTILITY_DESCRIPTION["Num Lock at Boot"]="Enables Num Lock automatically on all TTY consoles and the display manager login screen at boot."
UTILITY_DESCRIPTION["Local MOTD"]="Replaces Ubuntu's default dynamic MOTD with a clean, fast local version."
UTILITY_DESCRIPTION["Command-Not-Found Prompt"]="Enables auto-suggestion to install missing command packages when a command is not found."
UTILITY_DESCRIPTION["Create Snapshot"]="Creates a system snapshot for backup and rollback purposes using the configured snapshot backend."
UTILITY_DESCRIPTION["Restore Snapshot"]="Restores the system from a previously created snapshot. Use with caution."

# Development
UTILITY_DESCRIPTION["Claude Code"]="Anthropic's AI coding assistant that runs in the terminal for code generation, editing, and analysis."
UTILITY_DESCRIPTION["Cursor IDE"]="AI-powered code editor built on VS Code with deeply integrated AI features for code completion and chat."
UTILITY_DESCRIPTION["DBeaver"]="Universal database management tool supporting PostgreSQL, MySQL, SQLite, Oracle, and many more."
UTILITY_DESCRIPTION["Docker"]="Container platform for building, shipping, and running applications in isolated environments."
UTILITY_DESCRIPTION["GitHub CLI"]="Official command-line interface for GitHub — manage repos, issues, PRs, and workflows from the terminal."
UTILITY_DESCRIPTION["JetBrains Toolbox"]="Manager for installing and updating JetBrains IDEs such as IntelliJ, PyCharm, and WebStorm."
UTILITY_DESCRIPTION["NVM"]="Node Version Manager — install and switch between multiple Node.js versions with ease."
UTILITY_DESCRIPTION["Postman"]="API development and testing platform for designing, debugging, and collaborating on APIs."
UTILITY_DESCRIPTION["Visual Studio Code"]="Microsoft's extensible code editor with a rich ecosystem of extensions and built-in Git support."

# Gaming
UTILITY_DESCRIPTION["Bottles"]="Wine prefix manager for running Windows software on Linux with per-app isolation."
UTILITY_DESCRIPTION["Feral Gamemode"]="Optimizes Linux system performance while gaming by adjusting CPU governor, I/O priority, and more."
UTILITY_DESCRIPTION["Heroic Games Launcher"]="Open-source launcher for Epic Games Store, GOG, and Amazon Prime Gaming libraries."
UTILITY_DESCRIPTION["Lutris"]="Open gaming platform for managing and running games from multiple sources including Steam, GOG, and more."
UTILITY_DESCRIPTION["MangoHud"]="Vulkan and OpenGL overlay for monitoring FPS, frame times, CPU/GPU usage, and temperatures in-game."
UTILITY_DESCRIPTION["ProtonUp-Qt"]="Graphical tool for managing Proton-GE and Wine-GE compatibility layers for Steam and Lutris."
UTILITY_DESCRIPTION["Steam App"]="Valve's gaming platform for purchasing, downloading, and playing PC games on Linux."

# Internet
UTILITY_DESCRIPTION["Brave Browser"]="Privacy-focused web browser with built-in ad and tracker blocking based on Chromium."
UTILITY_DESCRIPTION["Chromium"]="Open-source web browser that serves as the upstream base for Google Chrome."
UTILITY_DESCRIPTION["Devolutions RDM"]="Remote Desktop Manager for centrally managing remote connections, passwords, and credentials."
UTILITY_DESCRIPTION["Discord"]="Voice, video, and text communication platform popular with gaming and developer communities."
UTILITY_DESCRIPTION["FileZilla"]="Cross-platform FTP, FTPS, and SFTP client for fast and reliable file transfers."
UTILITY_DESCRIPTION["Firefox"]="Open-source web browser by Mozilla with strong privacy features and extension support."
UTILITY_DESCRIPTION["Google Chrome"]="Google's web browser with extensive extension ecosystem, sync, and developer tools."
UTILITY_DESCRIPTION["KMail"]="KDE's feature-rich email client with PGP encryption, multiple account support, and filters."
UTILITY_DESCRIPTION["OpenSSH Server"]="Secure Shell server enabling encrypted remote terminal access to this machine."
UTILITY_DESCRIPTION["PIA VPN"]="Private Internet Access VPN client for encrypted and anonymous internet browsing."
UTILITY_DESCRIPTION["ProtonVPN"]="Free and open-source VPN service by Proton for secure and private browsing."
UTILITY_DESCRIPTION["QBittorrent"]="Open-source BitTorrent client with a clean interface and no ads."
UTILITY_DESCRIPTION["Remmina"]="Remote desktop client supporting RDP, VNC, SSH, SPICE, and other protocols."
UTILITY_DESCRIPTION["Signal Desktop"]="End-to-end encrypted messaging application focused on privacy and security."
UTILITY_DESCRIPTION["Syncthing"]="Continuous peer-to-peer file synchronization between your devices without a central server."
UTILITY_DESCRIPTION["Tailscale"]="Zero-config mesh VPN built on WireGuard for secure networking between your devices."
UTILITY_DESCRIPTION["Telegram Desktop"]="Cloud-based messaging app with fast delivery, group chats, channels, and file sharing."
UTILITY_DESCRIPTION["Termius SSH Client"]="Modern SSH client with sync across devices, SFTP, and snippet management."
UTILITY_DESCRIPTION["Thorium Browser"]="Chromium-based browser optimized for speed and performance with compiler optimizations."
UTILITY_DESCRIPTION["Thunderbird"]="Open-source email client by Mozilla with calendar integration and PGP support."
UTILITY_DESCRIPTION["Vivaldi Browser"]="Highly customizable Chromium-based browser with advanced tab management and built-in tools."
UTILITY_DESCRIPTION["WireGuard Client"]="Modern, fast, and lightweight VPN client using the WireGuard protocol."
UTILITY_DESCRIPTION["WireGuard Server"]="Sets up a WireGuard VPN server for secure remote access to your network."

# Productivity
UTILITY_DESCRIPTION["Bitwarden Client"]="Open-source password manager for securely storing and auto-filling credentials."
UTILITY_DESCRIPTION["GIMP"]="GNU Image Manipulation Program — powerful open-source photo editor and graphic design tool."
UTILITY_DESCRIPTION["Joplin Client"]="Open-source note-taking and to-do application with Markdown support and sync."
UTILITY_DESCRIPTION["LibreOffice"]="Full-featured open-source office suite compatible with Microsoft Office formats."
UTILITY_DESCRIPTION["Nextcloud Desktop"]="Desktop sync client for Nextcloud, providing self-hosted cloud file storage and sharing."
UTILITY_DESCRIPTION["OBS Studio"]="Open-source software for video recording and live streaming with scene composition."
UTILITY_DESCRIPTION["Obsidian"]="Markdown-based knowledge base and note-taking app with linking, graphs, and plugins."
UTILITY_DESCRIPTION["OnlyOffice"]="Office suite with strong Microsoft Office format compatibility and real-time collaboration."
UTILITY_DESCRIPTION["Standard Notes"]="End-to-end encrypted note-taking app with cross-platform sync and extensible editors."
UTILITY_DESCRIPTION["WPS Office"]="Microsoft Office-compatible office suite with a familiar interface and polished formatting."

# System Tools
UTILITY_DESCRIPTION["Btop"]="Modern terminal-based resource monitor with a rich visual interface showing CPU, memory, disk, and network."
UTILITY_DESCRIPTION["Dotfiles"]="Deploys your personal shell configuration and dotfiles from your repository."
UTILITY_DESCRIPTION["Fastfetch"]="Lightning-fast system information tool written in C, displaying OS, hardware, and software details."
UTILITY_DESCRIPTION["Stacer"]="Linux system optimizer and monitoring tool with a graphical interface for managing services and resources."
UTILITY_DESCRIPTION["Timeshift"]="System restore utility that creates incremental filesystem snapshots using rsync or BTRFS."
UTILITY_DESCRIPTION["Zsh + Oh My Zsh"]="Installs the Z shell with Oh My Zsh framework for enhanced terminal experience, themes, and plugins."
