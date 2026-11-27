# bash completion for linux_util.sh
# Install: source this file or copy it to /etc/bash_completion.d/linux_util

_linux_util_utilities() {
    cat <<'EOF'
1Password
Alacritty
AMD CPU Microcode & Firmware
AMD Drivers
Angry IP Scanner
Anki
Ansible
AnyDesk
ArtCraft Launcher
Audacity
auto-cpufreq
awesome
Back In Time
bat
Betterbird
Bitwarden Client
Bitwarden Extension
BleachBit
Blender
Bottles
BoxBuddy
Boxflat
Brave Browser
Brave Debloat
Brave Origin
bspwm
Btop
btrbk
Btrfs Assistant
btrfsmaintenance
Budgie Desktop
CachyOS Kernel Manager
Caja
Calibre
Catppuccin GRUB Theme
Chromium
Cinnamon Desktop
ClamAV
Claude Code
Claude Desktop
Claws Mail
Clonezilla
Cockpit
Codex
Command-Not-Found Prompt
Configure Bootloader
Configure Syncthing Folders
Configure Unattended Upgrades
COSMIC Desktop
CPU-X
Create Snapshot
Create Snapshot (Snapper)
Cryptomator
CUPS
Cursor IDE
Darktable
DBeaver
deb-get
Deepin Desktop
Delete Default Cloud-Init User
Delete Snapshot
Delete Snapshot (Snapper)
Devolutions RDM
Discord
Distro GRUB Themes
Distrobox
DistroShelf
Docker
Dolphin
Dolphin Emulator
duperemove
Duplicati
dwm
Déjà Dup
earlyoom
Element (Matrix)
Emacs
Enable RDP
Euro-Office
Evolution
eza
Fastfetch
Fedora Mainline Kernel
Feral Gamemode
Filelight
FileZilla
Firecracker
Firefox
firewall-config (GUI)
firewalld
Fix Broken Packages
Fix Grub on BTRFS
Fix Monitor Layout at Login
Fix Package Repos
Fix RDP Kerberos Delay
Flameshot
Flatpak Setup
Flatseal
Full System Upgrade
fzf
GDM
Gear Lever
Geary
Ghostty
GIMP
GitHub CLI
GNOME Desktop
Go SDK
Google Chrome
GParted
GPU Task Manager
Grsync
GRUB
GRUB Theme Selector
GTK Window Fix
Gufw (Firewall GUI)
HandBrake
HardInfo
Helix
Helm
Hermes Agent
Heroic Games Launcher
Homebrew
htop
HyperFluent GRUB Theme
Hyprland
i3
Inkscape
Input Leap
Install fail2ban
Intel CPU Microcode & Thermal
Intel Drivers
inxi
Java JDK
JetBrains Toolbox
Joplin Client
Joplin Web Clipper
k3s
k9s
KDE Desktop
Kdenlive
KDiskMark
KeePassXC
kitty
KMail
Kodi
Konsole
Kontainer
Kopia
krdpc
Krita
Krusader
kubectl
Kup
Kwi
LACT
lazygit
Libation
LibreOffice
LibreWolf
LightDM
LightDM Slick Greeter
Limine
linux-tkg
LM Studio
Local Time Zone / Locale
LocalSend
Logseq
luckyBackup
Lutris
LXDM
LXQt Desktop
ly
Mainline
Manage Share
MangoHud
Mark Text
MATE Desktop
Mattermost
Microsoft Teams
Midnight Commander
minikube
Moonlight
Mount Local Drive
Mount NFS Share
Mount SMB Share
mpv
Mullvad VPN
Multimedia Codecs
Nautilus
ncdu
Nemo
NeoMutt
Neovim
Nextcloud Desktop
Nix
nmap
nnn
Node.js
NordVPN
Num Lock at Boot
NVIDIA Drivers
NVIDIA PAIR
NVM
nvtop
OBS Studio
Obsidian
OCCT
Okular
Ollama
OnlyOffice
Openbox
OpenLogi
OpenRSAT
OpenSSH Server
OpenTofu
OpenVPN
Opera
Pacstall
Pantheon Desktop
Parallel Downloads
paru
Pay Respects
PCManFM-Qt
PHP
PIA VPN
Pika Backup
Podman
Podman Desktop
Postman
PowerShell
PPSSPP
Prism Launcher
Proton Mail Bridge
ProtonUp-Qt
ProtonVPN
Ptyxis
pyenv
Python
QBittorrent
Ranger
RawTherapee
rclone
Remmina
Reset Repos to Default
restic
Restore Snapshot
Restore Snapshot (Snapper)
RetroArch
ripgrep
rsnapshot
Ruby
RustDesk
Rustup
Scribus
SDDM
SDDM Astronaut
SDDM Breeze Theme
SDDM Sugar Candy
Shotcut
Signal Desktop
Slack
smartmontools
Snap (snapd)
Snapper
Snapper GUI
SponsorBlock Extension
Spotify
Stacer
Standard Notes
starship
Steam App
Sublime Text
Sunshine
Superfile
Sway
Switch Bootloader
Syncthing
System Updates
systemd-boot
Tailscale
Telegram Desktop
Terminator
Termius SSH Client
Terraform
Thermalright TRCC
Thorium Browser
Thunar
Thunderbird
Timeshift
tldr
TLP
TMOG
tmux
tmux Resurrect
Toolbx
Tor Browser
Trojita
UFW Firewall
Unattended Upgrades
UniFi Endpoint
Ventoy
VeraCrypt
Vim
vinceliuice GRUB Themes
Virt-Manager
VirtualBox
Visual Studio Code
Vivaldi Browser
VLC
Vorta
VSCodium
WezTerm
WhatsApp
WinApps
Wine
WireGuard Client
WireGuard Server
Wireshark
WPS Office
XEN Guest Utilities
Xfce Desktop
Xfce Terminal
Xodus Nexus
Xournal++
Yakuake
yay
Zed
Zen Browser
Zoom
Zotero
zoxide
zram
Zsh + Oh My Zsh
EOF
}

# Profile labels, as registered in lib/profiles.sh (a test keeps this in step).
_linux_util_profiles() {
    cat <<'EOF'
Default VM Server Profile
Default Physical PC
Developer Workstation
Home Desktop
EOF
}

_linux_util() {
    local cur prev words cword
    _init_completion || return

    local flags="--help -h --version --list --dry-run --verbose --debug
                 --install --uninstall --update --update-all --check
                 --no-color --json --setup-logrotate
                 --export-profile --import-profile"

    # Flags that take a utility name as next argument
    local name_flags="--install --uninstall --update --check"

    case "$prev" in
        --export-profile)
            # A profile label, or an output file (which exports every profile)
            local IFS=$'\n'
            COMPREPLY=( $(compgen -W "$(_linux_util_profiles)" -- "$cur") $(compgen -f -- "$cur") )
            local i
            for (( i=0; i<${#COMPREPLY[@]}; i++ )); do
                if [[ "${COMPREPLY[$i]}" == *' '* ]]; then
                    COMPREPLY[$i]="'${COMPREPLY[$i]}'"
                fi
            done
            return
            ;;
        --install|--uninstall|--update|--check)
            # Complete utility names; wrap multi-word names in quotes
            local utilities
            mapfile -t utilities < <(_linux_util_utilities)
            local IFS=$'\n'
            COMPREPLY=( $(compgen -W "${utilities[*]}" -- "$cur") )
            # Quote completions that contain spaces
            local i
            for (( i=0; i<${#COMPREPLY[@]}; i++ )); do
                if [[ "${COMPREPLY[$i]}" == *' '* ]]; then
                    COMPREPLY[$i]="'${COMPREPLY[$i]}'"
                fi
            done
            return
            ;;
        --import-profile)
            # Complete file paths
            COMPREPLY=( $(compgen -f -- "$cur") )
            return
            ;;
    esac

    # Default: complete flags
    COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
}

complete -F _linux_util linux_util.sh
complete -F _linux_util ./linux_util.sh
