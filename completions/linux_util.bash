# bash completion for linux_util.sh
# Install: source this file or copy it to /etc/bash_completion.d/linux_util

_linux_util_utilities() {
    cat <<'EOF'
AMD Drivers
Betterbird
Bitwarden Client
Bitwarden Extension
Bottles
Boxflat
Brave Browser
Btop
Budgie Desktop
CachyOS Kernel Manager
Chromium
Cinnamon Desktop
Claude Code
Claws Mail
Cockpit
Command-Not-Found Prompt
COSMIC Desktop
Create Snapshot
Cursor IDE
DBeaver
Deepin Desktop
Devolutions RDM
Discord
Docker
Enable RDP
Euro-Office
Evolution
Fastfetch
Fedora Mainline Kernel
Feral Gamemode
FileZilla
Firefox
Flatpak Setup
Full System Upgrade/Update
Geary
GIMP
GitHub CLI
GNOME Desktop
Google Chrome
Heroic Games Launcher
JetBrains Toolbox
Joplin Client
Joplin Web Clipper
KDE Desktop
KMail
LibreOffice
linux-tkg
Local Time Zone / Locale
LocalSend
Lutris
LXQt Desktop
Mainline
MangoHud
MATE Desktop
NeoMutt
Nextcloud Desktop
NVIDIA Drivers
NVM
OBS Studio
Obsidian
OnlyOffice
OpenLogi
OpenSSH Server
tmux
tmux Resurrect
Pantheon Desktop
Pay Respects
PIA VPN
Postman
Proton Mail Bridge
ProtonUp-Qt
ProtonVPN
QBittorrent
Remmina
Restore Snapshot
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
Trojita
Num Lock at Boot
UFW Firewall
Visual Studio Code
VSCodium
Vivaldi Browser
WinApps
Wine
WireGuard Client
WireGuard Server
WPS Office
XEN Guest Utilities
Xfce Desktop
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
