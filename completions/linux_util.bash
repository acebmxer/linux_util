# bash completion for linux_util.sh
# Install: source this file or copy it to /etc/bash_completion.d/linux_util

_linux_util_utilities() {
    cat <<'EOF'
1Password
Alacritty
AMD Drivers
Anki
ArtCraft Launcher
auto-cpufreq
bat
Betterbird
Bitwarden Client
Bitwarden Extension
BleachBit
Blender
Bottles
Boxflat
Brave Browser
Btop
Budgie Desktop
CachyOS Kernel Manager
Calibre
Chromium
Cinnamon Desktop
Claude Code
Claude Desktop
Claws Mail
Cockpit
Codex
Command-Not-Found Prompt
COSMIC Desktop
CPU-X
Create Snapshot
Cryptomator
CUPS
Cursor IDE
Darktable
DBeaver
Deepin Desktop
Devolutions RDM
Discord
Docker
earlyoom
Emacs
Enable RDP
Euro-Office
Evolution
eza
Fastfetch
Fedora Mainline Kernel
Feral Gamemode
FileZilla
Firecracker
Firefox
Flatpak Setup
Full System Upgrade/Update
fzf
Geary
Ghostty
GIMP
GitHub CLI
GNOME Desktop
Google Chrome
GPU Task Manager
GTK Window Fix
HardInfo
Helix
Helm
Hermes Agent
Heroic Games Launcher
htop
Intel Drivers
inxi
Java JDK
JetBrains Toolbox
Joplin Client
Joplin Web Clipper
k3s
KDE Desktop
KDiskMark
KeePassXC
kitty
KMail
Kodi
lazygit
LibreOffice
linux-tkg
Local Time Zone / Locale
LM Studio
LocalSend
Lutris
LXQt Desktop
Mainline
MangoHud
MATE Desktop
minikube
mpv
Multimedia Codecs
ncdu
NeoMutt
Nextcloud Desktop
nmap
NVIDIA Drivers
NVIDIA PAIR
NVM
nvtop
OBS Studio
Obsidian
Okular
Ollama
OnlyOffice
OpenLogi
OpenSSH Server
PHP
Podman Desktop
Python
RawTherapee
Ruby
Scribus
Shotcut
smartmontools
Spotify
starship
Sublime Text
tldr
TLP
tmux
tmux Resurrect
Pantheon Desktop
Parallel Downloads
Pay Respects
PIA VPN
Postman
Proton Mail Bridge
ProtonUp-Qt
ProtonVPN
QBittorrent
Remmina
Restore Snapshot
ripgrep
Signal Desktop
SponsorBlock Extension
Stacer
Standard Notes
Steam App
Syncthing
System Updates
Tailscale
Telegram Desktop
Termius SSH Client
Thermalright TRCC
Thorium Browser
Thunderbird
Timeshift
TMOG
Toolbx
Trojita
Num Lock at Boot
UFW Firewall
VeraCrypt
Vim
VirtualBox
Visual Studio Code
VSCodium
Vivaldi Browser
WezTerm
WinApps
Wine
WireGuard Client
WireGuard Server
Wireshark
WPS Office
XEN Guest Utilities
Xfce Desktop
Xodus Nexus
Xournal++
Zed
zoxide
zram
Zsh + Oh My Zsh
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
        --install|--uninstall|--update|--check|--export-profile)
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
