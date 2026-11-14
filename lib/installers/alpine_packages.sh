#!/bin/bash
# Alpine Linux: the utilities that install from Alpine's own repositories.
#
# Alpine is not covered by the per-distro case blocks in the other installer
# files, and most utilities there are built on .deb/.rpm/glibc downloads that
# do not run on Alpine (musl). Instead of adding an alpine arm to ~100 files,
# the utilities that Alpine carries as ordinary packages are listed here once,
# and installers.sh calls apply_alpine_registry at the end of registration to:
#   - give each listed utility generic apk install/uninstall/update/check
#     handlers, and
#   - drop every registered utility that has no Alpine path, so nothing is
#     offered that would run an installer with no Alpine branch and report
#     success having done nothing.
# Utilities with their own Alpine branch in their own file are in
# _ALPINE_OWN_HANDLERS below.
#
# Do not add a second copy of this table elsewhere: new Alpine utilities go
# in _ALPINE_TABLE.

# "Registered name|apk packages|binary for the quick installed check|OpenRC services|post-install function"
# Binary, services and post-install function may be empty.
_ALPINE_TABLE=(
    "Ansible|ansible|ansible||"
    "Btop|btop|btop||"
    "bat|bat|bat||"
    "ClamAV|clamav|clamscan||"
    "Docker|docker|docker|docker|_alpine_post_docker"
    "Distrobox|distrobox|distrobox||"
    "Fastfetch|fastfetch|fastfetch||"
    "FileZilla|filezilla|filezilla||"
    "Firefox|firefox|firefox||"
    "UFW Firewall|ufw|ufw|ufw|"
    "GIMP|gimp|gimp||"
    "GitHub CLI|github-cli|gh||"
    "Go SDK|go|go||"
    "Inkscape|inkscape|inkscape||"
    "kubectl|kubectl|kubectl||"
    "k9s|k9s|k9s||"
    "Krita|krita|krita||"
    "LibreOffice|libreoffice|soffice||"
    "Neovim|neovim|nvim||"
    "Node.js|nodejs npm|node||"
    "OpenSSH Server|openssh-server|sshd|sshd|"
    "tmux|tmux|tmux||"
    "OpenTofu|opentofu|tofu||"
    "Podman|podman|podman||"
    "QBittorrent|qbittorrent|qbittorrent||"
    "Remmina|remmina|remmina||"
    "ripgrep|ripgrep|rg||"
    "Rustup|rustup||||"
    "Syncthing|syncthing|syncthing||"
    "Tailscale|tailscale|tailscale|tailscale|"
    "Thunderbird|thunderbird|thunderbird||"
    "VLC|vlc|vlc||"
    "Ranger|ranger|ranger||"
    "nnn|nnn|nnn||"
    "Midnight Commander|mc|mc||"
    "Nautilus|nautilus|nautilus||"
    "Thunar|thunar|thunar||"
    "Dolphin|dolphin|dolphin||"
    "Nemo|nemo|nemo||"
    "Caja|caja|caja||"
    "PCManFM-Qt|pcmanfm-qt|pcmanfm-qt||"
    "Krusader|krusader|krusader||"
    "awesome|awesome|awesome||"
    "bspwm|bspwm sxhkd|bspwm||"
    "dwm|dwm|dwm||"
    "i3|i3wm|i3||"
    "Openbox|openbox|openbox||"
    "Sway|sway|sway||"
    "Hyprland|hyprland|Hyprland||"
    "Chromium|chromium|chromium||"
    "Flameshot|flameshot|flameshot||"
    "Kdenlive|kdenlive|kdenlive||"
    "OBS Studio|obs-studio|obs||"
    "Audacity|audacity|audacity||"
    "HandBrake|handbrake||||"
    "Wine|wine|wine||"
    "NeoMutt|neomutt|neomutt||"
    "Claws Mail|claws-mail|claws-mail||"
    "Evolution|evolution|evolution||"
    "Geary|geary|geary||"
    "KMail|kmail|kmail||"
    "Zotero|zotero|zotero||"
    "Virt-Manager|virt-manager|virt-manager||"
    "GParted|gparted|gparted||"
    "Filelight|filelight|filelight||"
    "Nextcloud Desktop|nextcloud-client|nextcloud||"
    "MangoHud|mangohud|mangohud||"
    "Feral Gamemode|gamemode|gamemoded||"
)

# Registered utilities whose own installer file has an Alpine branch.
_ALPINE_OWN_HANDLERS=(
    "Full System Upgrade"
    "System Updates"
    "Mount Local Drive"
    "Mount NFS Share"
    "Mount SMB Share"
    "Fix Broken Packages"
    "Delete Default Cloud-Init User"
    "XEN Guest Utilities"
)

# Docker: the daemon only accepts the current user once they are in the docker group.
_alpine_post_docker() {
    sudo addgroup "$USER" docker 2>/dev/null || true
    info "Log out and back in so the docker group applies to your user."
}

# _alpine_field NAME N — field N (1-5) of NAME's table row.
_alpine_field() {
    local row
    for row in "${_ALPINE_TABLE[@]}"; do
        [[ "${row%%|*}" == "$1" ]] && { cut -d'|' -f"$2" <<<"$row"; return 0; }
    done
    return 1
}

_alpine_install() {
    local name="$1" pkgs svc post
    pkgs=$(_alpine_field "$name" 2); svc=$(_alpine_field "$name" 4); post=$(_alpine_field "$name" 5)
    info "Installing ${name}..."
    # shellcheck disable=SC2086
    pkg_install $pkgs || { error "${name}: apk could not install ${pkgs}."; return 1; }
    local s
    for s in $svc; do svc_enable_now "$s" || warn "Could not enable the ${s} service."; done
    [[ -n "$post" ]] && "$post"
    info "${name} installed."
}

_alpine_uninstall() {
    local name="$1" pkgs svc s
    pkgs=$(_alpine_field "$name" 2); svc=$(_alpine_field "$name" 4)
    info "Uninstalling ${name}..."
    for s in $svc; do svc_disable_now "$s" 2>/dev/null || true; done
    # shellcheck disable=SC2086
    pkg_remove $pkgs
}

_alpine_update() {
    local name="$1" pkgs
    pkgs=$(_alpine_field "$name" 2)
    info "Updating ${name}..."
    # shellcheck disable=SC2086
    pkg_upgrade $pkgs
}

_alpine_check() {
    local name="$1" pkgs bin
    pkgs=$(_alpine_field "$name" 2); bin=$(_alpine_field "$name" 3)
    _check_standard "$bin" "${pkgs%% *}" ""
}

_alpine_version() {
    local pkgs
    pkgs=$(_alpine_field "$1" 2)
    _ver_from_pkg "${pkgs%% *}" || echo ""
}

# apply_alpine_registry — see the header. Call once, after every register_*.
apply_alpine_registry() {
    [[ "${DISTRO_FAMILY:-}" == "alpine" ]] || return 0
    local row name id
    declare -A _keep=()
    for name in "${_ALPINE_OWN_HANDLERS[@]}"; do _keep["$name"]=1; done
    for row in "${_ALPINE_TABLE[@]}"; do
        name="${row%%|*}"
        # Only utilities the registry already lists are rebound; a name that is
        # in the table but not registered is simply not offered.
        [[ -n "${INSTALL_FUNCS[$name]:-}" ]] || continue
        _keep["$name"]=1
        id="${name//[^A-Za-z0-9]/_}"
        eval "_alpine_install_${id}()   { _alpine_install   $(printf '%q' "$name"); }"
        eval "_alpine_uninstall_${id}() { _alpine_uninstall $(printf '%q' "$name"); }"
        eval "_alpine_update_${id}()    { _alpine_update    $(printf '%q' "$name"); }"
        eval "_alpine_check_${id}()     { _alpine_check     $(printf '%q' "$name"); }"
        eval "_alpine_version_${id}()   { _alpine_version   $(printf '%q' "$name"); }"
        INSTALL_FUNCS["$name"]="_alpine_install_${id}"
        UNINSTALL_FUNCS["$name"]="_alpine_uninstall_${id}"
        UPDATE_FUNCS["$name"]="_alpine_update_${id}"
        CHECK_FUNCS["$name"]="_alpine_check_${id}"
        VERSION_FUNCS["$name"]="_alpine_version_${id}"
    done
    local -a _utils=() _tasks=()
    for name in "${UTILITIES[@]}";    do [[ -n "${_keep[$name]:-}" ]] && _utils+=("$name"); done
    for name in "${SYSTEM_TASKS[@]}"; do [[ -n "${_keep[$name]:-}" ]] && _tasks+=("$name"); done
    UTILITIES=("${_utils[@]}")
    SYSTEM_TASKS=("${_tasks[@]}")
}
