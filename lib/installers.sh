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
# │  ARCH BRANCH: use repo_or_aur (or flatpak_or_aur), never aur_ensure —
# │  derivatives like CachyOS carry many AUR-named packages in their own repos.
# │  If the AUR really is the only source on upstream Arch, add the utility to
# │  mark_aur_only_arch below WITH its package name ("Name=pkg"), and give
# │  check_foobar the Arch package/binary names when they differ from the
# │  .deb/.rpm ones (see _check_standard's 4th and 5th arguments).
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
register_system_task "Mount Local Drive"  setup_mount_local_drive check_mount_local_drive uninstall_mount_local_drive update_mount_local_drive  get_version_mount_local_drive
register_system_task "Mount NFS Share"    setup_mount_nfs_share   check_mount_nfs_share   uninstall_mount_nfs_share   update_mount_nfs_share    get_version_mount_nfs_share
register_system_task "Mount SMB Share"    setup_mount_smb_share   check_mount_smb_share   uninstall_mount_smb_share   update_mount_smb_share    get_version_mount_smb_share
register_system_task "Manage Share"       setup_manage_share      check_manage_share      uninstall_manage_share      update_manage_share       get_version_manage_share
register_system_task "Configure Syncthing Folders" setup_syncthing_folders check_syncthing_folders uninstall_syncthing_folders update_syncthing_folders get_version_syncthing_folders
register_utility "NVIDIA Drivers"         install_nvidia_drivers  check_nvidia_drivers  uninstall_nvidia_drivers  update_nvidia_drivers     get_version_nvidia_drivers
register_utility "XEN Guest Utilities"    setup_xen_guest_utilities check_xen_guest_utilities uninstall_xen_guest_utilities setup_xen_guest_utilities get_version_xen_guest_utilities
register_utility "Enable RDP"             install_enable_rdp      check_enable_rdp      uninstall_enable_rdp      update_enable_rdp         get_version_enable_rdp
register_utility "OpenRSAT"               install_openrsat        check_openrsat        uninstall_openrsat        update_openrsat           get_version_openrsat
register_utility "AMD Drivers"            install_amd_drivers     check_amd_drivers     uninstall_amd_drivers     update_amd_drivers        get_version_amd_drivers
register_system_task "Num Lock at Boot"   install_numlock_boot    check_numlock_boot    uninstall_numlock_boot    update_numlock_boot       get_version_numlock_boot
register_system_task "Local Time Zone / Locale" setup_timezone_locale check_always_false noop_function setup_timezone_locale get_version_timezone_locale
# Fully interactive prompt flow — re-running the menu after a failure only asks again
NO_RETRY["Local Time Zone / Locale"]=1
register_system_task "GTK Window Fix" install_window_buttons check_always_false noop_function install_window_buttons get_version_window_buttons

# Debian/Ubuntu-only system tasks
if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    register_system_task "Unattended Upgrades" install_unattended_upgrades check_unattended_upgrades uninstall_unattended_upgrades update_unattended_upgrades get_version_unattended_upgrades
    # Only offer the config editor when the package (and thus its config file) is present.
    if check_unattended_upgrades; then
        register_system_task "Configure Unattended Upgrades" configure_unattended_upgrades check_always_false noop_function configure_unattended_upgrades
    fi
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

# Delete the stock cloud-image user (ubuntu/debian/centos/alpine). Always listed;
# the status column reflects whether one of those accounts currently exists.
register_system_task "Delete Default Cloud-Init User" delete_cloud_init_user check_always_false noop_function delete_cloud_init_user get_version_delete_cloud_init_user

# Remote-access fixes (all distros)
register_system_task "Fix RDP Kerberos Delay" install_fix_rdp_kerberos check_fix_rdp_kerberos uninstall_fix_rdp_kerberos update_fix_rdp_kerberos get_version_fix_rdp_kerberos

# Package repair tasks (all distros) — kept at the end of the System Tasks section
register_system_task "Fix Broken Packages"   setup_fix_broken_packages check_always_false noop_function setup_fix_broken_packages
register_system_task "Fix Package Repos"      setup_fix_repos           check_always_false noop_function setup_fix_repos
register_system_task "Reset Repos to Default" setup_reset_repos         check_always_false noop_function setup_reset_repos
NO_RETRY["Reset Repos to Default"]=1

# GRUB theme installs fail fast when GRUB is absent or the download fails — no value in retrying
NO_RETRY["GRUB Theme Selector"]=1
NO_RETRY["Distro GRUB Themes"]=1
NO_RETRY["vinceliuice GRUB Themes"]=1
NO_RETRY["Catppuccin GRUB Theme"]=1
NO_RETRY["HyperFluent GRUB Theme"]=1

# These fail immediately when Flatpak is absent — retrying adds no value
NO_RETRY["ProtonUp-Qt"]=1
NO_RETRY["Bottles"]=1
NO_RETRY["Boxflat"]=1
NO_RETRY["BoxBuddy"]=1
NO_RETRY["DistroShelf"]=1

# --- Utilities (alphabetical order) ---
register_utility "AMD CPU Microcode & Firmware"  install_amd_chipset_drivers   check_amd_chipset_drivers   uninstall_amd_chipset_drivers   update_amd_chipset_drivers   get_version_amd_chipset_drivers
register_utility "Angry IP Scanner"    install_angry_ip_scanner check_angry_ip_scanner uninstall_angry_ip_scanner update_angry_ip_scanner    get_version_angry_ip_scanner
register_utility "Ansible"             install_ansible          check_ansible          uninstall_ansible          update_ansible             get_version_ansible
register_utility "AnyDesk"             install_anydesk          check_anydesk          uninstall_anydesk          update_anydesk             get_version_anydesk
register_utility "Audacity"            install_audacity         check_audacity         uninstall_audacity         update_audacity            get_version_audacity
register_utility "Bitwarden Client"       install_bitwarden           check_bitwarden           uninstall_bitwarden           update_bitwarden              get_version_bitwarden
register_utility "GRUB"                install_grub             check_grub             uninstall_grub             update_grub                get_version_grub
register_utility "Limine"              install_limine           check_limine           uninstall_limine           update_limine              get_version_limine
register_utility "systemd-boot"        install_systemd_boot     check_systemd_boot     uninstall_systemd_boot     update_systemd_boot        get_version_systemd_boot
register_utility "Switch Bootloader"   setup_switch_bootloader  check_always_false         noop_switch_bootloader    update_switch_bootloader    get_version_switch_bootloader
register_utility "Configure Bootloader" setup_configure_bootloader check_configure_bootloader noop_configure_bootloader update_configure_bootloader get_version_configure_bootloader
register_utility "GRUB Theme Selector" install_grubtheme_selector    check_always_false          noop_function                   update_grubtheme_selector    get_version_grubtheme_selector
register_utility "Distro GRUB Themes"  install_grubtheme_distro      check_grubtheme_distro      uninstall_grubtheme_distro      update_grubtheme_distro      get_version_grubtheme_distro
register_utility "vinceliuice GRUB Themes" install_grubtheme_vinceliuice check_grubtheme_vinceliuice uninstall_grubtheme_vinceliuice update_grubtheme_vinceliuice get_version_grubtheme_vinceliuice
register_utility "Catppuccin GRUB Theme" install_grubtheme_catppuccin check_grubtheme_catppuccin  uninstall_grubtheme_catppuccin  update_grubtheme_catppuccin  get_version_grubtheme_catppuccin
register_utility "HyperFluent GRUB Theme" install_grubtheme_hyperfluent check_grubtheme_hyperfluent uninstall_grubtheme_hyperfluent update_grubtheme_hyperfluent get_version_grubtheme_hyperfluent
register_utility "Betterbird"             install_betterbird          check_betterbird          uninstall_betterbird          update_betterbird             get_version_betterbird
register_utility "Bitwarden Extension"    install_bitwarden_extension check_bitwarden_extension uninstall_bitwarden_extension update_bitwarden_extension    get_version_bitwarden_extension
register_utility "Bottles"                install_bottles             check_bottles             uninstall_bottles             update_bottles                get_version_bottles
register_utility "Boxflat"                install_boxflat             check_boxflat             uninstall_boxflat             update_boxflat                get_version_boxflat
register_utility "Brave Browser"       install_brave            check_brave            uninstall_brave            update_brave               get_version_brave
register_utility "Brave Debloat"       install_brave_debloat    check_brave_debloat    uninstall_brave_debloat    update_brave_debloat       get_version_brave_debloat
register_utility "Brave Origin"        install_brave_origin     check_brave_origin     uninstall_brave_origin     update_brave_origin        get_version_brave_origin
register_utility "Btop"                install_btop             check_btop             uninstall_btop             update_btop                get_version_btop
register_utility "Intel CPU Microcode & Thermal" install_intel_chipset_drivers check_intel_chipset_drivers uninstall_intel_chipset_drivers update_intel_chipset_drivers get_version_intel_chipset_drivers
register_utility "Chromium"            install_chromium         check_chromium         uninstall_chromium         update_chromium            get_version_chromium
register_utility "ClamAV"              install_clamav           check_clamav           uninstall_clamav           update_clamav              get_version_clamav
register_utility "Claws Mail"          install_claws_mail       check_claws_mail       uninstall_claws_mail       update_claws_mail          get_version_claws_mail
register_utility "Claude Code"         install_claude_code      check_claude_code      uninstall_claude_code      update_claude_code         get_version_claude_code
register_utility "Cockpit"             install_cockpit          check_cockpit          uninstall_cockpit          update_cockpit             get_version_cockpit
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
register_utility "Euro-Office"         install_euro_office      check_euro_office      uninstall_euro_office      update_euro_office         get_version_euro_office
register_utility "Evolution"           install_evolution        check_evolution        uninstall_evolution        update_evolution           get_version_evolution
register_utility "Docker"              setup_install_docker     check_docker           uninstall_docker           update_docker              get_version_docker
# DistroBox subcategory: the container tool plus optional graphical front-ends
register_utility "Distrobox"           install_distrobox        check_distrobox        uninstall_distrobox        update_distrobox           get_version_distrobox
register_utility "BoxBuddy"            install_boxbuddy         check_boxbuddy         uninstall_boxbuddy         update_boxbuddy            get_version_boxbuddy
register_utility "DistroShelf"         install_distroshelf      check_distroshelf      uninstall_distroshelf      update_distroshelf         get_version_distroshelf
register_utility "Fastfetch"           install_fastfetch        check_fastfetch        uninstall_fastfetch        update_fastfetch           get_version_fastfetch
register_utility "Feral Gamemode"      install_gamemode         check_gamemode         uninstall_gamemode         update_gamemode            get_version_gamemode
register_utility "FileZilla"           install_filezilla        check_filezilla        uninstall_filezilla        update_filezilla           get_version_filezilla
register_utility "Filelight"           install_filelight        check_filelight        uninstall_filelight        update_filelight           get_version_filelight
register_utility "Firefox"             install_firefox          check_firefox          uninstall_firefox          update_firefox             get_version_firefox
# Firewalls subcategory: host firewall managers followed by their GUI front-ends
register_utility "UFW Firewall"        install_ufw              check_ufw              uninstall_ufw              update_ufw                 get_version_ufw
# Gufw: packaged only for Debian/Ubuntu and Arch. No RPM-family distro ships it
# — not Fedora, EPEL 9/10, openSUSE Tumbleweed or Leap — and there is no Flatpak
# or COPR build either. Those users want firewalld plus firewall-config below.
if [[ "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "arch" ]]; then
    register_utility "Gufw (Firewall GUI)" install_gufw         check_gufw             uninstall_gufw             update_gufw                get_version_gufw
fi
register_utility "firewalld"           install_firewalld        check_firewalld        uninstall_firewalld        update_firewalld           get_version_firewalld
register_utility "firewall-config (GUI)" install_firewall_config check_firewall_config uninstall_firewall_config update_firewall_config    get_version_firewall_config
register_utility "Flameshot"           install_flameshot        check_flameshot        uninstall_flameshot        update_flameshot           get_version_flameshot
register_utility "Geary"               install_geary            check_geary            uninstall_geary            update_geary               get_version_geary
register_utility "GIMP"                install_gimp             check_gimp             uninstall_gimp             update_gimp                get_version_gimp
register_utility "GitHub CLI"          install_github_cli       check_github_cli       uninstall_github_cli       update_github_cli          get_version_github_cli
register_utility "Go SDK"              install_golang           check_golang           uninstall_golang           update_golang              get_version_golang
register_utility "Google Chrome"       install_google_chrome    check_google_chrome    uninstall_google_chrome    update_google_chrome       get_version_google_chrome
register_utility "GParted"             install_gparted          check_gparted          uninstall_gparted          update_gparted             get_version_gparted
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
# Kup: KDE backup tool — not packaged for RHEL family (Fedora uses a Copr)
if [[ "$DISTRO_FAMILY" != "rhel" ]]; then
    register_utility "Kup"             install_kup              check_kup              uninstall_kup              update_kup                 get_version_kup
fi
register_utility "LACT"                install_lact             check_lact             uninstall_lact             update_lact                get_version_lact
register_utility "Libation"            install_libation         check_libation         uninstall_libation         update_libation            get_version_libation
register_utility "LibreOffice"         install_libreoffice      check_libreoffice      uninstall_libreoffice      update_libreoffice         get_version_libreoffice
register_utility "LibreWolf"           install_librewolf        check_librewolf        uninstall_librewolf        update_librewolf           get_version_librewolf
register_utility "LocalSend"           install_localsend        check_localsend        uninstall_localsend        update_localsend           get_version_localsend
register_utility "Logseq"              install_logseq           check_logseq           uninstall_logseq           update_logseq              get_version_logseq
register_utility "Lutris"              install_lutris           check_lutris           uninstall_lutris           update_lutris              get_version_lutris
register_utility "MangoHud"            install_mangohud         check_mangohud         uninstall_mangohud         update_mangohud            get_version_mangohud
register_utility "Mark Text"           install_marktext         check_marktext         uninstall_marktext         update_marktext            get_version_marktext
register_utility "NeoMutt"             install_neomutt          check_neomutt          uninstall_neomutt          update_neomutt             get_version_neomutt
register_utility "Neovim"              install_neovim           check_neovim           uninstall_neovim           update_neovim              get_version_neovim
register_utility "Nextcloud Desktop"   install_nextcloud_desktop check_nextcloud_desktop uninstall_nextcloud_desktop update_nextcloud_desktop get_version_nextcloud_desktop
register_utility "NVM"                 install_nvm              check_nvm              uninstall_nvm              update_nvm                 get_version_nvm
register_utility "Node.js"             install_nodejs           check_nodejs           uninstall_nodejs           update_nodejs              get_version_nodejs
register_utility "OBS Studio"          install_obs_studio       check_obs_studio       uninstall_obs_studio       update_obs_studio          get_version_obs_studio
register_utility "OCCT"                install_occt             check_occt             uninstall_occt             update_occt                get_version_occt
register_utility "Obsidian"            install_obsidian         check_obsidian         uninstall_obsidian         update_obsidian            get_version_obsidian
register_utility "OnlyOffice"          install_onlyoffice       check_onlyoffice       uninstall_onlyoffice       update_onlyoffice          get_version_onlyoffice
register_utility "OpenLogi"            install_openlogi         check_openlogi         uninstall_openlogi         update_openlogi            get_version_openlogi
register_utility "OpenSSH Server"      install_openssh_server   check_openssh_server   uninstall_openssh_server   update_openssh_server      get_version_openssh_server
register_utility "OpenTofu"            install_opentofu         check_opentofu         uninstall_opentofu         update_opentofu            get_version_opentofu
register_utility "Pay Respects"        install_pay_respects     check_pay_respects     uninstall_pay_respects     update_pay_respects        get_version_pay_respects
register_utility "PIA VPN"             install_pia_vpn          check_pia_vpn          uninstall_pia_vpn          update_pia_vpn             get_version_pia_vpn
register_utility "Podman"              install_podman           check_podman           uninstall_podman           update_podman              get_version_podman
register_utility "Postman"             install_postman          check_postman          uninstall_postman          update_postman             get_version_postman
register_utility "PowerShell"          install_powershell       check_powershell       uninstall_powershell       update_powershell          get_version_powershell
register_utility "Proton Mail Bridge"  install_protonmail_bridge check_protonmail_bridge uninstall_protonmail_bridge update_protonmail_bridge get_version_protonmail_bridge
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
register_utility "Thermalright TRCC"   install_trcc             check_trcc             uninstall_trcc             update_trcc                get_version_trcc
register_utility "Thorium Browser"     install_thorium          check_thorium          uninstall_thorium          update_thorium             get_version_thorium
register_utility "Thunderbird"         install_thunderbird      check_thunderbird      uninstall_thunderbird      update_thunderbird         get_version_thunderbird
register_utility "Timeshift"           install_timeshift        check_timeshift        uninstall_timeshift        update_timeshift           get_version_timeshift
register_utility "Trojita"             install_trojita          check_trojita          uninstall_trojita          update_trojita             get_version_trojita
register_utility "Create Snapshot"     setup_create_snapshot    check_always_false     noop_function              setup_create_snapshot
NO_RETRY["Create Snapshot"]=1
register_utility "Restore Snapshot"    setup_restore_snapshot   check_always_false     noop_function              setup_restore_snapshot
NO_RETRY["Restore Snapshot"]=1
register_utility "Delete Snapshot"     setup_delete_snapshot    check_always_false     noop_function              setup_delete_snapshot
NO_RETRY["Delete Snapshot"]=1

# Snapper: available on Arch, openSUSE, Debian/Ubuntu, and Fedora
if [[ "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "suse" || "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "fedora" ]]; then
    register_utility "Snapper"                   install_snapper          check_snapper          uninstall_snapper          update_snapper             get_version_snapper
fi
# Snapper GUI: Debian/Ubuntu and Arch
if [[ "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "arch" ]]; then
    register_utility "Snapper GUI"               install_snapper_gui      check_snapper_gui      uninstall_snapper_gui      update_snapper_gui         get_version_snapper_gui
fi
if [[ "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "suse" || "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "fedora" ]]; then
    register_utility "Create Snapshot (Snapper)" setup_create_snapshot    check_always_false     noop_function              setup_create_snapshot
    NO_RETRY["Create Snapshot (Snapper)"]=1
    register_utility "Restore Snapshot (Snapper)" setup_restore_snapshot  check_always_false     noop_function              setup_restore_snapshot
    NO_RETRY["Restore Snapshot (Snapper)"]=1
    register_utility "Delete Snapshot (Snapper)" setup_delete_snapshot    check_always_false     noop_function              setup_delete_snapshot
    NO_RETRY["Delete Snapshot (Snapper)"]=1
fi

# Btrfs Assistant: useful for any btrfs system regardless of snapshot tool
if [[ "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "suse" || "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "fedora" ]]; then
    register_utility "Btrfs Assistant"           install_btrfs_assistant  check_btrfs_assistant  uninstall_btrfs_assistant  update_btrfs_assistant     get_version_btrfs_assistant
fi

# Btrfs Tools: maintenance, backup, and deduplication utilities
if [[ "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "suse" || "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "fedora" ]]; then
    register_utility "btrfsmaintenance"          install_btrfsmaintenance check_btrfsmaintenance uninstall_btrfsmaintenance update_btrfsmaintenance    get_version_btrfsmaintenance
fi
if [[ "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "fedora" ]]; then
    register_utility "btrbk"                     install_btrbk            check_btrbk            uninstall_btrbk            update_btrbk               get_version_btrbk
    register_utility "duperemove"                install_duperemove       check_duperemove       uninstall_duperemove       update_duperemove          get_version_duperemove
fi
register_utility "Tor Browser"         install_tor_browser      check_tor_browser      uninstall_tor_browser      update_tor_browser         get_version_tor_browser
# UniFi Endpoint: Ubiquiti only ships .deb/.rpm packages (no AUR package)
if [[ "$DISTRO_FAMILY" != "arch" ]]; then
    register_utility "UniFi Endpoint"            install_unifi_endpoint   check_unifi_endpoint   uninstall_unifi_endpoint   update_unifi_endpoint      get_version_unifi_endpoint
fi
register_utility "Ventoy"              install_ventoy           check_ventoy           uninstall_ventoy           update_ventoy              get_version_ventoy
register_utility "Virt-Manager"        install_virt_manager     check_virt_manager     uninstall_virt_manager     update_virt_manager        get_version_virt_manager
register_utility "Visual Studio Code"  install_vscode           check_vscode           uninstall_vscode           update_vscode              get_version_vscode
register_utility "Vorta"               install_vorta            check_vorta            uninstall_vorta            update_vorta               get_version_vorta
register_utility "Vivaldi Browser"     install_vivaldi          check_vivaldi          uninstall_vivaldi          update_vivaldi             get_version_vivaldi
register_utility "VLC"                 install_vlc              check_vlc              uninstall_vlc              update_vlc                 get_version_vlc
register_utility "WinApps"             install_winapps          check_winapps          uninstall_winapps          update_winapps             get_version_winapps
register_utility "Wine"               install_wine             check_wine             uninstall_wine             update_wine                get_version_wine
register_utility "WireGuard Client"    install_wireguard_client check_wireguard_client uninstall_wireguard_client update_wireguard_client    get_version_wireguard_client
register_utility "WireGuard Server"    install_wireguard_server check_wireguard_server uninstall_wireguard_server update_wireguard_server    get_version_wireguard_server
register_utility "WPS Office"          install_wps_office       check_wps_office       uninstall_wps_office       update_wps_office          get_version_wps_office
register_utility "Zen Browser"         install_zen_browser      check_zen_browser      uninstall_zen_browser      update_zen_browser         get_version_zen_browser
register_utility "Zoom"                install_zoom             check_zoom             uninstall_zoom             update_zoom                get_version_zoom
register_utility "Zotero"              install_zotero           check_zotero           uninstall_zotero           update_zotero              get_version_zotero
register_utility "Zsh + Oh My Zsh"     install_zsh_setup        check_zsh_setup        uninstall_zsh_setup        update_zsh_setup           get_version_zsh_setup

# --- File Managers ---
# Most file managers are available on all supported distros (RHEL via EPEL).
# Exception: PCManFM-Qt is not packaged for RHEL/EPEL and is hidden there.
register_utility "Nautilus"            install_nautilus         check_nautilus         uninstall_nautilus         update_nautilus            get_version_nautilus
register_utility "Dolphin"             install_dolphin          check_dolphin          uninstall_dolphin          update_dolphin             get_version_dolphin
register_utility "Thunar"              install_thunar           check_thunar           uninstall_thunar           update_thunar              get_version_thunar
register_utility "Nemo"                install_nemo             check_nemo             uninstall_nemo             update_nemo                get_version_nemo
register_utility "Caja"                install_caja             check_caja             uninstall_caja             update_caja                get_version_caja
if [[ "$DISTRO_FAMILY" != "rhel" ]]; then
    register_utility "PCManFM-Qt"      install_pcmanfm_qt       check_pcmanfm_qt       uninstall_pcmanfm_qt       update_pcmanfm_qt          get_version_pcmanfm_qt
fi
register_utility "Krusader"            install_krusader         check_krusader         uninstall_krusader         update_krusader            get_version_krusader
register_utility "Midnight Commander"  install_midnight_commander check_midnight_commander uninstall_midnight_commander update_midnight_commander get_version_midnight_commander
register_utility "Ranger"              install_ranger           check_ranger           uninstall_ranger           update_ranger              get_version_ranger
register_utility "nnn"                 install_nnn              check_nnn              uninstall_nnn              update_nnn                 get_version_nnn

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

# --- Window Managers ---
# Most WMs are packaged on every supported distro (RHEL via EPEL).
# Hyprland is the exception — see its conditional gate below.
register_utility "awesome"             install_awesome          check_awesome          uninstall_awesome          update_awesome             get_version_awesome
register_utility "bspwm"               install_bspwm            check_bspwm            uninstall_bspwm            update_bspwm               get_version_bspwm
register_utility "dwm"                 install_dwm              check_dwm              uninstall_dwm              update_dwm                 get_version_dwm
register_utility "i3"                  install_i3               check_i3               uninstall_i3               update_i3                  get_version_i3
register_utility "Openbox"             install_openbox          check_openbox          uninstall_openbox          update_openbox             get_version_openbox
register_utility "Sway"                install_sway             check_sway             uninstall_sway             update_sway                get_version_sway

# Hyprland: official packages on Arch, Fedora (39+), and openSUSE Tumbleweed.
# Debian stable and Ubuntu < 24.04 lack it; RHEL/EPEL has no build.
if [[ "$DISTRO_FAMILY" == "arch" ]] || \
   [[ "$DISTRO_ID" == "fedora" ]] || \
   [[ "$DISTRO_ID" == "opensuse-tumbleweed" ]] || \
   [[ "$DISTRO_ID" == "ubuntu" && "${DISTRO_VERSION_ID%%.*}" -ge 24 ]]; then
    register_utility "Hyprland"        install_hyprland         check_hyprland         uninstall_hyprland         update_hyprland            get_version_hyprland
fi

# --- Login Screens (display managers + login themes) ---
# Standalone building blocks: install a login screen on a headless box, or theme
# an existing one. Only one display manager is enabled at a time (see
# login_screens.sh). Display managers are broadly packaged, so all are offered on
# every distro — an install fails cleanly where a package is genuinely absent.
register_utility "SDDM"                install_dm_sddm          check_dm_sddm          uninstall_dm_sddm          update_dm_sddm             get_version_dm_sddm
register_utility "GDM"                 install_dm_gdm           check_dm_gdm           uninstall_dm_gdm           update_dm_gdm              get_version_dm_gdm
register_utility "LightDM"             install_dm_lightdm       check_dm_lightdm       uninstall_dm_lightdm       update_dm_lightdm          get_version_dm_lightdm
register_utility "ly"                  install_dm_ly            check_dm_ly            uninstall_dm_ly            update_dm_ly               get_version_dm_ly
register_utility "LXDM"                install_dm_lxdm          check_dm_lxdm          uninstall_dm_lxdm          update_dm_lxdm             get_version_dm_lxdm
register_utility "SDDM Breeze Theme"   install_sddmtheme_breeze       check_sddmtheme_breeze       uninstall_sddmtheme_breeze       update_sddmtheme_breeze       get_version_sddmtheme_breeze
register_utility "SDDM Sugar Candy"    install_sddmtheme_sugar_candy  check_sddmtheme_sugar_candy  uninstall_sddmtheme_sugar_candy  update_sddmtheme_sugar_candy  get_version_sddmtheme_sugar_candy
register_utility "SDDM Astronaut"      install_sddmtheme_astronaut    check_sddmtheme_astronaut    uninstall_sddmtheme_astronaut    update_sddmtheme_astronaut    get_version_sddmtheme_astronaut
register_utility "LightDM Slick Greeter" install_lightdmtheme_slick   check_lightdmtheme_slick     uninstall_lightdmtheme_slick     update_lightdmtheme_slick     get_version_lightdmtheme_slick
# Community SDDM themes are fetched from GitHub — no point retrying on a failed download.
NO_RETRY["SDDM Sugar Candy"]=1
NO_RETRY["SDDM Astronaut"]=1

# --- Package Managers (additional / third-party — native managers untouched) ---
# Cross-distro managers that run alongside the native package manager.
# Flatpak is listed first: several utilities (Bottles, BoxBuddy, DistroShelf,
# Boxflat, Duplicati, ProtonUp-Qt) install through it and need it set up first.
register_utility "Flatpak Setup"       install_flatpak_setup    check_flatpak_setup    uninstall_flatpak_setup    update_flatpak_setup       get_version_flatpak_setup
register_utility "Homebrew"            install_homebrew         check_homebrew         uninstall_homebrew         update_homebrew            get_version_homebrew
register_utility "Nix"                 install_nix              check_nix              uninstall_nix              update_nix                 get_version_nix
register_utility "Snap (snapd)"        install_snap             check_snap             uninstall_snap             update_snap                get_version_snap

# Debian/Ubuntu-family only: third-party .deb / AUR-style helpers
if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    register_utility "deb-get"         install_deb_get          check_deb_get          uninstall_deb_get          update_deb_get             get_version_deb_get
    register_utility "Pacstall"        install_pacstall         check_pacstall         uninstall_pacstall         update_pacstall            get_version_pacstall
fi

# Arch-family only: AUR helpers
if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    register_utility "yay"             install_yay              check_yay              uninstall_yay              update_yay                 get_version_yay
    register_utility "paru"            install_paru             check_paru             uninstall_paru             update_paru                get_version_paru
fi

# --- Kernel Managers (System Tools › Kernel Managers) ---
# Tools that install/switch alternate kernels. Each is registered on every distro
# so the "Kernel Managers" folder always lists the options; the install function
# itself warns and stops when run on a distro it does not support. Mainline is
# listed first (registration order sets the order inside the folder).
register_utility "Mainline"               install_mainline                 check_mainline                 uninstall_mainline                 update_mainline                 get_version_mainline
register_utility "CachyOS Kernel Manager" install_cachyos_kernel_manager   check_cachyos_kernel_manager   uninstall_cachyos_kernel_manager   update_cachyos_kernel_manager   get_version_cachyos_kernel_manager
register_utility "Fedora Mainline Kernel" install_fedora_mainline_kernel   check_fedora_mainline_kernel   uninstall_fedora_mainline_kernel   update_fedora_mainline_kernel   get_version_fedora_mainline_kernel
register_utility "linux-tkg"              install_linux_tkg                check_linux_tkg                uninstall_linux_tkg                update_linux_tkg                get_version_linux_tkg
# Building a kernel from source is a long, interactive job — never auto-retry it.
NO_RETRY["linux-tkg"]=1

# --- Category definitions ---
# The order here determines the tab order in the left panel.
CATEGORIES=("System Tasks" "Backup" "Bootloaders" "Desktop Environments" "Development" "Disk Utilities" "Drivers" "File Managers" "Firewalls" "Gaming" "Internet" "Login Screens" "Package Managers" "Productivity" "Remote Admin Tools" "System Tools" "Window Managers")

# Category assignment for each utility (System Tasks are identified by SYSTEM_TASKS array)
UTILITY_CATEGORY["Angry IP Scanner"]="Internet"
UTILITY_CATEGORY["GRUB"]="Bootloaders"
UTILITY_CATEGORY["Limine"]="Bootloaders"
UTILITY_CATEGORY["systemd-boot"]="Bootloaders"
UTILITY_CATEGORY["Switch Bootloader"]="Bootloaders"
UTILITY_CATEGORY["Configure Bootloader"]="Bootloaders"
UTILITY_CATEGORY["GRUB Theme Selector"]="Bootloaders"
UTILITY_CATEGORY["Distro GRUB Themes"]="Bootloaders"
UTILITY_CATEGORY["vinceliuice GRUB Themes"]="Bootloaders"
UTILITY_CATEGORY["Catppuccin GRUB Theme"]="Bootloaders"
UTILITY_CATEGORY["HyperFluent GRUB Theme"]="Bootloaders"
UTILITY_CATEGORY["AMD CPU Microcode & Firmware"]="Drivers"
UTILITY_CATEGORY["AMD Drivers"]="Drivers"
UTILITY_CATEGORY["Intel CPU Microcode & Thermal"]="Drivers"
UTILITY_CATEGORY["LACT"]="Drivers"
UTILITY_CATEGORY["NVIDIA Drivers"]="Drivers"
UTILITY_CATEGORY["OpenLogi"]="Drivers"
UTILITY_CATEGORY["Thermalright TRCC"]="Drivers"
UTILITY_CATEGORY["XEN Guest Utilities"]="Drivers"
UTILITY_CATEGORY["Nautilus"]="File Managers"
UTILITY_CATEGORY["Dolphin"]="File Managers"
UTILITY_CATEGORY["Thunar"]="File Managers"
UTILITY_CATEGORY["Nemo"]="File Managers"
UTILITY_CATEGORY["Caja"]="File Managers"
UTILITY_CATEGORY["PCManFM-Qt"]="File Managers"
UTILITY_CATEGORY["Krusader"]="File Managers"
UTILITY_CATEGORY["Midnight Commander"]="File Managers"
UTILITY_CATEGORY["Ranger"]="File Managers"
UTILITY_CATEGORY["nnn"]="File Managers"
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
UTILITY_CATEGORY["awesome"]="Window Managers"
UTILITY_CATEGORY["bspwm"]="Window Managers"
UTILITY_CATEGORY["dwm"]="Window Managers"
UTILITY_CATEGORY["Hyprland"]="Window Managers"
UTILITY_CATEGORY["i3"]="Window Managers"
UTILITY_CATEGORY["Openbox"]="Window Managers"
UTILITY_CATEGORY["Sway"]="Window Managers"
UTILITY_CATEGORY["SDDM"]="Login Screens"
UTILITY_CATEGORY["GDM"]="Login Screens"
UTILITY_CATEGORY["LightDM"]="Login Screens"
UTILITY_CATEGORY["ly"]="Login Screens"
UTILITY_CATEGORY["LXDM"]="Login Screens"
UTILITY_CATEGORY["SDDM Breeze Theme"]="Login Screens"
UTILITY_CATEGORY["SDDM Sugar Candy"]="Login Screens"
UTILITY_CATEGORY["SDDM Astronaut"]="Login Screens"
UTILITY_CATEGORY["LightDM Slick Greeter"]="Login Screens"
UTILITY_CATEGORY["Flatpak Setup"]="Package Managers"
UTILITY_CATEGORY["Homebrew"]="Package Managers"
UTILITY_CATEGORY["Nix"]="Package Managers"
UTILITY_CATEGORY["Snap (snapd)"]="Package Managers"
UTILITY_CATEGORY["deb-get"]="Package Managers"
UTILITY_CATEGORY["Pacstall"]="Package Managers"
UTILITY_CATEGORY["yay"]="Package Managers"
UTILITY_CATEGORY["paru"]="Package Managers"
UTILITY_CATEGORY["Mainline"]="System Tools"
UTILITY_CATEGORY["CachyOS Kernel Manager"]="System Tools"
UTILITY_CATEGORY["Fedora Mainline Kernel"]="System Tools"
UTILITY_CATEGORY["linux-tkg"]="System Tools"
UTILITY_CATEGORY["Betterbird"]="Internet"
UTILITY_CATEGORY["Bitwarden Client"]="Productivity"
UTILITY_CATEGORY["Bitwarden Extension"]="Internet"
UTILITY_CATEGORY["Bottles"]="Gaming"
UTILITY_CATEGORY["Boxflat"]="Gaming"
UTILITY_CATEGORY["Brave Browser"]="Internet"
UTILITY_CATEGORY["Brave Debloat"]="Internet"
UTILITY_CATEGORY["Brave Origin"]="Internet"
UTILITY_CATEGORY["Btop"]="System Tools"
UTILITY_CATEGORY["Chromium"]="Internet"
UTILITY_CATEGORY["Claude Code"]="Development"
UTILITY_CATEGORY["Claws Mail"]="Internet"
UTILITY_CATEGORY["Cockpit"]="Remote Admin Tools"
UTILITY_CATEGORY["Cursor IDE"]="Development"
UTILITY_CATEGORY["DBeaver"]="Development"
UTILITY_CATEGORY["Devolutions RDM"]="Remote Admin Tools"
UTILITY_CATEGORY["Discord"]="Internet"
UTILITY_CATEGORY["Docker"]="Development"
UTILITY_CATEGORY["Distrobox"]="Development"
UTILITY_CATEGORY["BoxBuddy"]="Development"
UTILITY_CATEGORY["DistroShelf"]="Development"
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
UTILITY_CATEGORY["NeoMutt"]="Internet"
UTILITY_CATEGORY["Nextcloud Desktop"]="Productivity"
UTILITY_CATEGORY["NVM"]="Development"
UTILITY_CATEGORY["OBS Studio"]="Productivity"
UTILITY_CATEGORY["OCCT"]="System Tools"
UTILITY_CATEGORY["Obsidian"]="Productivity"
UTILITY_CATEGORY["OnlyOffice"]="Productivity"
UTILITY_CATEGORY["OpenSSH Server"]="Remote Admin Tools"
UTILITY_CATEGORY["PIA VPN"]="Internet"
UTILITY_CATEGORY["Postman"]="Development"
UTILITY_CATEGORY["PowerShell"]="Development"
UTILITY_CATEGORY["Proton Mail Bridge"]="Internet"
UTILITY_CATEGORY["ProtonUp-Qt"]="Gaming"
UTILITY_CATEGORY["ProtonVPN"]="Internet"
UTILITY_CATEGORY["QBittorrent"]="Internet"
UTILITY_CATEGORY["Remmina"]="Remote Admin Tools"
UTILITY_CATEGORY["Signal Desktop"]="Internet"
UTILITY_CATEGORY["SponsorBlock Extension"]="Internet"
UTILITY_CATEGORY["Stacer"]="System Tools"
UTILITY_CATEGORY["Standard Notes"]="Productivity"
UTILITY_CATEGORY["Steam App"]="Gaming"
UTILITY_CATEGORY["Syncthing"]="Internet"
UTILITY_CATEGORY["Tailscale"]="Internet"
UTILITY_CATEGORY["Telegram Desktop"]="Internet"
UTILITY_CATEGORY["Termius SSH Client"]="Remote Admin Tools"
UTILITY_CATEGORY["Thorium Browser"]="Internet"
UTILITY_CATEGORY["Thunderbird"]="Internet"
UTILITY_CATEGORY["Trojita"]="Internet"
UTILITY_CATEGORY["Timeshift"]="Backup"
UTILITY_CATEGORY["Create Snapshot"]="Backup"
UTILITY_CATEGORY["Restore Snapshot"]="Backup"
UTILITY_CATEGORY["Delete Snapshot"]="Backup"
UTILITY_CATEGORY["Snapper"]="Backup"
UTILITY_CATEGORY["Snapper GUI"]="Backup"
UTILITY_CATEGORY["Btrfs Assistant"]="Disk Utilities"
UTILITY_CATEGORY["btrfsmaintenance"]="Disk Utilities"
UTILITY_CATEGORY["btrbk"]="Disk Utilities"
UTILITY_CATEGORY["duperemove"]="Disk Utilities"
UTILITY_CATEGORY["Create Snapshot (Snapper)"]="Backup"
UTILITY_CATEGORY["Restore Snapshot (Snapper)"]="Backup"
UTILITY_CATEGORY["Delete Snapshot (Snapper)"]="Backup"
UTILITY_CATEGORY["Déjà Dup"]="Backup"
UTILITY_CATEGORY["Kup"]="Backup"
UTILITY_CATEGORY["Vorta"]="Backup"
UTILITY_CATEGORY["Duplicati"]="Backup"
UTILITY_CATEGORY["Visual Studio Code"]="Development"
UTILITY_CATEGORY["Vivaldi Browser"]="Internet"
UTILITY_CATEGORY["WinApps"]="Productivity"
UTILITY_CATEGORY["Wine"]="Gaming"
UTILITY_CATEGORY["WireGuard Client"]="Internet"
UTILITY_CATEGORY["WireGuard Server"]="Internet"
UTILITY_CATEGORY["WPS Office"]="Productivity"
UTILITY_CATEGORY["Zsh + Oh My Zsh"]="System Tools"
UTILITY_CATEGORY["Pay Respects"]="System Tools"
UTILITY_CATEGORY["Ansible"]="Development"
UTILITY_CATEGORY["AnyDesk"]="Remote Admin Tools"
UTILITY_CATEGORY["Audacity"]="Productivity"
UTILITY_CATEGORY["ClamAV"]="System Tools"
UTILITY_CATEGORY["Element (Matrix)"]="Internet"
UTILITY_CATEGORY["Euro-Office"]="Productivity"
UTILITY_CATEGORY["Evolution"]="Internet"
UTILITY_CATEGORY["Geary"]="Internet"
UTILITY_CATEGORY["Flameshot"]="Productivity"
UTILITY_CATEGORY["Go SDK"]="Development"
UTILITY_CATEGORY["UFW Firewall"]="Firewalls"
UTILITY_CATEGORY["Gufw (Firewall GUI)"]="Firewalls"
UTILITY_CATEGORY["firewalld"]="Firewalls"
UTILITY_CATEGORY["firewall-config (GUI)"]="Firewalls"
UTILITY_CATEGORY["HandBrake"]="Productivity"
UTILITY_CATEGORY["Inkscape"]="Productivity"
UTILITY_CATEGORY["Input Leap"]="System Tools"
UTILITY_CATEGORY["k9s"]="Development"
UTILITY_CATEGORY["Kdenlive"]="Productivity"
UTILITY_CATEGORY["Krita"]="Productivity"
UTILITY_CATEGORY["kubectl"]="Development"
UTILITY_CATEGORY["Libation"]="Productivity"
UTILITY_CATEGORY["LibreWolf"]="Internet"
UTILITY_CATEGORY["LocalSend"]="Internet"
UTILITY_CATEGORY["Logseq"]="Productivity"
UTILITY_CATEGORY["Mark Text"]="Productivity"
UTILITY_CATEGORY["Neovim"]="Development"
UTILITY_CATEGORY["Node.js"]="Development"
UTILITY_CATEGORY["OpenTofu"]="Development"
UTILITY_CATEGORY["Podman"]="Development"
UTILITY_CATEGORY["pyenv"]="Development"
UTILITY_CATEGORY["RustDesk"]="Remote Admin Tools"
UTILITY_CATEGORY["Enable RDP"]="Remote Admin Tools"
UTILITY_CATEGORY["OpenRSAT"]="Remote Admin Tools"
UTILITY_CATEGORY["Rustup"]="Development"
UTILITY_CATEGORY["Slack"]="Internet"
UTILITY_CATEGORY["Terraform"]="Development"
UTILITY_CATEGORY["Tor Browser"]="Internet"
UTILITY_CATEGORY["UniFi Endpoint"]="Internet"
UTILITY_CATEGORY["Ventoy"]="Disk Utilities"
UTILITY_CATEGORY["GParted"]="Disk Utilities"
UTILITY_CATEGORY["Virt-Manager"]="Development"
UTILITY_CATEGORY["VLC"]="Productivity"
UTILITY_CATEGORY["Zen Browser"]="Internet"
UTILITY_CATEGORY["Zoom"]="Internet"
UTILITY_CATEGORY["Zotero"]="Productivity"

# Subcategory assignments — utility name → subcategory label within the parent category
UTILITY_SUBCATEGORY["Brave Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Brave Debloat"]="Web Browser Tweaks"
UTILITY_SUBCATEGORY["Brave Origin"]="Web Browsers"
UTILITY_SUBCATEGORY["Chromium"]="Web Browsers"
UTILITY_SUBCATEGORY["Firefox"]="Web Browsers"
UTILITY_SUBCATEGORY["Google Chrome"]="Web Browsers"
UTILITY_SUBCATEGORY["Thorium Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Vivaldi Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Zen Browser"]="Web Browsers"
UTILITY_SUBCATEGORY["Bitwarden Extension"]="Web Browser Extensions"
UTILITY_SUBCATEGORY["Joplin Web Clipper"]="Web Browser Extensions"
UTILITY_SUBCATEGORY["SponsorBlock Extension"]="Web Browser Extensions"
UTILITY_SUBCATEGORY["Discord"]="Messaging"
UTILITY_SUBCATEGORY["Signal Desktop"]="Messaging"
UTILITY_SUBCATEGORY["Telegram Desktop"]="Messaging"
UTILITY_SUBCATEGORY["Betterbird"]="Email Clients"
UTILITY_SUBCATEGORY["Claws Mail"]="Email Clients"
UTILITY_SUBCATEGORY["Evolution"]="Email Clients"
UTILITY_SUBCATEGORY["Geary"]="Email Clients"
UTILITY_SUBCATEGORY["KMail"]="Email Clients"
UTILITY_SUBCATEGORY["NeoMutt"]="Email Clients"
UTILITY_SUBCATEGORY["Proton Mail Bridge"]="Email Clients"
UTILITY_SUBCATEGORY["Thunderbird"]="Email Clients"
UTILITY_SUBCATEGORY["Trojita"]="Email Clients"
UTILITY_SUBCATEGORY["FileZilla"]="File Transfer"
UTILITY_SUBCATEGORY["LocalSend"]="File Transfer"
UTILITY_SUBCATEGORY["Remmina"]="Remote Access"
UTILITY_SUBCATEGORY["Termius SSH Client"]="Remote Access"
UTILITY_SUBCATEGORY["OpenSSH Server"]="Remote Access"
UTILITY_SUBCATEGORY["Devolutions RDM"]="Remote Access"
UTILITY_SUBCATEGORY["Enable RDP"]="Remote Access"
UTILITY_SUBCATEGORY["Cockpit"]="Remote Access"
UTILITY_SUBCATEGORY["PIA VPN"]="VPN"
UTILITY_SUBCATEGORY["ProtonVPN"]="VPN"
UTILITY_SUBCATEGORY["Tailscale"]="VPN"
UTILITY_SUBCATEGORY["UniFi Endpoint"]="VPN"
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
UTILITY_SUBCATEGORY["Distrobox"]="Distrobox"
UTILITY_SUBCATEGORY["BoxBuddy"]="Distrobox"
UTILITY_SUBCATEGORY["DistroShelf"]="Distrobox"
UTILITY_SUBCATEGORY["Steam App"]="Game Launchers"
UTILITY_SUBCATEGORY["Lutris"]="Game Launchers"
UTILITY_SUBCATEGORY["Heroic Games Launcher"]="Game Launchers"
UTILITY_SUBCATEGORY["Bottles"]="Game Launchers"
UTILITY_SUBCATEGORY["Boxflat"]="Gaming Utilities"
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
UTILITY_SUBCATEGORY["Snapper GUI"]="Snapper"
UTILITY_SUBCATEGORY["Btrfs Assistant"]="Btrfs Tools"
UTILITY_SUBCATEGORY["btrfsmaintenance"]="Btrfs Tools"
UTILITY_SUBCATEGORY["btrbk"]="Btrfs Tools"
UTILITY_SUBCATEGORY["duperemove"]="Btrfs Tools"
UTILITY_SUBCATEGORY["Create Snapshot (Snapper)"]="Snapper"
UTILITY_SUBCATEGORY["Restore Snapshot (Snapper)"]="Snapper"
UTILITY_SUBCATEGORY["Delete Snapshot (Snapper)"]="Snapper"
UTILITY_SUBCATEGORY["Déjà Dup"]="File Backup"
UTILITY_SUBCATEGORY["Kup"]="File Backup"
UTILITY_SUBCATEGORY["Vorta"]="File Backup"
UTILITY_SUBCATEGORY["Duplicati"]="File Backup"
UTILITY_SUBCATEGORY["AMD CPU Microcode & Firmware"]="CPU Microcode"
UTILITY_SUBCATEGORY["AMD Drivers"]="GPU Drivers"
UTILITY_SUBCATEGORY["Intel CPU Microcode & Thermal"]="CPU Microcode"
UTILITY_SUBCATEGORY["LACT"]="GPU Drivers"
UTILITY_SUBCATEGORY["NVIDIA Drivers"]="GPU Drivers"
UTILITY_SUBCATEGORY["Nautilus"]="Graphical"
UTILITY_SUBCATEGORY["Dolphin"]="Graphical"
UTILITY_SUBCATEGORY["Thunar"]="Graphical"
UTILITY_SUBCATEGORY["Nemo"]="Graphical"
UTILITY_SUBCATEGORY["Caja"]="Graphical"
UTILITY_SUBCATEGORY["PCManFM-Qt"]="Graphical"
UTILITY_SUBCATEGORY["Krusader"]="Graphical"
UTILITY_SUBCATEGORY["Midnight Commander"]="Terminal"
UTILITY_SUBCATEGORY["Ranger"]="Terminal"
UTILITY_SUBCATEGORY["nnn"]="Terminal"
UTILITY_SUBCATEGORY["SDDM"]="Display Managers"
UTILITY_SUBCATEGORY["GDM"]="Display Managers"
UTILITY_SUBCATEGORY["LightDM"]="Display Managers"
UTILITY_SUBCATEGORY["ly"]="Display Managers"
UTILITY_SUBCATEGORY["LXDM"]="Display Managers"
UTILITY_SUBCATEGORY["GRUB Theme Selector"]="GRUB Themes"
UTILITY_SUBCATEGORY["Distro GRUB Themes"]="GRUB Themes"
UTILITY_SUBCATEGORY["vinceliuice GRUB Themes"]="GRUB Themes"
UTILITY_SUBCATEGORY["Catppuccin GRUB Theme"]="GRUB Themes"
UTILITY_SUBCATEGORY["HyperFluent GRUB Theme"]="GRUB Themes"
UTILITY_SUBCATEGORY["SDDM Breeze Theme"]="SDDM Themes"
UTILITY_SUBCATEGORY["SDDM Sugar Candy"]="SDDM Themes"
UTILITY_SUBCATEGORY["SDDM Astronaut"]="SDDM Themes"
UTILITY_SUBCATEGORY["LightDM Slick Greeter"]="LightDM Greeters"

# Kernel Managers (grouped under the System Tools tab)
UTILITY_SUBCATEGORY["Mainline"]="Kernel Managers"
UTILITY_SUBCATEGORY["CachyOS Kernel Manager"]="Kernel Managers"
UTILITY_SUBCATEGORY["Fedora Mainline Kernel"]="Kernel Managers"
UTILITY_SUBCATEGORY["linux-tkg"]="Kernel Managers"

# Display name overrides — shown in the menu instead of the utility key
UTILITY_DISPLAY_NAME["Bottles"]="Bottles (Requires Flatpak)"
UTILITY_DISPLAY_NAME["Boxflat"]="Boxflat (Requires Flatpak)"
UTILITY_DISPLAY_NAME["ProtonUp-Qt"]="ProtonUp-Qt (Requires Flatpak)"
UTILITY_DISPLAY_NAME["Duplicati"]="Duplicati (Requires Flatpak)"
UTILITY_DISPLAY_NAME["BoxBuddy"]="BoxBuddy (Requires Flatpak)"
UTILITY_DISPLAY_NAME["DistroShelf"]="DistroShelf (Requires Flatpak)"
UTILITY_DISPLAY_NAME["Zen Browser"]="Zen Browser (Beta)"

# System Tasks: subcategory folders appear at the top, plain tasks keep their order.
UTILITY_SUBCATEGORY["Full System Upgrade/Update"]="System Updaters"
UTILITY_SUBCATEGORY["System Updates"]="System Updaters"
UTILITY_SUBCATEGORY["Unattended Upgrades"]="System Updaters"
UTILITY_SUBCATEGORY["Configure Unattended Upgrades"]="System Updaters"
UTILITY_SUBCATEGORY["Mount Local Drive"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["Mount NFS Share"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["Mount SMB Share"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["Manage Share"]="Mount / Unmount Shares"
UTILITY_SUBCATEGORY["GTK Window Fix"]="WSL Fixes"

# Explicit subcategory display order within each category tab
SUBCATEGORY_ORDER["Development"]="IDEs & Editors|Distrobox"
SUBCATEGORY_ORDER["Drivers"]="CPU Microcode|GPU Drivers"
SUBCATEGORY_ORDER["File Managers"]="Graphical|Terminal"
SUBCATEGORY_ORDER["Internet"]="Web Browsers|Web Browser Tweaks|Web Browser Extensions|Messaging|Email Clients|File Transfer|VPN"
SUBCATEGORY_ORDER["Remote Admin Tools"]="Remote Access"
SUBCATEGORY_ORDER["Bootloaders"]="GRUB Themes"
SUBCATEGORY_ORDER["Login Screens"]="Display Managers|SDDM Themes|LightDM Greeters"
SUBCATEGORY_ORDER["System Tools"]="Kernel Managers"

# --- Descriptions (shown in the info panel when an item is highlighted) ---

# System Tasks
UTILITY_DESCRIPTION["Full System Upgrade/Update"]="Performs a comprehensive system upgrade including all configured package managers and removes unused packages."
UTILITY_DESCRIPTION["System Updates"]="Installs and configures automatic system update scheduling via systemd timers or cron."
UTILITY_DESCRIPTION["Unattended Upgrades"]="Enables the Debian/Ubuntu unattended-upgrades package so security (and optionally other) updates install automatically in the background. Runs the package's own debconf setup so you can choose what gets updated. The package must already be present (it ships by default on most Ubuntu installs)."
UTILITY_DESCRIPTION["Configure Unattended Upgrades"]="Opens /etc/apt/apt.conf.d/50unattended-upgrades in your editor (\$EDITOR, or nano) so you can choose which update origins auto-install, blacklist packages, and set auto-reboot and notification behavior. Only appears when the unattended-upgrades package is installed."
UTILITY_DESCRIPTION["Mount Local Drive"]="Interactively selects an unmounted block device and adds it to /etc/fstab, mounting it permanently under ~/media/<name>. Supports ext4, xfs, btrfs, NTFS, exFAT, and vFAT. Backs up fstab before any changes."
UTILITY_DESCRIPTION["Mount NFS Share"]="Discovers NFS exports from a remote server via showmount and mounts the chosen share persistently via /etc/fstab. Installs NFS client tools if needed and backs up fstab before any changes."
UTILITY_DESCRIPTION["Mount SMB Share"]="Connects to an SMB/CIFS server, prompts for credentials, lists available shares, and mounts the chosen share persistently via /etc/fstab. Credentials are stored in a private file under HOME. Installs cifs-utils if needed and backs up fstab before any changes."
UTILITY_DESCRIPTION["Manage Share"]="Update or unmount an existing linux_util-managed mount. Update: change server, share path, credentials, or mount location for NFS, SMB, or local disk mounts. Unmount: remove the share, delete the mount point directory, clear the fstab entry, and remove the KDE Dolphin Places entry. Backs up fstab before any changes."
UTILITY_DESCRIPTION["NVIDIA Drivers"]="Installs proprietary NVIDIA GPU drivers for optimal 3D graphics and compute performance."

# Bootloaders
UTILITY_DESCRIPTION["GRUB"]="GRand Unified Bootloader — the most widely used bootloader on Linux, supporting BIOS and UEFI, multi-OS boot menus, encrypted volumes, and virtually every filesystem."
UTILITY_DESCRIPTION["Limine"]="Modern, portable bootloader supporting BIOS and UEFI (x86_64 and aarch64). Known for its fast startup, clean configuration, and native Limine Boot Protocol used by hobby OS development."
UTILITY_DESCRIPTION["systemd-boot"]="Lightweight EFI-only bootloader (formerly gummiboot) that is part of systemd. Zero dependencies, simple drop-in entry files, and automatic discovery of installed kernels on systemd-based distributions."
UTILITY_DESCRIPTION["Switch Bootloader"]="Interactively switch between GRUB, Limine, and systemd-boot. Detects your active bootloader, installs the chosen replacement, deploys it to disk or the EFI partition, and optionally removes the old one. Always snapshot before switching."
UTILITY_DESCRIPTION["Configure Bootloader"]="Configure your active bootloader. GRUB: set timeout, kernel parameters, regenerate config, or edit /etc/default/grub. systemd-boot: edit loader.conf, set default entry, manage boot entries. Limine: edit limine.conf, redeploy to disk. All: rebuild missing initramfs images for kernels the bootloader silently dropped."
# GRUB Themes — installed into GRUB's themes dir, set via GRUB_THEME= in /etc/default/grub, then grub.cfg is regenerated. Require GRUB to be the active bootloader and an internet connection.
UTILITY_DESCRIPTION["GRUB Theme Selector"]="Switch the active GRUB theme without reinstalling. Lists the themes already installed in GRUB's themes directory (plus the stock no-theme menu), marks the one that is currently active, and points GRUB_THEME= at your choice before regenerating grub.cfg. Requires GRUB."
UTILITY_DESCRIPTION["Distro GRUB Themes"]="Per-distro logo boot themes from AdisonCavani/distro-grub-themes. Picks the theme matching your distribution (falling back to the first available), installs it into GRUB's themes directory, and activates it. Requires GRUB and an internet connection."
UTILITY_DESCRIPTION["vinceliuice GRUB Themes"]="Polished GRUB themes from vinceliuice/grub2-themes. Runs the upstream installer to set up the 'tela' variant by default (vimix, stylish, whitesur, and slaze are also available); the installer copies the theme, edits /etc/default/grub, and regenerates the config. Requires GRUB and an internet connection."
UTILITY_DESCRIPTION["Catppuccin GRUB Theme"]="The soothing pastel Catppuccin theme for GRUB (catppuccin/grub). Installs the 'mocha' flavor by default (latte, frappe, and macchiato are in the repo) into GRUB's themes directory and activates it. Requires GRUB and an internet connection."
UTILITY_DESCRIPTION["HyperFluent GRUB Theme"]="A sleek, modern animated GRUB theme from Coopydood/HyperFluent-GRUB-Theme. Installs the variant matching your distribution (falling back to a generic one) into GRUB's themes directory and activates it. Requires GRUB and an internet connection."

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
UTILITY_DESCRIPTION["Cockpit"]="Web-based server management console reachable at https://<host>:9090. Provides a browser UI for system metrics, logs, storage, networking, services, containers, user accounts, and a built-in terminal. Enables cockpit.socket so the service activates on first connection, and opens 9090/tcp in the active firewall (firewalld or UFW)."
UTILITY_DESCRIPTION["Enable RDP"]="Enables Remote Desktop Protocol access to this machine using the XRDP server."
UTILITY_DESCRIPTION["OpenRSAT"]="Cross-platform Active Directory management console from Tranquil IT (a modern Microsoft RSAT-like tool) for managing users, groups, OUs, and DNS records. Installs the latest GitHub release: a .deb on Debian/Ubuntu, an .rpm on Fedora/RHEL (x86_64), or the standalone Linux binary on openSUSE. Not available on Arch."
UTILITY_DESCRIPTION["AMD CPU Microcode & Firmware"]="Installs AMD CPU microcode updates and linux-firmware blobs (PSP/SMU, Wi-Fi, Bluetooth, and other device firmware) for Ryzen, Threadripper, and EPYC platforms."
UTILITY_DESCRIPTION["Intel CPU Microcode & Thermal"]="Installs Intel CPU microcode updates and the thermald thermal management daemon for 10th Gen through Core Ultra (Arrow Lake) platforms."
UTILITY_DESCRIPTION["AMD Drivers"]="Installs open-source AMD GPU drivers (AMDGPU/Mesa) for optimal graphics performance."
UTILITY_DESCRIPTION["LACT"]="Linux AMDGPU Top — graphical tool for overclocking, undervolting, and monitoring AMD GPUs. Provides fan control, power limit adjustments, and real-time sensor readings. A reboot is required after installation before changes can be applied."
UTILITY_DESCRIPTION["Flatpak Setup"]="Configures the Flatpak package manager and adds the Flathub repository for sandboxed applications."
UTILITY_DESCRIPTION["UFW Firewall"]="Installs and configures Uncomplicated Firewall with sensible default rules (deny incoming, allow outgoing, allow SSH). Disables firewalld first if it is active — only one firewall manager should run at a time."
UTILITY_DESCRIPTION["Gufw (Firewall GUI)"]="Graphical frontend for UFW to view status, toggle the firewall, and manage rules and app profiles. Installs UFW first if it is not already present."
UTILITY_DESCRIPTION["firewalld"]="Dynamic zone-based firewall daemon, the default on Fedora, RHEL, and openSUSE. Managed with firewall-cmd or the firewall-config GUI. Disables UFW first if it is active — only one firewall manager should run at a time."
UTILITY_DESCRIPTION["firewall-config (GUI)"]="Graphical configuration tool for firewalld to manage zones, services, ports, and rich rules. Installs firewalld first if it is not already present."
UTILITY_DESCRIPTION["Num Lock at Boot"]="Enables Num Lock automatically on all TTY consoles and the display manager login screen at boot."
UTILITY_DESCRIPTION["Local Time Zone / Locale"]="Lets you interactively set your system time zone, locale, or both in one task."
UTILITY_DESCRIPTION["Command-Not-Found Prompt"]="Enables auto-suggestion to install missing command packages when a command is not found."
UTILITY_DESCRIPTION["Delete Default Cloud-Init User"]="Removes the stock user that cloud/VM images ship with, along with its home directory. Detects the known default accounts (ubuntu, debian, centos, alpine) by presence — the status shows 'Cloud Init user found' while one exists and goes blank once removed. Uses deluser --remove-home (userdel --remove where deluser is absent). Confirms before deleting, refuses to delete the account you are logged in as, and is a no-op when none exist."
UTILITY_DESCRIPTION["Fix RDP Kerberos Delay"]="Stops Remmina/FreeRDP (xfreerdp) from stalling ~20s before each Windows RDP login. The MIT krb5 sample config that ships with the krb5 package leaves dns_lookup_kdc at its default of true, so krb5 does a DNS SRV lookup for the server's Kerberos realm, fails to reach a KDC, and times out before falling back to NTLM. Sets dns_lookup_kdc, dns_lookup_realm, and rdns to false under [libdefaults] in /etc/krb5.conf — realm-agnostic, so it fixes every domain, not just one. Backs up the file first, leaves all other sections untouched, and is fully reversible."
UTILITY_DESCRIPTION["Fix Broken Packages"]="Repairs half-installed packages and unmet dependencies (dpkg --configure -a / apt --fix-broken, dnf distro-sync, pacman -Syu, zypper verify). Read-only checks run automatically; any step that adds or removes packages is confirmed first."
UTILITY_DESCRIPTION["Fix Package Repos"]="Refreshes repository metadata and repairs common repo errors (stale caches, unreachable mirrors, missing keys). Clearing caches or reinitializing the keyring is confirmed before it runs."
UTILITY_DESCRIPTION["Reset Repos to Default"]="Restores base distro repositories toward their stock state. Backs up all repo config first, keeps third-party repos that installed packages depend on, and prompts (keep/disable/remove) for each unused third-party repo."
UTILITY_DESCRIPTION["Create Snapshot"]="Creates a system snapshot using the active backup backend (Timeshift or Snapper). Prompts for an optional description."
UTILITY_DESCRIPTION["Restore Snapshot"]="Restores the system from a previously created snapshot. Lists all available snapshots and asks for confirmation before proceeding."
UTILITY_DESCRIPTION["Delete Snapshot"]="Permanently removes one or more snapshots. Lists all available snapshots and asks for confirmation before deleting."
UTILITY_DESCRIPTION["GTK Window Fix"]="Restores the minimize, maximize, and close buttons on GTK app title bars (GNOME, Cinnamon, MATE, Xfce). Under WSLg the default window-manager layout omits minimize/maximize, leaving GTK apps such as Remmina, Nautilus, and Files with only a close button. Sets the per-user window-manager button-layout preference; KDE shows all three by default and is skipped."

# Development
UTILITY_DESCRIPTION["Ansible"]="IT automation tool for provisioning, configuration management, and application deployment using agentless SSH-based playbooks."
UTILITY_DESCRIPTION["Claude Code"]="Anthropic's AI coding assistant that runs in the terminal for code generation, editing, and analysis."
UTILITY_DESCRIPTION["Cursor IDE"]="AI-powered code editor built on VS Code with deeply integrated AI features for code completion and chat."
UTILITY_DESCRIPTION["DBeaver"]="Universal database management tool supporting PostgreSQL, MySQL, SQLite, Oracle, and many more."
UTILITY_DESCRIPTION["Docker"]="Container platform for building, shipping, and running applications in isolated environments."
UTILITY_DESCRIPTION["Distrobox"]="Runs any Linux distribution inside your terminal, tightly integrated with the host (shared home, X11/Wayland, audio, and devices). Use it to run software from another distro without touching your base system. Installed from the native package where available (EPEL on RHEL), otherwise via the upstream rootless installer into ~/.local. Requires a container backend — Podman or Docker."
UTILITY_DESCRIPTION["BoxBuddy"]="Simple GTK4/libadwaita graphical front-end for Distrobox. Create, enter, upgrade, and delete boxes, install packages, and export apps without memorising commands. Installed via Flatpak from Flathub; it does not bundle Distrobox, so install Distrobox first."
UTILITY_DESCRIPTION["DistroShelf"]="Modern GTK4/libadwaita graphical manager for Distrobox containers — view status and details, install packages, manage exported applications, open terminal sessions, and clone or delete boxes. Installed via Flatpak from Flathub; requires Distrobox on the host."
UTILITY_DESCRIPTION["GitHub CLI"]="Official command-line interface for GitHub — manage repos, issues, PRs, and workflows from the terminal."
UTILITY_DESCRIPTION["Go SDK"]="Official Go programming language SDK with the compiler, standard library, and toolchain."
UTILITY_DESCRIPTION["JetBrains Toolbox"]="Manager for installing and updating JetBrains IDEs such as IntelliJ, PyCharm, and WebStorm."
UTILITY_DESCRIPTION["k9s"]="Terminal-based UI for interacting with Kubernetes clusters — browse, observe, and manage workloads in real time."
UTILITY_DESCRIPTION["kubectl"]="Official Kubernetes command-line tool for deploying applications and managing cluster resources."
UTILITY_DESCRIPTION["Neovim"]="Hyperextensible Vim-based text editor focused on extensibility and usability with Lua-powered configuration."
UTILITY_DESCRIPTION["Node.js"]="JavaScript runtime built on Chrome's V8 engine for building fast, scalable server-side and CLI applications."
UTILITY_DESCRIPTION["NVM"]="Node Version Manager — install and switch between multiple Node.js versions with ease."
UTILITY_DESCRIPTION["Thermalright TRCC"]="Community Linux port of the Thermalright LCD Control Center — drives the LCD screens and RGB LED segments on Thermalright CPU coolers, AIO pump heads and fan hubs, with themes, video and GIF playback, sensor overlays, a CLI and a REST API. Installed from upstream's own package on Debian/Ubuntu and Arch; Fedora, RHEL and openSUSE get the PyPI build via pipx, because upstream's RPM is compiled against the maintainer's own Fedora release and hard-requires a python nvidia-ml-py module no RPM repository ships."
UTILITY_DESCRIPTION["OpenLogi"]="Local-first alternative to Logitech Options+ for Logi Bolt, Unifying, Bluetooth, and wired Logitech peripherals — button and gesture remapping, DPI presets, SmartShift, keyboard F-key remapping, and UVC webcam controls, with no account or telemetry and a plain TOML config. Installed from upstream's own .deb/.rpm/.pkg.tar.zst (it is in no distro's repos); the package's udev rules grant device access without root, and the installer enables the per-user openlogi-agent.service that drives the devices."
UTILITY_DESCRIPTION["OpenTofu"]="Open-source Terraform fork for infrastructure-as-code provisioning across cloud providers and on-prem resources."
UTILITY_DESCRIPTION["Pay Respects"]="Press F after a mistyped or failed command and it suggests the fix — a Rust replacement for thefuck, with an inline Ctrl+X correction mode and its own command-not-found handler. Installed from upstream's official .deb/.rpm (it is in no distro's repos) and wired into ~/.bashrc and ~/.zshrc. Its AI module, which would send failed commands to the author's API server, is disabled by default."
UTILITY_DESCRIPTION["Podman"]="Daemonless container engine compatible with Docker CLI for building and running OCI containers without root."
UTILITY_DESCRIPTION["Postman"]="API development and testing platform for designing, debugging, and collaborating on APIs."
UTILITY_DESCRIPTION["PowerShell"]="Microsoft's cross-platform task automation shell and scripting language built on .NET. Provides powerful object-based pipelines, remote management via WinRM/SSH, and broad compatibility with Windows PowerShell scripts. Installed via the official Microsoft apt repository where available, otherwise via the GitHub release .deb."
UTILITY_DESCRIPTION["pyenv"]="Python version manager for installing and switching between multiple Python versions per-project."
UTILITY_DESCRIPTION["Rustup"]="Official Rust toolchain installer and version manager for the Rust programming language."
UTILITY_DESCRIPTION["Terraform"]="HashiCorp's infrastructure-as-code tool for provisioning and managing cloud resources with declarative HCL configs."
UTILITY_DESCRIPTION["Virt-Manager"]="Graphical desktop tool for managing KVM/QEMU virtual machines with full libvirt integration."
UTILITY_DESCRIPTION["Visual Studio Code"]="Microsoft's extensible code editor with a rich ecosystem of extensions and built-in Git support."

# Gaming
UTILITY_DESCRIPTION["Bottles"]="Wine prefix manager for running Windows software on Linux with per-app isolation. Requires Flatpak — run 'Flatpak Setup' from the Package Managers category first on non-Arch systems."
UTILITY_DESCRIPTION["Boxflat"]="Settings manager for Moza Racing sim-racing hardware (wheelbase, wheel, pedals, shifter) on Linux. Installed via Flatpak from Flathub by default; on Arch it falls back to the boxflat-git AUR package when Flatpak is unavailable."
UTILITY_DESCRIPTION["Feral Gamemode"]="Optimizes Linux system performance while gaming by adjusting CPU governor, I/O priority, and more. For Steam games add the launch option: gamemoderun %command%"
UTILITY_DESCRIPTION["Heroic Games Launcher"]="Open-source launcher for Epic Games Store, GOG, and Amazon Prime Gaming libraries."
UTILITY_DESCRIPTION["Lutris"]="Open gaming platform for managing and running games from multiple sources including Steam, GOG, and more."
UTILITY_DESCRIPTION["MangoHud"]="Vulkan and OpenGL overlay for monitoring FPS, frame times, CPU/GPU usage, and temperatures in-game."
UTILITY_DESCRIPTION["ProtonUp-Qt"]="Graphical tool for managing Proton-GE and Wine-GE compatibility layers for Steam and Lutris. Requires Flatpak — run 'Flatpak Setup' from the Package Managers category first on non-Arch systems."
UTILITY_DESCRIPTION["Steam App"]="Valve's gaming platform for purchasing, downloading, and playing PC games on Linux."
UTILITY_DESCRIPTION["Wine"]="Compatibility layer that enables Windows applications and games to run natively on Linux without a virtual machine."

# Internet
UTILITY_DESCRIPTION["Bitwarden Extension"]="Deploys Bitwarden browser extension via policy files for all detected browsers (Brave, Chrome, Chromium, Firefox, LibreWolf, Thorium, Vivaldi). The extension is force-installed on next browser launch."
UTILITY_DESCRIPTION["Brave Browser"]="Privacy-focused web browser with built-in ad and tracker blocking based on Chromium."
UTILITY_DESCRIPTION["Brave Debloat"]="Disables Brave Browser annoyances via enterprise policy: Rewards, Crypto Wallet, VPN, Leo AI, News, Talk, and Tor. Also disables telemetry (P3A, stats ping, metrics reporting, Safe Browsing extended reporting, and URL-keyed data collection)."
UTILITY_DESCRIPTION["Brave Origin"]="Streamlined build of the Brave browser that ships without Rewards, Wallet, VPN, Leo AI, News, and other add-ons. Installed as a separate 'brave-origin' package alongside (not replacing) regular Brave Browser."
UTILITY_DESCRIPTION["Betterbird"]="Thunderbird fork carrying bug fixes and features upstream has not merged. Installed from Flathub, or the AUR on Arch, since no distro packages it. Shares the ~/.thunderbird profile directory with Thunderbird."
UTILITY_DESCRIPTION["Chromium"]="Open-source web browser that serves as the upstream base for Google Chrome."
UTILITY_DESCRIPTION["Claws Mail"]="Fast, lightweight GTK email client with extensive filtering and a plugin system. A good fit for XFCE and other resource-conscious desktops."
UTILITY_DESCRIPTION["Euro-Office"]="Office suite (documents, spreadsheets, presentations, PDF and forms) — a European community fork of ONLYOFFICE, AGPL v3. BUILT FROM SOURCE: upstream publishes no desktop binaries at all — no releases, no Flathub or Snap, no apt/rpm repository — so this task runs their own containerised build ('docker buildx bake') and installs the .deb/.rpm it produces. Arch goes through the AUR package, which drives the same build and leaves pacman tracking the result. Docker with the Buildx plugin is required, the compile takes hours, and it needs tens of GB of disk; it always confirms before starting, and never builds unattended unless EUROOFFICE_BUILD=yes. Builds the newest release tag by default — set EUROOFFICE_REF to build a branch or another tag. Sources are kept in ~/.cache/linux_util/euro-office so later updates rebuild incrementally, and an update only recompiles when a newer release exists. Uninstall removes the package, that cache, and the build cache volume."
UTILITY_DESCRIPTION["Evolution"]="GNOME's personal information manager combining email, calendar, contacts, and tasks. Installs evolution-ews alongside it for Microsoft Exchange account support where the package is available."
UTILITY_DESCRIPTION["Devolutions RDM"]="Remote Desktop Manager for centrally managing remote connections, passwords, and credentials."
UTILITY_DESCRIPTION["Discord"]="Voice, video, and text communication platform popular with gaming and developer communities."
UTILITY_DESCRIPTION["FileZilla"]="Cross-platform FTP, FTPS, and SFTP client for fast and reliable file transfers."
UTILITY_DESCRIPTION["Firefox"]="Open-source web browser by Mozilla with strong privacy features and extension support."
UTILITY_DESCRIPTION["Geary"]="Lightweight GNOME email client with conversation threading and a minimal interface."
UTILITY_DESCRIPTION["Google Chrome"]="Google's web browser with extensive extension ecosystem, sync, and developer tools."
UTILITY_DESCRIPTION["KMail"]="KDE's feature-rich email client with PGP encryption, multiple account support, and filters."
UTILITY_DESCRIPTION["NeoMutt"]="Terminal email client, a maintained fork of Mutt with sidebar, notmuch, and NNTP support. Ships no default account config — you write ~/.config/neomutt/neomuttrc yourself."
UTILITY_DESCRIPTION["OpenSSH Server"]="Secure Shell server enabling encrypted remote terminal access to this machine."
UTILITY_DESCRIPTION["Proton Mail Bridge"]="Local IMAP/SMTP gateway that decrypts Proton Mail so any desktop client can use it. Requires a paid Proton plan and a running keyring. Installed from Flathub, as Proton publishes no tracking repo."
UTILITY_DESCRIPTION["PIA VPN"]="Private Internet Access VPN client for encrypted and anonymous internet browsing."
UTILITY_DESCRIPTION["ProtonVPN"]="Free and open-source VPN service by Proton for secure and private browsing."
UTILITY_DESCRIPTION["QBittorrent"]="Open-source BitTorrent client with a clean interface and no ads."
UTILITY_DESCRIPTION["Remmina"]="Remote desktop client supporting RDP, VNC, SSH, SPICE, and other protocols."
UTILITY_DESCRIPTION["Signal Desktop"]="End-to-end encrypted messaging application focused on privacy and security."
UTILITY_DESCRIPTION["SponsorBlock Extension"]="Deploys SponsorBlock browser extension via policy files for all detected browsers (Brave, Chrome, Chromium, Firefox, LibreWolf, Thorium, Vivaldi). Automatically skips YouTube sponsors, intros, outros, and other unwanted segments using a crowdsourced database."
UTILITY_DESCRIPTION["Syncthing"]="Continuous peer-to-peer file synchronization between your devices without a central server."
UTILITY_DESCRIPTION["Tailscale"]="Zero-config mesh VPN built on WireGuard for secure networking between your devices."
UTILITY_DESCRIPTION["Telegram Desktop"]="Cloud-based messaging app with fast delivery, group chats, channels, and file sharing."
UTILITY_DESCRIPTION["Termius SSH Client"]="Modern SSH client with sync across devices, SFTP, and snippet management."
UTILITY_DESCRIPTION["Thorium Browser"]="Chromium-based browser optimized for speed and performance with compiler optimizations."
UTILITY_DESCRIPTION["Thunderbird"]="Open-source email client by Mozilla with calendar integration and PGP support."
UTILITY_DESCRIPTION["Trojita"]="Trojitá — fast, Qt-native IMAP client and a lighter alternative to KMail on KDE. Fedora, Arch (AUR) and openSUSE only: Debian dropped the package and it was never in EPEL. Upstream is quiet; 0.7 dates from 2016."
UTILITY_DESCRIPTION["Vivaldi Browser"]="Highly customizable Chromium-based browser with advanced tab management and built-in tools."
UTILITY_DESCRIPTION["Zen Browser"]="Privacy-focused Firefox-based browser with vertical tabs, split view, and workspaces. Still in beta. Installs the official tarball to ~/.local/share/zen-browser, falling back to Flatpak if the tarball cannot be installed."
UTILITY_DESCRIPTION["WireGuard Client"]="Modern, fast, and lightweight VPN client using the WireGuard protocol."
UTILITY_DESCRIPTION["Angry IP Scanner"]="Fast and friendly network scanner that pings IP ranges, resolves hostnames, scans ports, and exports results to CSV, TXT, or XML. Requires Java."
UTILITY_DESCRIPTION["AnyDesk"]="Fast remote desktop application with low latency for support and remote access across platforms."
UTILITY_DESCRIPTION["Element (Matrix)"]="Open-source Matrix client for decentralized, end-to-end encrypted messaging and collaboration."
UTILITY_DESCRIPTION["LocalSend"]="Open-source AirDrop alternative — sends files and text between devices on the same network, with no internet connection, account, or cloud service. Uses port 53317; the installer offers to open it if a firewall is active. Installed from the official .deb on Debian/Ubuntu and from Flathub elsewhere (upstream publishes no .rpm)."
UTILITY_DESCRIPTION["LibreWolf"]="Privacy-hardened Firefox fork with tracking protection, telemetry removed, and strong security defaults."
UTILITY_DESCRIPTION["RustDesk"]="Open-source remote desktop application — self-hostable alternative to AnyDesk and TeamViewer."
UTILITY_DESCRIPTION["Slack"]="Team messaging and collaboration platform with channels, threads, integrations, and file sharing."
UTILITY_DESCRIPTION["Tor Browser"]="Privacy browser bundled with the Tor network for anonymous, censorship-resistant browsing."
UTILITY_DESCRIPTION["UniFi Endpoint"]="Ubiquiti's UniFi Identity VPN client for secure access to UniFi-managed networks — VPN connectivity, WiFi authentication, and credential management."
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
UTILITY_DESCRIPTION["Libation"]="Open-source Audible audiobook manager for downloading, decrypting, and organizing your audiobook library."
UTILITY_DESCRIPTION["Logseq"]="Open-source knowledge management and note-taking app based on linked, Markdown-formatted outliner blocks."
UTILITY_DESCRIPTION["Mark Text"]="Simple, elegant Markdown editor focused on writing speed with live preview and multiple themes."
UTILITY_DESCRIPTION["VLC"]="Versatile open-source media player supporting virtually every audio and video format without additional codecs."
UTILITY_DESCRIPTION["Zotero"]="Free reference manager for collecting, organizing, annotating, and citing research sources."
UTILITY_DESCRIPTION["Joplin Client"]="Open-source note-taking and to-do application with Markdown support and sync."
UTILITY_DESCRIPTION["Joplin Web Clipper"]="Deploys Joplin Web Clipper browser extension via policy files for all detected browsers (Brave, Chrome, Chromium, Firefox, LibreWolf, Thorium, Vivaldi). Captures web pages and screenshots directly into Joplin — requires the Joplin desktop app running with Web Clipper service enabled."
UTILITY_DESCRIPTION["LibreOffice"]="Full-featured open-source office suite compatible with Microsoft Office formats."
UTILITY_DESCRIPTION["Nextcloud Desktop"]="Desktop sync client for Nextcloud, providing self-hosted cloud file storage and sharing."
UTILITY_DESCRIPTION["OBS Studio"]="Open-source software for video recording and live streaming with scene composition."
UTILITY_DESCRIPTION["OCCT"]="Stability and stress-testing suite for CPU, RAM, GPU, and PSU, with live hardware monitoring — widely used to validate overclocks and diagnose unstable hardware. Installs the free Personal edition as a self-contained x86_64 binary from ocbase.com (no upstream repo or checksum). Installed per-user under ~/.local/share/occt, since OCCT stores its imported license alongside its own executable and must be able to write there. Launch from the application menu or run 'occt'."
UTILITY_DESCRIPTION["Obsidian"]="Markdown-based knowledge base and note-taking app with linking, graphs, and plugins."
UTILITY_DESCRIPTION["OnlyOffice"]="Office suite with strong Microsoft Office format compatibility and real-time collaboration."
UTILITY_DESCRIPTION["Standard Notes"]="End-to-end encrypted note-taking app with cross-platform sync and extensible editors."
UTILITY_DESCRIPTION["WPS Office"]="Microsoft Office-compatible office suite with a familiar interface and polished formatting."
UTILITY_DESCRIPTION["WinApps"]="Runs Windows applications (Office, Adobe, and anything else installed in Windows) as individual windows on the Linux desktop, via a Windows VM and FreeRDP RemoteApp. Installs the prerequisites — FreeRDP 3, dialog, netcat, libnotify — clones the source to ~/.local/bin/winapps-src, links 'winapps-setup', and writes a 0600 config template to ~/.config/winapps/winapps.conf. Then offers to create the Windows VM for you from upstream's compose file via Docker or Podman (Windows 11 Pro, 4 GB RAM, 4 cores, 64 GB disk, ~8 GB download; you can edit the compose file first, and declining is safe). Requires KVM. Finish by running 'winapps-setup --user' once Windows has booted. Windows itself is licensed separately — it installs and runs unactivated, activation needs your own Retail/Volume key, and RemoteApp needs Pro or better, not Home. Uninstall never deletes the VM or its disk. Upstream publishes no releases, so the version shown is the commit date and hash."

# System Tools
UTILITY_DESCRIPTION["Mainline"]="Ubuntu mainline-kernel installer (the cappelikan/bkw777 fork of ukuu) — a GTK GUI (mainline-gtk) plus 'mainline' CLI that downloads, installs, lists, and removes mainline kernels from kernel.ubuntu.com. Debian/Ubuntu family only: installed from ppa:cappelikan/ppa where add-apt-repository is available, otherwise from the latest upstream .deb. Warns and stops on Arch/Fedora/openSUSE."
UTILITY_DESCRIPTION["CachyOS Kernel Manager"]="GUI to install, build, swap, and remove kernels on Arch-family systems (a pacman front-end that also configures sched-ext schedulers). The package ships only in the CachyOS repository — not the AUR — so it installs out of the box on CachyOS or any Arch system with the CachyOS repo enabled. This task does not add the CachyOS repo for you; if the package is not in a configured repo it warns and links the setup guide. Arch family only."
UTILITY_DESCRIPTION["Fedora Mainline Kernel"]="Enables the community @kernel-vanilla/mainline Copr and installs the latest upstream (vanilla) mainline kernel on Fedora — the standard way to test an upstream kernel there, since Fedora has no dedicated GUI manager. Fedora only. Mainline kernels are unsigned, so Secure Boot must be disabled to boot them; the stock Fedora kernel is kept as a fallback."
UTILITY_DESCRIPTION["linux-tkg"]="Frogging-Family custom-kernel builder. Unlike the other kernel managers it BUILDS a kernel from source — you pick the CPU scheduler (BORE, EEVDF, PDS, …), compiler, and config. Cross-distro: makepkg on Arch, or ./install.sh on Debian/Ubuntu, Fedora, and openSUSE (it produces and installs a .deb/.rpm). The build is interactive and can take 20-60+ minutes; kernels carry 'tkg' in the name and are removed manually (./install.sh uninstall-help). Build deps are installed automatically where possible."
UTILITY_DESCRIPTION["Btop"]="Modern terminal-based resource monitor with a rich visual interface showing CPU, memory, disk, and network."
UTILITY_DESCRIPTION["Filelight"]="KDE disk usage analyzer that visualizes storage consumption as an interactive radial map, making it easy to identify large files and directories."
UTILITY_DESCRIPTION["ClamAV"]="Open-source antivirus engine for detecting trojans, viruses, malware, and other malicious threats."
UTILITY_DESCRIPTION["Input Leap"]="Open-source KVM software that shares one keyboard and mouse across multiple computers on your local network."
UTILITY_DESCRIPTION["Ventoy"]="Bootable USB solution for loading multiple ISO images from a single drive — just copy ISOs and boot."
UTILITY_DESCRIPTION["GParted"]="Graphical partition editor for creating, resizing, moving, copying, and deleting disk partitions. Supports ext2/3/4, btrfs, xfs, ntfs, fat32, and more — ideal for managing drives and preparing disks."
UTILITY_DESCRIPTION["Fastfetch"]="Lightning-fast system information tool written in C, displaying OS, hardware, and software details."
UTILITY_DESCRIPTION["Stacer"]="Linux system optimizer and monitoring tool with a graphical interface for managing services and resources."
UTILITY_DESCRIPTION["Timeshift"]="System restore utility that creates incremental filesystem snapshots using rsync or BTRFS. Install this first to enable Create, Restore, and Delete Snapshot."
UTILITY_DESCRIPTION["Déjà Dup"]="(GNOME) Simple, beginner-friendly backup tool for backing up files and folders to local drives, network shares, or cloud storage. Uses duplicity under the hood for encrypted, incremental backups."
UTILITY_DESCRIPTION["Kup"]="(KDE) Backup tool that integrates with Plasma System Settings. Supports incremental versioned backups (via bup) and synchronized folder copies (via rsync) to local drives or external media. On Fedora, installed from the zawertun/kde-kup Copr as it is not in the official repos. Not available for RHEL-based systems."
UTILITY_DESCRIPTION["Vorta"]="GUI frontend for BorgBackup — a fast, deduplicating backup tool with encryption and compression. Installs both Borg (CLI) and Vorta (GUI). On RHEL-based systems, only BorgBackup is installed via EPEL as Vorta is not packaged there."
UTILITY_DESCRIPTION["Duplicati"]="Cloud backup tool with a web-based GUI supporting S3, Google Drive, OneDrive, SFTP, and many more backends. Features encryption, deduplication, and scheduling. Installed via Flatpak — run 'Flatpak Setup' from the Package Managers category first if not already configured."
UTILITY_DESCRIPTION["Snapper"]="Btrfs and LVM snapshot manager. Supports automatic pre/post snapshots on Arch, openSUSE, Debian/Ubuntu, and Fedora. Conflicts with Timeshift — the installer will prompt to remove it first."
UTILITY_DESCRIPTION["Snapper GUI"]="GTK graphical interface for Snapper. Browse, create, delete, and compare snapshots visually. Works on any filesystem Snapper supports — does not require Btrfs."
UTILITY_DESCRIPTION["Btrfs Assistant"]="Qt GUI for managing Btrfs filesystems and Snapper snapshots. Includes subvolume management, snapshot browsing, and scrub/balance operations. Available on Arch, Debian/Ubuntu, Fedora, and openSUSE."
UTILITY_DESCRIPTION["btrfsmaintenance"]="Automates routine Btrfs maintenance tasks — scrub, balance, trim, and defrag — on a configurable schedule via systemd timers or cron. Edit /etc/btrfsmaintenance/btrfsmaintenance.conf to tune intervals and mountpoints."
UTILITY_DESCRIPTION["btrbk"]="Powerful Btrfs snapshot and backup tool. Creates snapshots locally and sends them to remote hosts via SSH using btrfs send/receive. Supports flexible retention policies and incremental transfers. Configure via /etc/btrbk/btrbk.conf."
UTILITY_DESCRIPTION["duperemove"]="Extent-based deduplication tool for Btrfs (and other filesystems). Scans for duplicate data blocks and replaces them with shared extents to reclaim disk space. Best run periodically on data-heavy volumes."
UTILITY_DESCRIPTION["Create Snapshot (Snapper)"]="Create a manual Snapper snapshot of the root filesystem with an optional description."
UTILITY_DESCRIPTION["Restore Snapshot (Snapper)"]="Roll back the system to a previous Snapper snapshot."
UTILITY_DESCRIPTION["Delete Snapshot (Snapper)"]="Permanently delete one or more Snapper snapshots to free disk space."
UTILITY_DESCRIPTION["Zsh + Oh My Zsh"]="Installs the Z shell with Oh My Zsh framework, zsh-autosuggestions, and zsh-syntax-highlighting plugins. During install you can choose from Powerlevel10k (pre-configured or interactive wizard) or one of 10 popular built-in themes. Theme can also be changed later via the update option."

# File Managers
UTILITY_DESCRIPTION["Nautilus"]="GNOME's default file manager (also known as 'Files'). Clean, simple GTK interface with sidebar navigation and built-in network browsing. Pulls in GNOME/GTK libraries; works on any desktop but feels most at home on GNOME."
UTILITY_DESCRIPTION["Dolphin"]="KDE Plasma's default file manager. Powerful Qt-based interface with split views, tabs, embedded terminal, and deep integration with KIO protocols (sftp://, fish://, smb://, trash://). Pulls in KDE Frameworks; works on any desktop but feels most at home on KDE Plasma."
UTILITY_DESCRIPTION["Thunar"]="Xfce's default file manager. Fast, lightweight GTK file manager with bulk rename, custom actions, and volume management. Excellent on low-resource systems; works on any desktop."
UTILITY_DESCRIPTION["Nemo"]="Cinnamon's default file manager — a Nautilus fork that retains classic features like dual-pane view, type-ahead search, and an editable address bar. Pulls in some Cinnamon libraries; works on any desktop but is the natural choice on Cinnamon."
UTILITY_DESCRIPTION["Caja"]="MATE's default file manager — a GNOME 2-era Nautilus fork with a traditional layout, dual-pane view, and extensible plugin system. Pulls in MATE libraries; works on any desktop but is the natural choice on MATE."
UTILITY_DESCRIPTION["PCManFM-Qt"]="LXQt's default file manager. Extremely lightweight Qt-based file manager with tabs, dual panes, and trash support. Pulls in LXQt/Qt libraries; works on any desktop but is the natural choice on LXQt. Not packaged for RHEL-based distros."
UTILITY_DESCRIPTION["Krusader"]="Advanced twin-panel (orthodox) file manager for KDE, inspired by Total Commander. Supports archive handling, batch rename, file comparison, and synchronization. Pulls in KDE Frameworks; works on any desktop."
UTILITY_DESCRIPTION["Midnight Commander"]="Classic text-mode twin-panel file manager (mc) with menu-driven navigation, built-in editor (mcedit), archive browsing, and FTP/SFTP support. Runs in any terminal — no desktop environment required."
UTILITY_DESCRIPTION["Ranger"]="Vim-inspired terminal file manager with a three-pane Miller column view, file previews, and heavy keyboard customization. Runs in any terminal — no desktop environment required."
UTILITY_DESCRIPTION["nnn"]="Tiny, blazing-fast terminal file manager with optional file previews, plugins, and a context-based workflow. Minimal dependencies; runs in any terminal — no desktop environment required."

# Window Managers
UTILITY_DESCRIPTION["awesome"]="Highly configurable X11 window manager with dynamic tiling and floating layouts. Configured in Lua and extensible via a rich widget library. Suits users who want a tiling WM that doubles as a programmable framework."
UTILITY_DESCRIPTION["bspwm"]="Lightweight X11 tiling window manager that arranges windows as leaves of a binary tree. Controlled entirely via messages from the bspc CLI and paired with sxhkd for keybindings (installed automatically). Highly scriptable."
UTILITY_DESCRIPTION["dwm"]="Suckless dynamic X11 window manager — minimal, fast, and under 2000 lines of C. The packaged binary ships upstream defaults; meaningful customization requires editing config.h and recompiling."
UTILITY_DESCRIPTION["Hyprland"]="Modern, animated Wayland tiling compositor with smooth visuals, dynamic tiling, and rich theming. Available on Arch, Fedora, openSUSE Tumbleweed, and Ubuntu 24.04+. Not packaged for RHEL or Debian stable."
UTILITY_DESCRIPTION["i3"]="Classic X11 tiling window manager with simple text-based configuration, fast performance, and a large ecosystem of status bars, launchers, and themes. The go-to choice for tiling on X11."
UTILITY_DESCRIPTION["Openbox"]="Minimal, fast X11 stacking window manager with a clean right-click menu and XML configuration. Ideal for building lightweight custom desktops or running on low-resource hardware."
UTILITY_DESCRIPTION["Sway"]="Wayland tiling compositor that is a drop-in replacement for i3 — reads i3 config files and behaves the same way. The most popular tiling option for Wayland users coming from i3."

# Login Screens (display managers + login themes)
UTILITY_DESCRIPTION["SDDM"]="Simple Desktop Display Manager — the Qt-based login screen used by KDE Plasma and LXQt, with full theming support. Installs SDDM and, if no login screen is active, enables it (otherwise asks before replacing the current one). Pair with an SDDM theme below. Does not start immediately — reboot to use it."
UTILITY_DESCRIPTION["GDM"]="GNOME Display Manager — the GTK login screen used by GNOME (package 'gdm3' on Debian/Ubuntu, 'gdm' elsewhere). Installs GDM and enables it when no login screen is active, or asks before replacing the current one. GDM theming is intentionally not offered (it requires recompiling gresource bundles). Reboot to use it."
UTILITY_DESCRIPTION["LightDM"]="Lightweight, cross-desktop display manager used by Xfce, MATE, Cinnamon, and Budgie. Installs LightDM plus a GTK greeter so a login form renders, and enables it when no login screen is active (otherwise asks first). Themeable via the Slick greeter below. Reboot to use it."
UTILITY_DESCRIPTION["ly"]="Minimal TUI (text-mode) display manager that runs on the console — no X/Wayland greeter needed. Ideal for window-manager users who want a tiny login screen. Packaged on Arch and openSUSE; the install fails cleanly where it is not available. Reboot to use it."
UTILITY_DESCRIPTION["LXDM"]="Lightweight GTK display manager from the LXDE project. A small, fast login screen suited to low-resource systems and minimal desktops. Installs LXDM and enables it when no login screen is active, or asks before replacing the current one. Reboot to use it."
UTILITY_DESCRIPTION["SDDM Breeze Theme"]="Sets the upstream KDE Breeze theme as the SDDM login screen via an /etc/sddm.conf.d drop-in (overrides distro defaults such as the Kubuntu theme). Breeze ships with KDE Plasma; on Debian/Ubuntu the standalone sddm-theme-breeze package is pulled in if needed. Requires SDDM."
UTILITY_DESCRIPTION["SDDM Sugar Candy"]="Popular, highly configurable QtQuick SDDM theme with a clean blurred-background login. Downloaded from GitHub into /usr/share/sddm/themes and set as the active SDDM theme; pulls in the QtQuick runtime it needs. Requires SDDM and an internet connection."
UTILITY_DESCRIPTION["SDDM Astronaut"]="Modern QtQuick SDDM theme bundle (multiple sci-fi styles) downloaded from GitHub into /usr/share/sddm/themes and set as the active SDDM theme; pulls in the QtQuick runtime it needs. Requires SDDM and an internet connection."
UTILITY_DESCRIPTION["LightDM Slick Greeter"]="Installs the Slick greeter (the themeable GTK greeter used by Linux Mint) and selects it for LightDM via an /etc/lightdm/lightdm.conf.d drop-in. Customise background, GTK theme, and icons in /etc/lightdm/slick-greeter.conf. Requires LightDM; not packaged on every distro."

# Package Managers (additional / third-party — these run alongside your native
# package manager, which is never replaced or removed)
UTILITY_DESCRIPTION["Homebrew"]="Cross-distro package manager (Linuxbrew) that installs into your home directory and runs entirely in user space. Great for getting newer CLI tool versions without root or touching system packages. Installs as a normal user; cannot be installed as root."
UTILITY_DESCRIPTION["Nix"]="Powerful cross-distro, purely-functional package manager with reproducible, isolated, and rollback-able installs. Works alongside the native package manager. Installed via the Determinate Systems installer for a clean, non-interactive setup and tidy uninstall."
UTILITY_DESCRIPTION["Snap (snapd)"]="Canonical's cross-distro package manager for sandboxed, self-contained 'snap' apps. Native on Debian/Ubuntu and Fedora, via EPEL on RHEL, the system:snappy repo on openSUSE, and the AUR on Arch. Enables the snapd socket and sets up the /snap path automatically."
UTILITY_DESCRIPTION["deb-get"]="apt-get-style management of .deb packages from third-party repositories and direct downloads (Chrome, VS Code, Discord, etc.) that aren't in the official repos. Debian/Ubuntu family only; installed apps stay tracked by dpkg/apt."
UTILITY_DESCRIPTION["Pacstall"]="The 'AUR for Ubuntu/Debian' — installs software from community build scripts (pacscripts) that fetch or compile upstream packages not available in apt. Debian/Ubuntu family only. Community-maintained, so review scripts before installing."
UTILITY_DESCRIPTION["yay"]="Popular AUR helper for Arch-family distros, written in Go. Wraps pacman to search, build, and install packages from the Arch User Repository. Arch family only; installed from the repo on Manjaro/EndeavourOS or built from the AUR otherwise."
UTILITY_DESCRIPTION["paru"]="Feature-rich AUR helper for Arch-family distros, written in Rust — an alternative to yay with the same pacman-style workflow. Arch family only; installed from the repo where available or built from the AUR."

# --- AUR-only utilities (Arch) ---
# These have no official-repo or Flatpak fallback in their installer — on
# upstream Arch the AUR is their only install path. Hidden from the install
# listing while AUR_ENABLED=false and not already installed (see
# _utility_hidden_aur_only in lib/utilities.sh); uninstalling an existing
# install is never affected.
#
# Each entry carries its Arch package name. Derivatives ship many of these in
# their own repos — CachyOS has brave-bin, google-chrome and others — and an
# entry stays visible, installing with plain pacman, wherever the configured
# repos carry the package. Keep the package name in sync with the repo_or_aur
# call in the matching lib/installers/*.sh file.
# AnyDesk, Boxflat, Google Chrome and Visual Studio Code are NOT listed: each
# now has a Flathub tier ahead of the AUR. PowerShell and Libation are not
# listed either -- both install from upstream's own binaries. See
# arch_install_ordered in lib/aur.sh for the tier order.
mark_aur_only_arch \
    "Brave Browser=brave-bin" "Brave Origin=brave-origin-bin" \
    "Devolutions RDM=remote-desktop-manager" \
    "Euro-Office=euro-office-desktopeditors-git" \
    "Snap (snapd)=snapd" "Snapper GUI=snapper-gui-git" \
    "Trojita=trojita" "Zotero=zotero"
