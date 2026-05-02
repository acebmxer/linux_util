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
register_system_task "Topgrade"           install_topgrade        check_topgrade        uninstall_topgrade        update_topgrade           get_version_topgrade
NO_RETRY["Topgrade"]=1
register_system_task "Mount Local Drive"  setup_mount_local_drive check_mount_local_drive uninstall_mount_local_drive update_mount_local_drive  get_version_mount_local_drive
register_system_task "Mount NFS Share"    setup_mount_nfs_share   check_mount_nfs_share   uninstall_mount_nfs_share   update_mount_nfs_share    get_version_mount_nfs_share
register_system_task "Mount SMB Share"    setup_mount_smb_share   check_mount_smb_share   uninstall_mount_smb_share   update_mount_smb_share    get_version_mount_smb_share
register_system_task "Manage Share"       setup_manage_share      check_manage_share      uninstall_manage_share      update_manage_share       get_version_manage_share
register_system_task "Configure Syncthing Folders" setup_syncthing_folders check_syncthing_folders uninstall_syncthing_folders update_syncthing_folders get_version_syncthing_folders
register_utility "NVIDIA Drivers"         install_nvidia_drivers  check_nvidia_drivers  uninstall_nvidia_drivers  update_nvidia_drivers     get_version_nvidia_drivers
register_utility "XEN Guest Utilities"    setup_xen_guest_utilities check_xen_guest_utilities uninstall_xen_guest_utilities setup_xen_guest_utilities get_version_xen_guest_utilities
register_system_task "Enable RDP"         install_enable_rdp      check_enable_rdp      uninstall_enable_rdp      update_enable_rdp         get_version_enable_rdp
register_utility "AMD Drivers"            install_amd_drivers     check_amd_drivers     uninstall_amd_drivers     update_amd_drivers        get_version_amd_drivers
register_system_task "Flatpak Setup"      install_flatpak_setup   check_flatpak_setup   uninstall_flatpak_setup   update_flatpak_setup      get_version_flatpak_setup
register_system_task "UFW Firewall"       install_ufw             check_ufw             uninstall_ufw             update_ufw                get_version_ufw
register_system_task "Num Lock at Boot"   install_numlock_boot    check_numlock_boot    uninstall_numlock_boot    update_numlock_boot       get_version_numlock_boot
register_system_task "Local Time Zone / Locale" setup_timezone_locale check_always_false noop_function setup_timezone_locale get_version_timezone_locale

# Debian/Ubuntu-only system tasks
if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    register_system_task "Configure Unattended Upgrades" install_unattended_upgrades check_unattended_upgrades uninstall_unattended_upgrades update_unattended_upgrades get_version_unattended_upgrades
    register_system_task "Install fail2ban"              install_fail2ban            check_fail2ban            uninstall_fail2ban            update_fail2ban            get_version_fail2ban
fi

# Command-not-found auto-install prompt (Ubuntu, Kubuntu, KDE Neon)
# Prerequisite: enables interactive y/N install prompt for missing commands in bash.
if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "kubuntu" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
    register_system_task "Command-Not-Found Prompt" setup_command_not_found check_command_not_found uninstall_command_not_found update_command_not_found
fi

# Ubuntu/Kubuntu/KDE Neon specific fixes
if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "kubuntu" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
    register_system_task "Fix Grub on BTRFS"          install_fix_grub_btrfs   check_fix_grub_btrfs   uninstall_fix_grub_btrfs   update_fix_grub_btrfs   get_version_fix_grub_btrfs
    register_system_task "Fix Monitor Layout at Login" install_fix_monitor_login check_always_false     noop_function              install_fix_monitor_login
fi

# These fail immediately when Flatpak is absent — retrying adds no value
NO_RETRY["ProtonUp-Qt"]=1
NO_RETRY["Bottles"]=1

# --- Utilities (alphabetical order) ---
register_utility "AMD CPU Microcode & Firmware"  install_amd_chipset_drivers   check_amd_chipset_drivers   uninstall_amd_chipset_drivers   update_amd_chipset_drivers   get_version_amd_chipset_drivers
register_utility "Ansible"             install_ansible          check_ansible          uninstall_ansible          update_ansible             get_version_ansible
register_utility "AnyDesk"             install_anydesk          check_anydesk          uninstall_anydesk          update_anydesk             get_version_anydesk
register_utility "Audacity"            install_audacity         check_audacity         uninstall_audacity         update_audacity            get_version_audacity
register_utility "Bitwarden Client"       install_bitwarden           check_bitwarden           uninstall_bitwarden           update_bitwarden              get_version_bitwarden
register_utility "Bitwarden Extension"    install_bitwarden_extension check_bitwarden_extension uninstall_bitwarden_extension update_bitwarden_extension    get_version_bitwarden_extension
register_utility "Bottles"                install_bottles             check_bottles             uninstall_bottles             update_bottles                get_version_bottles
register_utility "Brave Browser"       install_brave            check_brave            uninstall_brave            update_brave               get_version_brave
register_utility "Btop"                install_btop             check_btop             uninstall_btop             update_btop                get_version_btop
register_utility "Intel CPU Microcode & Thermal" install_intel_chipset_drivers check_intel_chipset_drivers uninstall_intel_chipset_drivers update_intel_chipset_drivers get_version_intel_chipset_drivers
register_utility "Chromium"            install_chromium         check_chromium         uninstall_chromium         update_chromium            get_version_chromium
register_utility "ClamAV"              install_clamav           check_clamav           uninstall_clamav           update_clamav              get_version_clamav
register_utility "Claude Code"         install_claude_code      check_claude_code      uninstall_claude_code      update_claude_code         get_version_claude_code
register_utility "Cursor IDE"          install_cursor           check_cursor           uninstall_cursor           update_cursor              get_version_cursor
register_utility "DBeaver"             install_dbeaver          check_dbeaver          uninstall_dbeaver          update_dbeaver             get_version_dbeaver

# Déjà Dup: not supported on RHEL family
if [[ "$DISTRO_FAMILY" != "rhel" ]]; then
    register_utility "Déjà Dup" install_deja_dup check_deja_dup uninstall_deja_dup update_deja_dup get_version_deja_dup
fi
register_utility "Duplicati"           install_duplicati        check_duplicati        uninstall_duplicati        update_duplicati           get_version_duplicati
NO_RETRY["Duplicati"]=1
register_utility "Devolutions RDM"     install_devolutions_rdm  check_devolutions_rdm  uninstall_devolutions_rdm  update_devolutions_rdm     get_version_devolutions_rdm
register_utility "Discord"             install_discord          check_discord          uninstall_discord          update_discord             get_version_discord
register_utility "Element (Matrix)"    install_element          check_element          uninstall_element          update_element             get_version_element
register_utility "Docker"              setup_install_docker     check_docker           uninstall_docker           update_docker              get_version_docker
register_utility "Fastfetch"           install_fastfetch        check_fastfetch        uninstall_fastfetch        update_fastfetch           get_version_fastfetch
register_utility "Feral Gamemode"      install_gamemode         check_gamemode         uninstall_gamemode         update_gamemode            get_version_gamemode
register_utility "FileZilla"           install_filezilla        check_filezilla        uninstall_filezilla        update_filezilla           get_version_filezilla
register_utility "Filelight"           install_filelight        check_filelight        uninstall_filelight        update_filelight           get_version_filelight
register_utility "Firefox"             install_firefox          check_firefox          uninstall_firefox          update_firefox             get_version_firefox
register_utility "Flameshot"           install_flameshot        check_flameshot        uninstall_flameshot        update_flameshot           get_version_flameshot
register_utility "GIMP"                install_gimp             check_gimp             uninstall_gimp             update_gimp                get_version_gimp
register_utility "GitHub CLI"          install_github_cli       check_github_cli       uninstall_github_cli       update_github_cli          get_version_github_cli
register_utility "Go SDK"              install_golang           check_golang           uninstall_golang           update_golang              get_version_golang
register_utility "Google Chrome"       install_google_chrome    check_google_chrome    uninstall_google_chrome    update_google_chrome       get_version_google_chrome
register_utility "HandBrake"           install_handbrake        check_handbrake        uninstall_handbrake        update_handbrake           get_version_handbrake
register_utility "Heroic Games Launcher" install_heroic         check_heroic           uninstall_heroic           update_heroic              get_version_heroic
register_utility "Inkscape"            install_inkscape         check_inkscape         uninstall_inkscape         update_inkscape            get_version_inkscape
register_utility "Input Leap"          install_input_leap       check_input_leap       uninstall_input_leap       update_input_leap          get_version_input_leap
register_utility "JetBrains Toolbox"   install_jetbrains_toolbox check_jetbrains_toolbox uninstall_jetbrains_toolbox update_jetbrains_toolbox get_version_jetbrains_toolbox
register_utility "Joplin Client"              install_joplin                       check_joplin                       uninstall_joplin                       update_joplin                        get_version_joplin
register_utility "Joplin Web Clipper"         install_joplin_webclipper_extension  check_joplin_webclipper_extension  uninstall_joplin_webclipper_extension  update_joplin_webclipper_extension   get_version_joplin_webclipper_extension
register_utility "k9s"                 install_k9s              check_k9s              uninstall_k9s              update_k9s                 get_version_k9s
register_utility "Kdenlive"            install_kdenlive         check_kdenlive         uninstall_kdenlive         update_kdenlive            get_version_kdenlive
register_utility "KMail"                      install_kmail                        check_kmail                        uninstall_kmail                        update_kmail                         get_version_kmail
register_utility "Krita"               install_krita            check_krita            uninstall_krita            update_krita               get_version_krita
register_utility "kubectl"             install_kubectl          check_kubectl          uninstall_kubectl          update_kubectl             get_version_kubectl
register_utility "LACT"                install_lact             check_lact             uninstall_lact             update_lact                get_version_lact
register_utility "LibreOffice"         install_libreoffice      check_libreoffice      uninstall_libreoffice      update_libreoffice         get_version_libreoffice
register_utility "LibreWolf"           install_librewolf        check_librewolf        uninstall_librewolf        update_librewolf           get_version_librewolf
register_utility "Logseq"              install_logseq           check_logseq           uninstall_logseq           update_logseq              get_version_logseq
register_utility "Lutris"              install_lutris           check_lutris           uninstall_lutris           update_lutris              get_version_lutris
register_utility "MangoHud"            install_mangohud         check_mangohud         uninstall_mangohud         update_mangohud            get_version_mangohud
register_utility "Mark Text"           install_marktext         check_marktext         uninstall_marktext         update_marktext            get_version_marktext
register_utility "Neovim"              install_neovim           check_neovim           uninstall_neovim           update_neovim              get_version_neovim
register_utility "Nextcloud Desktop"   install_nextcloud_desktop check_nextcloud_desktop uninstall_nextcloud_desktop update_nextcloud_desktop get_version_nextcloud_desktop
register_utility "NVM"                 install_nvm              check_nvm              uninstall_nvm              update_nvm                 get_version_nvm
register_utility "Node.js"             install_nodejs           check_nodejs           uninstall_nodejs           update_nodejs              get_version_nodejs
register_utility "OBS Studio"          install_obs_studio       check_obs_studio       uninstall_obs_studio       update_obs_studio          get_version_obs_studio
register_utility "Obsidian"            install_obsidian         check_obsidian         uninstall_obsidian         update_obsidian            get_version_obsidian
register_utility "OnlyOffice"          install_onlyoffice       check_onlyoffice       uninstall_onlyoffice       update_onlyoffice          get_version_onlyoffice
register_utility "OpenSSH Server"      install_openssh_server   check_openssh_server   uninstall_openssh_server   update_openssh_server      get_version_openssh_server
register_utility "OpenTofu"            install_opentofu         check_opentofu         uninstall_opentofu         update_opentofu            get_version_opentofu
register_utility "PIA VPN"             install_pia_vpn          check_pia_vpn          uninstall_pia_vpn          update_pia_vpn             get_version_pia_vpn
register_utility "Podman"              install_podman           check_podman           uninstall_podman           update_podman              get_version_podman
register_utility "Postman"             install_postman          check_postman          uninstall_postman          update_postman             get_version_postman
register_utility "PowerShell"          install_powershell       check_powershell       uninstall_powershell       update_powershell          get_version_powershell
register_utility "ProtonUp-Qt"         install_protonup_qt      check_protonup_qt      uninstall_protonup_qt      update_protonup_qt         get_version_protonup_qt
register_utility "ProtonVPN"           install_protonvpn        check_protonvpn        uninstall_protonvpn        update_protonvpn           get_version_protonvpn
register_utility "pyenv"               install_pyenv            check_pyenv            uninstall_pyenv            update_pyenv               get_version_pyenv
register_utility "QBittorrent"         install_qbittorrent      check_qbittorrent      uninstall_qbittorrent      update_qbittorrent         get_version_qbittorrent
register_utility "Remmina"             install_remmina          check_remmina          uninstall_remmina          update_remmina             get_version_remmina
register_utility "RustDesk"            install_rustdesk         check_rustdesk         uninstall_rustdesk         update_rustdesk            get_version_rustdesk
register_utility "Rustup"              install_rustup           check_rustup           uninstall_rustup           update_rustup              get_version_rustup
register_utility "Signal Desktop"         install_signal                check_signal                uninstall_signal                update_signal                 get_version_signal
register_utility "Slack"               install_slack            check_slack            uninstall_slack            update_slack               get_version_slack
register_utility "SponsorBlock Extension" install_sponsorblock_extension check_sponsorblock_extension uninstall_sponsorblock_extension update_sponsorblock_extension get_version_sponsorblock_extension
register_utility "Stacer"                 install_stacer                check_stacer                uninstall_stacer                update_stacer                 get_version_stacer
register_utility "Standard Notes"      install_standard_notes   check_standard_notes   uninstall_standard_notes   update_standard_notes      get_version_standard_notes
register_utility "Steam App"           install_steam            check_steam            uninstall_steam            update_steam               get_version_steam
register_utility "Syncthing"           install_syncthing        check_syncthing        uninstall_syncthing        update_syncthing           get_version_syncthing
register_utility "Tailscale"           install_tailscale        check_tailscale        uninstall_tailscale        update_tailscale           get_version_tailscale
register_utility "Telegram Desktop"    install_telegram         check_telegram         uninstall_telegram         update_telegram            get_version_telegram
register_utility "Termius SSH Client"  install_termius          check_termius          uninstall_termius          update_termius             get_version_termius
register_utility "Terraform"           install_terraform        check_terraform        uninstall_terraform        update_terraform           get_version_terraform
register_utility "Thorium Browser"     install_thorium          check_thorium          uninstall_thorium          update_thorium             get_version_thorium
register_utility "Thunderbird"         install_thunderbird      check_thunderbird      uninstall_thunderbird      update_thunderbird         get_version_thunderbird
register_utility "Timeshift"           install_timeshift        check_timeshift        uninstall_timeshift        update_timeshift           get_version_timeshift
register_utility "Create Snapshot"     setup_create_snapshot    check_always_false     noop_function              setup_create_snapshot
NO_RETRY["Create Snapshot"]=1
register_utility "Restore Snapshot"    setup_restore_snapshot   check_always_false     noop_function              setup_restore_snapshot
NO_RETRY["Restore Snapshot"]=1
register_utility "Delete Snapshot"     setup_delete_snapshot    check_always_false     noop_function              setup_delete_snapshot
NO_RETRY["Delete Snapshot"]=1

# Snapper and Btrfs Assistant: Arch and openSUSE only
if [[ "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "suse" ]]; then
    register_utility "Snapper"                   install_snapper          check_snapper          uninstall_snapper          update_snapper             get_version_snapper
    register_utility "Btrfs Assistant"           install_btrfs_assistant  check_btrfs_assistant  uninstall_btrfs_assistant  update_btrfs_assistant     get_version_btrfs_assistant
    register_utility "Create Snapshot (Snapper)" setup_create_snapshot    check_always_false     noop_function              setup_create_snapshot
    NO_RETRY["Create Snapshot (Snapper)"]=1
    register_utility "Restore Snapshot (Snapper)" setup_restore_snapshot  check_always_false     noop_function              setup_restore_snapshot
    NO_RETRY["Restore Snapshot (Snapper)"]=1
    register_utility "Delete Snapshot (Snapper)" setup_delete_snapshot    check_always_false     noop_function              setup_delete_snapshot
    NO_RETRY["Delete Snapshot (Snapper)"]=1
fi
register_utility "Tor Browser"         install_tor_browser      check_tor_browser      uninstall_tor_browser      update_tor_browser         get_version_tor_browser
register_utility "Ventoy"              install_ventoy           check_ventoy           uninstall_ventoy           update_ventoy              get_version_ventoy
register_utility "Virt-Manager"        install_virt_manager     check_virt_manager     uninstall_virt_manager     update_virt_manager        get_version_virt_manager
register_utility "Visual Studio Code"  install_vscode           check_vscode           uninstall_vscode           update_vscode              get_version_vscode
register_utility "Vorta"               install_vorta            check_vorta            uninstall_vorta            update_vorta               get_version_vorta
register_utility "Vivaldi Browser"     install_vivaldi          check_vivaldi          uninstall_vivaldi          update_vivaldi             get_version_vivaldi
register_utility "VLC"                 install_vlc              check_vlc              uninstall_vlc              update_vlc                 get_version_vlc
register_utility "Wine"               install_wine             check_wine             uninstall_wine             update_wine                get_version_wine
register_utility "WireGuard Client"    install_wireguard_client check_wireguard_client uninstall_wireguard_client update_wireguard_client    get_version_wireguard_client
register_utility "WireGuard Server"    install_wireguard_server check_wireguard_server uninstall_wireguard_server update_wireguard_server    get_version_wireguard_server
register_utility "WPS Office"          install_wps_office       check_wps_office       uninstall_wps_office       update_wps_office          get_version_wps_office
register_utility "Zoom"                install_zoom             check_zoom             uninstall_zoom             update_zoom                get_version_zoom
register_utility "Zotero"              install_zotero           check_zotero           uninstall_zotero           update_zotero              get_version_zotero
register_utility "Zsh + Oh My Zsh"     install_zsh_setup        check_zsh_setup        uninstall_zsh_setup        update_zsh_setup           get_version_zsh_setup

# --- Desktop Environment Utilities ---
# Elementary OS uses Pantheon exclusively; any other DE causes display manager
# and PAM session conflicts. The elementary project explicitly advises against it.

# Cinnamon: available on Debian, Ubuntu, Fedora, Arch, openSUSE — not elementary
if [[ "$DISTRO_ID" != "elementary" ]]; then
    register_utility "Cinnamon Desktop"    install_cinnamon         check_cinnamon         uninstall_cinnamon         update_cinnamon            get_version_cinnamon
fi

# COSMIC: requires Ubuntu 24.10+/Debian Trixie, Fedora 42+, or Arch.
# Not packaged for the RHEL ecosystem or openSUSE Leap/SLES.
if [[ "$DISTRO_ID" != "elementary" ]] && \
   [[ "$DISTRO_FAMILY" != "rhel" ]] && \
   [[ "$DISTRO_ID" != "opensuse-leap" ]] && \
   [[ "$DISTRO_ID" != "sles" ]]; then
    register_utility "COSMIC Desktop"      install_cosmic           check_cosmic           uninstall_cosmic           update_cosmic              get_version_cosmic
fi

# Deepin: official packages on Fedora, Arch, and openSUSE Tumbleweed (via OBS).
# No official Debian/Ubuntu packages; the only Ubuntu PPA is unmaintained and
# conflicts with GDM. No EPEL coverage. Not in openSUSE Leap/SLES.
if [[ "$DISTRO_FAMILY" != "debian" ]] && \
   [[ "$DISTRO_FAMILY" != "rhel" ]] && \
   [[ "$DISTRO_ID" != "elementary" ]] && \
   [[ "$DISTRO_ID" != "opensuse-leap" ]] && \
   [[ "$DISTRO_ID" != "sles" ]]; then
    register_utility "Deepin Desktop"      install_deepin           check_deepin           uninstall_deepin           update_deepin              get_version_deepin
fi

# GNOME, KDE, MATE, Xfce: available on all supported distros except elementary
if [[ "$DISTRO_ID" != "elementary" ]]; then
    register_utility "GNOME Desktop"       install_gnome            check_gnome            uninstall_gnome            update_gnome               get_version_gnome
    register_utility "KDE Desktop"         install_kde              check_kde              uninstall_kde              update_kde                 get_version_kde
    register_utility "MATE Desktop"        install_mate             check_mate             uninstall_mate             update_mate                get_version_mate
    register_utility "Xfce Desktop"        install_xfce             check_xfce             uninstall_xfce             update_xfce                get_version_xfce
fi

# Budgie: available on Debian/Ubuntu, Fedora, Arch, and openSUSE.
# Not packaged in EPEL (no RHEL support). Not on elementary.
if [[ "$DISTRO_ID" != "elementary" ]] && \
   [[ "$DISTRO_FAMILY" != "rhel" ]]; then
    register_utility "Budgie Desktop"      install_budgie           check_budgie           uninstall_budgie           update_budgie              get_version_budgie
fi

# LXQt: available on Debian/Ubuntu, Fedora, Arch, and openSUSE.
# Not packaged in EPEL (no RHEL support). Not on elementary.
if [[ "$DISTRO_ID" != "elementary" ]] && \
   [[ "$DISTRO_FAMILY" != "rhel" ]]; then
    register_utility "LXQt Desktop"        install_lxqt             check_lxqt             uninstall_lxqt             update_lxqt                get_version_lxqt
fi

# Pantheon: official packages only on Arch (extra repo) and openSUSE Tumbleweed
# (Factory pattern). Not packaged on Debian/Ubuntu, Fedora, RHEL, or Leap/SLES.
# Already installed on elementary — no need to offer it there.
if [[ "$DISTRO_FAMILY" == "arch" ]] || [[ "$DISTRO_ID" == "opensuse-tumbleweed" ]]; then
    register_utility "Pantheon Desktop"    install_pantheon         check_pantheon         uninstall_pantheon         update_pantheon            get_version_pantheon
fi

# --- Category definitions ---
# The order here determines the tab order in the left panel.
CATEGORIES=("System Tasks" "Backup" "Desktop Environments" "Development" "Drivers" "Gaming" "Internet" "Productivity" "System Tools")

# Category assignment for each utility (System Tasks are identified by SYSTEM_TASKS array)
UTILITY_CATEGORY["AMD CPU Microcode & Firmware"]="Drivers"
UTILITY_CATEGORY["AMD Drivers"]="Drivers"
UTILITY_CATEGORY["Intel CPU Microcode & Thermal"]="Drivers"
UTILITY_CATEGORY["LACT"]="Drivers"
UTILITY_CATEGORY["NVIDIA Drivers"]="Drivers"
UTILITY_CATEGORY["XEN Guest Utilities"]="Drivers"
UTILITY_CATEGORY["Budgie Desktop"]="Desktop Environments"
UTILITY_CATEGORY["Cinnamon Desktop"]="Desktop Environments"
UTILITY_CATEGORY["COSMIC Desktop"]="Desktop Environments"
UTILITY_CATEGORY["Deepin Desktop"]="Desktop Environments"
UTILITY_CATEGORY["GNOME Desktop"]="Desktop Environments"
UTILITY_CATEGORY["KDE Desktop"]="Desktop Environments"
UTILITY_CATEGORY["LXQt Desktop"]="Desktop Environments"
UTILITY_CATEGORY["MATE Desktop"]="Desktop Environments"
UTILITY_CATEGORY["Pantheon Desktop"]="Desktop Environments"
UTILITY_CATEGORY["Xfce Desktop"]="Desktop Environments"
UTILITY_CATEGORY["Bitwarden Client"]="Productivity"
UTILITY_CATEGORY["Bitwarden Extension"]="Internet"
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
UTILITY_CATEGORY["Fastfetch"]="System Tools"
UTILITY_CATEGORY["Feral Gamemode"]="Gaming"
UTILITY_CATEGORY["FileZilla"]="Internet"
UTILITY_CATEGORY["Filelight"]="System Tools"
UTILITY_CATEGORY["Firefox"]="Internet"
UTILITY_CATEGORY["GIMP"]="Productivity"
UTILITY_CATEGORY["GitHub CLI"]="Development"
UTILITY_CATEGORY["Google Chrome"]="Internet"
UTILITY_CATEGORY["Heroic Games Launcher"]="Gaming"
UTILITY_CATEGORY["JetBrains Toolbox"]="Development"
UTILITY_CATEGORY["Joplin Client"]="Productivity"
UTILITY_CATEGORY["Joplin Web Clipper"]="Internet"
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
UTILITY_CATEGORY["PowerShell"]="Development"
UTILITY_CATEGORY["ProtonUp-Qt"]="Gaming"
UTILITY_CATEGORY["ProtonVPN"]="Internet"
UTILITY_CATEGORY["QBittorrent"]="Internet"
UTILITY_CATEGORY["Remmina"]="Internet"
UTILITY_CATEGORY["Signal Desktop"]="Internet"
UTILITY_CATEGORY["SponsorBlock Extension"]="Internet"
UTILITY_CATEGORY["Stacer"]="System Tools"
UTILITY_CATEGORY["Standard Notes"]="Productivity"
UTILITY_CATEGORY["Steam App"]="Gaming"
UTILITY_CATEGORY["Syncthing"]="Internet"
UTILITY_CATEGORY["Tailscale"]="Internet"
UTILITY_CATEGORY["Telegram Desktop"]="Internet"
UTILITY_CATEGORY["Termius SSH Client"]="Internet"
UTILITY_CATEGORY["Thorium Browser"]="Internet"
UTILITY_CATEGORY["Thunderbird"]="Internet"
UTILITY_CATEGORY["Timeshift"]="Backup"
UTILITY_CATEGORY["Create Snapshot"]="Backup"
UTILITY_CATEGORY["Restore Snapshot"]="Backup"
UTILITY_CATEGORY["Delete Snapshot"]="Backup"
UTILITY_CATEGORY["Snapper"]="Backup"
UTILITY_CATEGORY["Btrfs Assistant"]="Backup"
UTILITY_CATEGORY["Create Snapshot (Snapper)"]="Backup"
UTILITY_CATEGORY["Restore Snapshot (Snapper)"]="Backup"
UTILITY_CATEGORY["Delete Snapshot (Snapper)"]="Backup"
UTILITY_CATEGORY["Déjà Dup"]="Backup"
UTILITY_CATEGORY["Vorta"]="Backup"
UTILITY_CATEGORY["Duplicati"]="Backup"
UTILITY_CATEGORY["Visual Studio Code"]="Development"
UTILITY_CATEGORY["Vivaldi Browser"]="Internet"
UTILITY_CATEGORY["Wine"]="Gaming"
UTILITY_CATEGORY["WireGuard Client"]="Internet"
UTILITY_CATEGORY["WireGuard Server"]="Internet"
UTILITY_CATEGORY["WPS Office"]="Productivity"
UTILITY_CATEGORY["Zsh + Oh My Zsh"]="System Tools"
UTILITY_CATEGORY["Ansible"]="Development"
UTILITY_CATEGORY["AnyDesk"]="Internet"
UTILITY_CATEGORY["Audacity"]="Productivity"
UTILITY_CATEGORY["ClamAV"]="System Tools"
UTILITY_CATEGORY["Element (Matrix)"]="Internet"
UTILITY_CATEGORY["Flameshot"]="Productivity"
UTILITY_CATEGORY["Go SDK"]="Development"
UTILITY_CATEGORY["HandBrake"]="Productivity"
UTILITY_CATEGORY["Inkscape"]="Productivity"
UTILITY_CATEGORY["Input Leap"]="System Tools"
UTILITY_CATEGORY["k9s"]="Development"
UTILITY_CATEGORY["Kdenlive"]="Productivity"
UTILITY_CATEGORY["Krita"]="Productivity"
UTILITY_CATEGORY["kubectl"]="Development"
UTILITY_CATEGORY["LibreWolf"]="Internet"
UTILITY_CATEGORY["Logseq"]="Productivity"
UTILITY_CATEGORY["Mark Text"]="Productivity"
UTILITY_CATEGORY["Neovim"]="Development"
UTILITY_CATEGORY["Node.js"]="Development"
UTILITY_CATEGORY["OpenTofu"]="Development"
UTILITY_CATEGORY["Podman"]="Development"
UTILITY_CATEGORY["pyenv"]="Development"
UTILITY_CATEGORY["RustDesk"]="Internet"
UTILITY_CATEGORY["Rustup"]="Development"
UTILITY_CATEGORY["Slack"]="Internet"
UTILITY_CATEGORY["Terraform"]="Development"
UTILITY_CATEGORY["Tor Browser"]="Internet"
UTILITY_CATEGORY["Ventoy"]="System Tools"
UTILITY_CATEGORY["Virt-Manager"]="Development"
UTILITY_CATEGORY["VLC"]="Productivity"
UTILITY_CATEGORY["Zoom"]="Internet"
UTILITY_CATEGORY["Zotero"]="Productivity"

# Subcategory assignments — utility name → subcategory label within the parent category
UTILITY_SUBCATEGORY["Brave Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Chromium"]="Web Browsers"
UTILITY_SUBCATEGORY["Firefox"]="Web Browsers"
UTILITY_SUBCATEGORY["Google Chrome"]="Web Browsers"
UTILITY_SUBCATEGORY["Thorium Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Vivaldi Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Bitwarden Extension"]="Web Browser Extensions"
UTILITY_SUBCATEGORY["Joplin Web Clipper"]="Web Browser Extensions"
UTILITY_SUBCATEGORY["SponsorBlock Extension"]="Web Browser Extensions"
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
UTILITY_SUBCATEGORY["Wine"]="Gaming Utilities"
UTILITY_SUBCATEGORY["AnyDesk"]="Remote Access"
UTILITY_SUBCATEGORY["Element (Matrix)"]="Messaging"
UTILITY_SUBCATEGORY["LibreWolf"]="Web Browsers"
UTILITY_SUBCATEGORY["Neovim"]="IDEs & Editors"
UTILITY_SUBCATEGORY["RustDesk"]="Remote Access"
UTILITY_SUBCATEGORY["Slack"]="Messaging"
UTILITY_SUBCATEGORY["Tor Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Zoom"]="Messaging"
UTILITY_SUBCATEGORY["Timeshift"]="Timeshift"
UTILITY_SUBCATEGORY["Create Snapshot"]="Timeshift"
UTILITY_SUBCATEGORY["Restore Snapshot"]="Timeshift"
UTILITY_SUBCATEGORY["Delete Snapshot"]="Timeshift"
UTILITY_SUBCATEGORY["Snapper"]="Snapper"
UTILITY_SUBCATEGORY["Btrfs Assistant"]="Snapper"
UTILITY_SUBCATEGORY["Create Snapshot (Snapper)"]="Snapper"
UTILITY_SUBCATEGORY["Restore Snapshot (Snapper)"]="Snapper"
UTILITY_SUBCATEGORY["Delete Snapshot (Snapper)"]="Snapper"
UTILITY_SUBCATEGORY["Déjà Dup"]="File Backup"
UTILITY_SUBCATEGORY["Vorta"]="File Backup"
UTILITY_SUBCATEGORY["Duplicati"]="File Backup"
UTILITY_SUBCATEGORY["AMD CPU Microcode & Firmware"]="CPU Microcode"
UTILITY_SUBCATEGORY["AMD Drivers"]="GPU Drivers"
UTILITY_SUBCATEGORY["Intel CPU Microcode & Thermal"]="CPU Microcode"
UTILITY_SUBCATEGORY["LACT"]="GPU Drivers"
UTILITY_SUBCATEGORY["NVIDIA Drivers"]="GPU Drivers"

# Display name overrides — shown in the menu instead of the utility key
UTILITY_DISPLAY_NAME["Bottles"]="Bottles (Requires Flatpak)"
UTILITY_DISPLAY_NAME["ProtonUp-Qt"]="ProtonUp-Qt (Requires Flatpak)"
UTILITY_DISPLAY_NAME["Duplicati"]="Duplicati (Requires Flatpak)"

# System Tasks uses interleaved mode: subcategory folders appear in registration order
SUBCATEGORY_INTERLEAVED["System Tasks"]=1
UTILITY_SUBCATEGORY["Full System Upgrade/Update"]="System Updaters"
UTILITY_SUBCATEGORY["System Updates"]="System Updaters"
UTILITY_SUBCATEGORY["Topgrade"]="System Updaters"
UTILITY_SUBCATEGORY["Mount Local Drive"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["Mount NFS Share"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["Mount SMB Share"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["Manage Share"]="Mount / Unmount Shares"

# Explicit subcategory display order within each category tab
SUBCATEGORY_ORDER["Drivers"]="CPU Microcode|GPU Drivers"
SUBCATEGORY_ORDER["Internet"]="Web Browsers|Web Browser Extensions|Messaging|Email Clients|File Transfer|Remote Access|VPN"

# --- Descriptions (shown in the info panel when an item is highlighted) ---

# System Tasks
UTILITY_DESCRIPTION["Full System Upgrade/Update"]="Performs a comprehensive system upgrade including all configured package managers and removes unused packages."
UTILITY_DESCRIPTION["System Updates"]="Installs and configures automatic system update scheduling via systemd timers or cron."
UTILITY_DESCRIPTION["Topgrade"]="Runs all configured updaters in one command: apt/dnf/pacman, Flatpak, Snap, Cargo, pip, npm, Brew, and more. On Bazzite the binary is pre-installed (use 'ujust update'); this entry manages your personal topgrade.toml config and offers Workstation, Server, and Bazzite presets. Not recommended for servers hosting sensitive services — use System Updates instead."
UTILITY_DESCRIPTION["Mount Local Drive"]="Interactively selects an unmounted block device and adds it to /etc/fstab, mounting it permanently under ~/media/<name>. Supports ext4, xfs, btrfs, NTFS, exFAT, and vFAT. Backs up fstab before any changes."
UTILITY_DESCRIPTION["Mount NFS Share"]="Discovers NFS exports from a remote server via showmount and mounts the chosen share persistently via /etc/fstab. Installs NFS client tools if needed and backs up fstab before any changes."
UTILITY_DESCRIPTION["Mount SMB Share"]="Connects to an SMB/CIFS server, prompts for credentials, lists available shares, and mounts the chosen share persistently via /etc/fstab. Credentials are stored in a private file under HOME. Installs cifs-utils if needed and backs up fstab before any changes."
UTILITY_DESCRIPTION["Manage Share"]="Update or unmount an existing linux_util-managed mount. Update: change server, share path, credentials, or mount location for NFS, SMB, or local disk mounts. Unmount: remove the share, delete the mount point directory, clear the fstab entry, and remove the KDE Dolphin Places entry. Backs up fstab before any changes."
UTILITY_DESCRIPTION["NVIDIA Drivers"]="Installs proprietary NVIDIA GPU drivers for optimal 3D graphics and compute performance."

# Desktop Environments
UTILITY_DESCRIPTION["Budgie Desktop"]="Modern, polished desktop from the Solus project built on the GNOME stack, featuring a clean layout and the unique Raven notification and settings sidebar."
UTILITY_DESCRIPTION["Cinnamon Desktop"]="Linux Mint's elegant desktop environment offering a classic layout with modern polish and strong customisability."
UTILITY_DESCRIPTION["COSMIC Desktop"]="System76's new Rust-built desktop environment designed for speed, modularity, and a first-class Linux experience."
UTILITY_DESCRIPTION["Deepin Desktop"]="Visually striking desktop environment from the Deepin project, known for its beautiful animations, polished UI, and integrated application suite (DDE)."
UTILITY_DESCRIPTION["GNOME Desktop"]="Modern, minimalist desktop used by default on Ubuntu and Fedora, focused on simplicity, touch-friendly design, and keyboard-driven workflow."
UTILITY_DESCRIPTION["KDE Desktop"]="Feature-rich Plasma desktop with extensive customisation, a full application suite, and strong Wayland support."
UTILITY_DESCRIPTION["LXQt Desktop"]="Lightweight Qt-based desktop offering a fast, resource-efficient experience with a modern look — ideal for modest hardware or users who prefer Qt tooling."
UTILITY_DESCRIPTION["MATE Desktop"]="Traditional GNOME 2-based desktop offering a familiar layout, low resource usage, and broad hardware support."
UTILITY_DESCRIPTION["Pantheon Desktop"]="Elegant, opinionated desktop from the elementary OS project, designed for simplicity and consistency with a macOS-inspired aesthetic."
UTILITY_DESCRIPTION["Xfce Desktop"]="Lightweight and fast desktop that is visually clean, reliable, and ideal for older or lower-end hardware."
UTILITY_DESCRIPTION["XEN Guest Utilities"]="Installs XEN guest agent for improved virtual machine performance, clipboard sharing, and host integration."
UTILITY_DESCRIPTION["Enable RDP"]="Enables Remote Desktop Protocol access to this machine using the XRDP server."
UTILITY_DESCRIPTION["AMD CPU Microcode & Firmware"]="Installs AMD CPU microcode updates and linux-firmware blobs (PSP/SMU, Wi-Fi, Bluetooth, and other device firmware) for Ryzen, Threadripper, and EPYC platforms."
UTILITY_DESCRIPTION["Intel CPU Microcode & Thermal"]="Installs Intel CPU microcode updates and the thermald thermal management daemon for 10th Gen through Core Ultra (Arrow Lake) platforms."
UTILITY_DESCRIPTION["AMD Drivers"]="Installs open-source AMD GPU drivers (AMDGPU/Mesa) for optimal graphics performance."
UTILITY_DESCRIPTION["LACT"]="Linux AMDGPU Top — graphical tool for overclocking, undervolting, and monitoring AMD GPUs. Provides fan control, power limit adjustments, and real-time sensor readings. A reboot is required after installation before changes can be applied."
UTILITY_DESCRIPTION["Flatpak Setup"]="Configures the Flatpak package manager and adds the Flathub repository for sandboxed applications."
UTILITY_DESCRIPTION["UFW Firewall"]="Installs and configures Uncomplicated Firewall with sensible default rules."
UTILITY_DESCRIPTION["Num Lock at Boot"]="Enables Num Lock automatically on all TTY consoles and the display manager login screen at boot."
UTILITY_DESCRIPTION["Local Time Zone / Locale"]="Lets you interactively set your system time zone, locale, or both in one task."
UTILITY_DESCRIPTION["Command-Not-Found Prompt"]="Enables auto-suggestion to install missing command packages when a command is not found."
UTILITY_DESCRIPTION["Create Snapshot"]="Creates a system snapshot using the active backup backend (Timeshift or Snapper). Prompts for an optional description."
UTILITY_DESCRIPTION["Restore Snapshot"]="Restores the system from a previously created snapshot. Lists all available snapshots and asks for confirmation before proceeding."
UTILITY_DESCRIPTION["Delete Snapshot"]="Permanently removes one or more snapshots. Lists all available snapshots and asks for confirmation before deleting."

# Development
UTILITY_DESCRIPTION["Ansible"]="IT automation tool for provisioning, configuration management, and application deployment using agentless SSH-based playbooks."
UTILITY_DESCRIPTION["Claude Code"]="Anthropic's AI coding assistant that runs in the terminal for code generation, editing, and analysis."
UTILITY_DESCRIPTION["Cursor IDE"]="AI-powered code editor built on VS Code with deeply integrated AI features for code completion and chat."
UTILITY_DESCRIPTION["DBeaver"]="Universal database management tool supporting PostgreSQL, MySQL, SQLite, Oracle, and many more."
UTILITY_DESCRIPTION["Docker"]="Container platform for building, shipping, and running applications in isolated environments."
UTILITY_DESCRIPTION["GitHub CLI"]="Official command-line interface for GitHub — manage repos, issues, PRs, and workflows from the terminal."
UTILITY_DESCRIPTION["Go SDK"]="Official Go programming language SDK with the compiler, standard library, and toolchain."
UTILITY_DESCRIPTION["JetBrains Toolbox"]="Manager for installing and updating JetBrains IDEs such as IntelliJ, PyCharm, and WebStorm."
UTILITY_DESCRIPTION["k9s"]="Terminal-based UI for interacting with Kubernetes clusters — browse, observe, and manage workloads in real time."
UTILITY_DESCRIPTION["kubectl"]="Official Kubernetes command-line tool for deploying applications and managing cluster resources."
UTILITY_DESCRIPTION["Neovim"]="Hyperextensible Vim-based text editor focused on extensibility and usability with Lua-powered configuration."
UTILITY_DESCRIPTION["Node.js"]="JavaScript runtime built on Chrome's V8 engine for building fast, scalable server-side and CLI applications."
UTILITY_DESCRIPTION["NVM"]="Node Version Manager — install and switch between multiple Node.js versions with ease."
UTILITY_DESCRIPTION["OpenTofu"]="Open-source Terraform fork for infrastructure-as-code provisioning across cloud providers and on-prem resources."
UTILITY_DESCRIPTION["Podman"]="Daemonless container engine compatible with Docker CLI for building and running OCI containers without root."
UTILITY_DESCRIPTION["Postman"]="API development and testing platform for designing, debugging, and collaborating on APIs."
UTILITY_DESCRIPTION["PowerShell"]="Microsoft's cross-platform task automation shell and scripting language built on .NET. Provides powerful object-based pipelines, remote management via WinRM/SSH, and broad compatibility with Windows PowerShell scripts. Installed via the official Microsoft apt repository where available, otherwise via the GitHub release .deb."
UTILITY_DESCRIPTION["pyenv"]="Python version manager for installing and switching between multiple Python versions per-project."
UTILITY_DESCRIPTION["Rustup"]="Official Rust toolchain installer and version manager for the Rust programming language."
UTILITY_DESCRIPTION["Terraform"]="HashiCorp's infrastructure-as-code tool for provisioning and managing cloud resources with declarative HCL configs."
UTILITY_DESCRIPTION["Virt-Manager"]="Graphical desktop tool for managing KVM/QEMU virtual machines with full libvirt integration."
UTILITY_DESCRIPTION["Visual Studio Code"]="Microsoft's extensible code editor with a rich ecosystem of extensions and built-in Git support."

# Gaming
UTILITY_DESCRIPTION["Bottles"]="Wine prefix manager for running Windows software on Linux with per-app isolation. Requires Flatpak — enable the 'Flatpak Setup' system task first on non-Arch systems."
UTILITY_DESCRIPTION["Feral Gamemode"]="Optimizes Linux system performance while gaming by adjusting CPU governor, I/O priority, and more. For Steam games add the launch option: gamemoderun %command%"
UTILITY_DESCRIPTION["Heroic Games Launcher"]="Open-source launcher for Epic Games Store, GOG, and Amazon Prime Gaming libraries."
UTILITY_DESCRIPTION["Lutris"]="Open gaming platform for managing and running games from multiple sources including Steam, GOG, and more."
UTILITY_DESCRIPTION["MangoHud"]="Vulkan and OpenGL overlay for monitoring FPS, frame times, CPU/GPU usage, and temperatures in-game."
UTILITY_DESCRIPTION["ProtonUp-Qt"]="Graphical tool for managing Proton-GE and Wine-GE compatibility layers for Steam and Lutris. Requires Flatpak — enable the 'Flatpak Setup' system task first on non-Arch systems."
UTILITY_DESCRIPTION["Steam App"]="Valve's gaming platform for purchasing, downloading, and playing PC games on Linux."
UTILITY_DESCRIPTION["Wine"]="Compatibility layer that enables Windows applications and games to run natively on Linux without a virtual machine."

# Internet
UTILITY_DESCRIPTION["Bitwarden Extension"]="Deploys Bitwarden browser extension via policy files for all detected browsers (Brave, Chrome, Chromium, Firefox, Vivaldi). The extension is force-installed on next browser launch."
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
UTILITY_DESCRIPTION["SponsorBlock Extension"]="Deploys SponsorBlock browser extension via policy files for all detected browsers (Brave, Chrome, Chromium, Firefox, Vivaldi). Automatically skips YouTube sponsors, intros, outros, and other unwanted segments using a crowdsourced database."
UTILITY_DESCRIPTION["Syncthing"]="Continuous peer-to-peer file synchronization between your devices without a central server."
UTILITY_DESCRIPTION["Tailscale"]="Zero-config mesh VPN built on WireGuard for secure networking between your devices."
UTILITY_DESCRIPTION["Telegram Desktop"]="Cloud-based messaging app with fast delivery, group chats, channels, and file sharing."
UTILITY_DESCRIPTION["Termius SSH Client"]="Modern SSH client with sync across devices, SFTP, and snippet management."
UTILITY_DESCRIPTION["Thorium Browser"]="Chromium-based browser optimized for speed and performance with compiler optimizations."
UTILITY_DESCRIPTION["Thunderbird"]="Open-source email client by Mozilla with calendar integration and PGP support."
UTILITY_DESCRIPTION["Vivaldi Browser"]="Highly customizable Chromium-based browser with advanced tab management and built-in tools."
UTILITY_DESCRIPTION["WireGuard Client"]="Modern, fast, and lightweight VPN client using the WireGuard protocol."
UTILITY_DESCRIPTION["AnyDesk"]="Fast remote desktop application with low latency for support and remote access across platforms."
UTILITY_DESCRIPTION["Element (Matrix)"]="Open-source Matrix client for decentralized, end-to-end encrypted messaging and collaboration."
UTILITY_DESCRIPTION["LibreWolf"]="Privacy-hardened Firefox fork with tracking protection, telemetry removed, and strong security defaults."
UTILITY_DESCRIPTION["RustDesk"]="Open-source remote desktop application — self-hostable alternative to AnyDesk and TeamViewer."
UTILITY_DESCRIPTION["Slack"]="Team messaging and collaboration platform with channels, threads, integrations, and file sharing."
UTILITY_DESCRIPTION["Tor Browser"]="Privacy browser bundled with the Tor network for anonymous, censorship-resistant browsing."
UTILITY_DESCRIPTION["WireGuard Server"]="Sets up a WireGuard VPN server for secure remote access to your network."
UTILITY_DESCRIPTION["Zoom"]="Video conferencing platform for meetings, webinars, and team collaboration."

# Productivity
UTILITY_DESCRIPTION["Audacity"]="Free, open-source multi-track audio editor and recorder for recording, editing, and exporting audio files."
UTILITY_DESCRIPTION["Bitwarden Client"]="Open-source password manager for securely storing and auto-filling credentials."
UTILITY_DESCRIPTION["Flameshot"]="Powerful, customizable screenshot tool with built-in annotation and markup capabilities."
UTILITY_DESCRIPTION["GIMP"]="GNU Image Manipulation Program — powerful open-source photo editor and graphic design tool."
UTILITY_DESCRIPTION["HandBrake"]="Open-source video transcoder for converting video files between formats with hardware acceleration support."
UTILITY_DESCRIPTION["Inkscape"]="Professional vector graphics editor for creating illustrations, logos, and scalable artwork using SVG."
UTILITY_DESCRIPTION["Kdenlive"]="KDE's powerful non-linear video editor with multi-track editing, effects, and broad format support."
UTILITY_DESCRIPTION["Krita"]="Professional digital painting application designed for illustrators, concept artists, and texture artists."
UTILITY_DESCRIPTION["Logseq"]="Open-source knowledge management and note-taking app based on linked, Markdown-formatted outliner blocks."
UTILITY_DESCRIPTION["Mark Text"]="Simple, elegant Markdown editor focused on writing speed with live preview and multiple themes."
UTILITY_DESCRIPTION["VLC"]="Versatile open-source media player supporting virtually every audio and video format without additional codecs."
UTILITY_DESCRIPTION["Zotero"]="Free reference manager for collecting, organizing, annotating, and citing research sources."
UTILITY_DESCRIPTION["Joplin Client"]="Open-source note-taking and to-do application with Markdown support and sync."
UTILITY_DESCRIPTION["Joplin Web Clipper"]="Deploys Joplin Web Clipper browser extension via policy files for all detected browsers (Brave, Chrome, Chromium, Firefox, Vivaldi). Captures web pages and screenshots directly into Joplin — requires the Joplin desktop app running with Web Clipper service enabled."
UTILITY_DESCRIPTION["LibreOffice"]="Full-featured open-source office suite compatible with Microsoft Office formats."
UTILITY_DESCRIPTION["Nextcloud Desktop"]="Desktop sync client for Nextcloud, providing self-hosted cloud file storage and sharing."
UTILITY_DESCRIPTION["OBS Studio"]="Open-source software for video recording and live streaming with scene composition."
UTILITY_DESCRIPTION["Obsidian"]="Markdown-based knowledge base and note-taking app with linking, graphs, and plugins."
UTILITY_DESCRIPTION["OnlyOffice"]="Office suite with strong Microsoft Office format compatibility and real-time collaboration."
UTILITY_DESCRIPTION["Standard Notes"]="End-to-end encrypted note-taking app with cross-platform sync and extensible editors."
UTILITY_DESCRIPTION["WPS Office"]="Microsoft Office-compatible office suite with a familiar interface and polished formatting."

# System Tools
UTILITY_DESCRIPTION["Btop"]="Modern terminal-based resource monitor with a rich visual interface showing CPU, memory, disk, and network."
UTILITY_DESCRIPTION["Filelight"]="KDE disk usage analyzer that visualizes storage consumption as an interactive radial map, making it easy to identify large files and directories."
UTILITY_DESCRIPTION["ClamAV"]="Open-source antivirus engine for detecting trojans, viruses, malware, and other malicious threats."
UTILITY_DESCRIPTION["Input Leap"]="Open-source KVM software that shares one keyboard and mouse across multiple computers on your local network."
UTILITY_DESCRIPTION["Ventoy"]="Bootable USB solution for loading multiple ISO images from a single drive — just copy ISOs and boot."
UTILITY_DESCRIPTION["Fastfetch"]="Lightning-fast system information tool written in C, displaying OS, hardware, and software details."
UTILITY_DESCRIPTION["Stacer"]="Linux system optimizer and monitoring tool with a graphical interface for managing services and resources."
UTILITY_DESCRIPTION["Timeshift"]="System restore utility that creates incremental filesystem snapshots using rsync or BTRFS. Install this first to enable Create, Restore, and Delete Snapshot."
UTILITY_DESCRIPTION["Déjà Dup"]="(GNOME) Simple, beginner-friendly backup tool for backing up files and folders to local drives, network shares, or cloud storage. Uses duplicity under the hood for encrypted, incremental backups."
UTILITY_DESCRIPTION["Vorta"]="GUI frontend for BorgBackup — a fast, deduplicating backup tool with encryption and compression. Installs both Borg (CLI) and Vorta (GUI). On RHEL-based systems, only BorgBackup is installed via EPEL as Vorta is not packaged there."
UTILITY_DESCRIPTION["Duplicati"]="Cloud backup tool with a web-based GUI supporting S3, Google Drive, OneDrive, SFTP, and many more backends. Features encryption, deduplication, and scheduling. Installed via Flatpak — run 'Flatpak Setup' first if not already configured."
UTILITY_DESCRIPTION["Snapper"]="Btrfs and LVM snapshot manager from openSUSE. Supports automatic pre/post snapshots on Arch and openSUSE. Conflicts with Timeshift on Arch-based systems."
UTILITY_DESCRIPTION["Btrfs Assistant"]="GUI frontend for managing Btrfs snapshots and subvolumes. Works alongside Snapper to provide a visual interface for snapshot operations."
UTILITY_DESCRIPTION["Create Snapshot (Snapper)"]="Create a manual Snapper snapshot of the root filesystem with an optional description."
UTILITY_DESCRIPTION["Restore Snapshot (Snapper)"]="Roll back the system to a previous Snapper snapshot."
UTILITY_DESCRIPTION["Delete Snapshot (Snapper)"]="Permanently delete one or more Snapper snapshots to free disk space."
UTILITY_DESCRIPTION["Zsh + Oh My Zsh"]="Installs the Z shell with Oh My Zsh framework for enhanced terminal experience, themes, and plugins."
