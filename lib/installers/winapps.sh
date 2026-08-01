#!/bin/bash
# WinApps — run Windows applications on the Linux desktop via FreeRDP RemoteApp

# --- WinApps ---

# Upstream's setup.sh hard-codes these paths for a '--user' installation, so we
# populate exactly the same locations. Anything else and 'winapps-setup' would
# clone a second copy of the source instead of reusing ours.
_WINAPPS_BIN="$HOME/.local/bin"
_WINAPPS_SRC="$_WINAPPS_BIN/winapps-src"
_WINAPPS_SYS_SRC="/usr/local/bin/winapps-src"
_WINAPPS_CONF_DIR="$HOME/.config/winapps"
_WINAPPS_CONF="$_WINAPPS_CONF_DIR/winapps.conf"

check_winapps() {
    [[ -d "$_WINAPPS_SRC" || -d "$_WINAPPS_SYS_SRC" ]] && return 0
    command -v winapps &>/dev/null
}

# Set to 1 once the Windows container has been started, so the closing
# instructions do not tell the user to create a VM they already have.
_WINAPPS_VM_STARTED=0
# Resolved compose front-end and the backend it drives; filled in by
# _winapps_resolve_compose.
_WINAPPS_COMPOSE=()
_WINAPPS_BACKEND=""

# Install FreeRDP 3 from Flathub. Used on releases whose repositories still
# only carry FreeRDP 2, which WinApps refuses to run against.
_winapps_freerdp_flatpak() {
    ensure_flatpak || return 1
    flatpak install -y flathub com.freerdp.FreeRDP || return 1
    # WinApps hands FreeRDP host paths for the shared home drive, so the
    # sandbox needs to see $HOME.
    sudo flatpak override --filesystem=home com.freerdp.FreeRDP
}

# Find a usable compose front-end. Docker ships v2 as a plugin ('docker
# compose') but older systems still have standalone 'docker-compose', and
# Podman offers both shapes too.
_winapps_resolve_compose() {
    _WINAPPS_COMPOSE=()
    _WINAPPS_BACKEND=""
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        _WINAPPS_COMPOSE=(docker compose); _WINAPPS_BACKEND="docker"
    elif command -v docker-compose &>/dev/null; then
        _WINAPPS_COMPOSE=(docker-compose); _WINAPPS_BACKEND="docker"
    elif command -v podman &>/dev/null && podman compose version &>/dev/null; then
        _WINAPPS_COMPOSE=(podman compose); _WINAPPS_BACKEND="podman"
    elif command -v podman-compose &>/dev/null; then
        _WINAPPS_COMPOSE=(podman-compose); _WINAPPS_BACKEND="podman"
    else
        error "No compose front-end found. Install the Docker Compose plugin, docker-compose, or podman-compose."
        return 1
    fi
    return 0
}

# Bring up the Windows container described by upstream's compose file.
_winapps_deploy_vm() {
    local _compose_file="$_WINAPPS_SRC/compose.yaml"
    if [[ ! -f "$_compose_file" ]]; then
        error "No compose file at $_compose_file — the WinApps source is incomplete."
        return 1
    fi

    # KVM is the entire premise. Without it QEMU falls back to software
    # emulation and Windows is far too slow to use as a desktop.
    if [[ ! -e /dev/kvm ]]; then
        error "/dev/kvm is missing. Enable VT-x/AMD-V in your BIOS/UEFI, then re-run this task."
        return 1
    fi
    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        warn "No read/write access to /dev/kvm — the container will fail to start."
        warn "Fix it with 'sudo usermod -aG kvm \"\$USER\"', then log out and back in."
    fi

    _winapps_resolve_compose || return 1
    if [[ "$_WINAPPS_BACKEND" == "podman" ]]; then
        warn "Rootless Podman needs 'crun' (not 'runc') and the commented-out 'group_add: keep-groups'"
        warn "lines in compose.yaml before it can reach /dev/kvm."
    fi

    info "Starting the Windows VM with '${_WINAPPS_COMPOSE[*]}'..."
    info "This pulls several GB and installs Windows unattended — expect a long first run."
    if ! "${_WINAPPS_COMPOSE[@]}" --file "$_compose_file" up -d; then
        error "Failed to start the Windows container."
        return 1
    fi

    # Keep the config's backend consistent with what actually got started,
    # or WinApps will look for the VM using the wrong tool.
    if [[ "$_WINAPPS_BACKEND" == "podman" ]] && grep -q '^WAFLAVOR="docker"' "$_WINAPPS_CONF" 2>/dev/null; then
        sed -i 's/^WAFLAVOR="docker"/WAFLAVOR="podman"/' "$_WINAPPS_CONF"
        info "Set WAFLAVOR=\"podman\" in $_WINAPPS_CONF to match the backend used."
    fi

    _WINAPPS_VM_STARTED=1
    info "Windows is installing in the background. Watch it at http://127.0.0.1:8006."
    info "Stop it with '${_WINAPPS_COMPOSE[*]} --file $_compose_file stop'."
}

# Offer to create the VM. Declining is always safe — the closing instructions
# print the command to run later.
_winapps_offer_vm() {
    # Explicit opt-in/opt-out for unattended runs (scripted '--install WinApps',
    # profile imports, cron).
    case "${WINAPPS_DEPLOY_VM:-}" in
        1|y|yes|true)  _winapps_deploy_vm; return 0 ;;
        0|n|no|false)  return 0 ;;
    esac

    # Nothing to prompt on — never kick off a multi-GB download unasked.
    [[ -e /dev/tty && -r /dev/tty ]] || return 0

    echo ""
    info "WinApps needs a Windows VM. One can be created now from $_WINAPPS_SRC/compose.yaml"
    info "Defaults: Windows 11 Pro, 4 GB RAM, 4 CPU cores, 64 GB disk (~8 GB download)."
    info "You must supply your own Windows license; it runs unactivated until you do."

    local _ans=""
    read -rp "Create the Windows VM now? [y/N, or 'e' to edit compose.yaml first]: " _ans < /dev/tty
    case "${_ans,,}" in
        e*)
            "${EDITOR:-nano}" "$_WINAPPS_SRC/compose.yaml" < /dev/tty > /dev/tty 2>&1
            read -rp "Create the Windows VM now? [y/N]: " _ans < /dev/tty
            [[ "${_ans,,}" == y* ]] && _winapps_deploy_vm
            ;;
        y*) _winapps_deploy_vm ;;
        *)  info "Skipping VM creation." ;;
    esac
    return 0
}

install_winapps() {
    info "Installing WinApps..."
    ensure_tools

    # Upstream's dependency set. FreeRDP must be version 3 — WinApps relies on
    # RemoteApp handling that FreeRDP 2 does not expose.
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y curl dialog git iproute2 libnotify-bin netcat-openbsd || return 1
            # freerdp3-x11 only exists on Debian 13+ / Ubuntu 24.04+; older
            # releases ship FreeRDP 2 under the freerdp2-x11 name, which is
            # not usable here.
            if apt-cache show freerdp3-x11 &>/dev/null; then
                sudo apt install -y freerdp3-x11 || return 1
            else
                warn "freerdp3-x11 is not in this release's repositories — installing FreeRDP 3 from Flathub instead."
                _winapps_freerdp_flatpak || {
                    error "Could not provide FreeRDP 3, which WinApps requires."
                    return 1
                }
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y curl dialog git iproute libnotify nmap-ncat freerdp || return 1
            ;;
        rhel)
            # freerdp and nmap-ncat come from EPEL on RHEL/Rocky/Alma/CentOS.
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y curl dialog git iproute libnotify nmap-ncat freerdp || return 1
            ;;
        arch)
            sudo pacman -S --noconfirm --needed curl dialog git iproute2 libnotify openbsd-netcat freerdp || return 1
            ;;
        suse)
            sudo zypper install -y curl dialog git iproute2 libnotify-tools netcat-openbsd freerdp || return 1
            ;;
        *)
            error "Unsupported distribution for WinApps."
            return 1
            ;;
    esac

    # Confirm what actually landed: distributions differ on whether the v3
    # binary is called xfreerdp or xfreerdp3, and a v2 binary silently
    # satisfies the package install on some releases.
    local _rdp_cmd="" _rdp_major=""
    for _rdp_cmd in xfreerdp3 xfreerdp; do
        command -v "$_rdp_cmd" &>/dev/null || continue
        _rdp_major=$("$_rdp_cmd" --version 2>/dev/null | grep -oP '[0-9]+' | head -1)
        [[ -n "$_rdp_major" ]] && break
    done
    if [[ -n "$_rdp_major" && "$_rdp_major" -lt 3 ]]; then
        warn "FreeRDP $_rdp_major found — WinApps needs version 3. Install it from Flathub, or set FREERDP_COMMAND in the config."
    fi

    # Clone into the location upstream's installer expects, so 'winapps-setup'
    # updates this checkout rather than making a second one.
    if [[ -d "$_WINAPPS_SRC/.git" ]]; then
        info "Updating the existing WinApps source at $_WINAPPS_SRC..."
        git -C "$_WINAPPS_SRC" pull --no-rebase --recurse-submodules 2>/dev/null || \
            warn "Could not update the existing WinApps checkout — 'winapps-setup' will retry on its next run."
    else
        mkdir -p "$_WINAPPS_BIN"
        git clone --recurse-submodules --remote-submodules \
            https://github.com/winapps-org/winapps.git "$_WINAPPS_SRC" || {
            error "Failed to clone the WinApps repository."
            return 1
        }
    fi

    # Upstream creates this symlink only at the end of a successful install;
    # doing it now means the user can run 'winapps-setup' by name once their
    # Windows VM is up. The 'winapps' symlink is deliberately NOT created —
    # setup.sh reads that file as a pre-existing installation and aborts.
    ln -sf "$_WINAPPS_SRC/setup.sh" "$_WINAPPS_BIN/winapps-setup"

    # Configuration template. setup.sh exits with EC_NO_CONFIG when this file
    # is missing, so seed it — but never overwrite credentials already there.
    if [[ -f "$_WINAPPS_CONF" ]]; then
        info "Keeping the existing configuration at $_WINAPPS_CONF."
    else
        mkdir -p "$_WINAPPS_CONF_DIR"
        cat > "$_WINAPPS_CONF" <<'WINAPPS_CONF_EOF'
##################################
#   WINAPPS CONFIGURATION FILE   #
##################################
# Full reference: https://github.com/winapps-org/winapps#step-3-create-a-winapps-configuration-file

# [WINDOWS USERNAME] — must match the account inside the Windows VM.
RDP_USER="MyWindowsUser"

# [WINDOWS PASSWORD]
# FreeRDP 3.9.0 and newer require a password to be set.
RDP_PASS="MyWindowsPassword"

# [WINDOWS DOMAIN] — blank unless the VM is domain-joined.
RDP_DOMAIN=""

# [WINDOWS IPv4 ADDRESS]
# Defaults to 127.0.0.1 for docker/podman. Leave blank for libvirt and
# WinApps will determine it at runtime.
RDP_IP="127.0.0.1"

# [RDP PORT] — the host port mapped to Windows port 3389.
RDP_PORT="3389"

# [VM NAME] — libvirt only; must match the domain name of the Windows VM.
VM_NAME="RDPWindows"

# [BACKEND] — 'docker', 'podman', 'libvirt' or 'manual'.
WAFLAVOR="docker"

# [DISPLAY SCALING FACTOR] — 100, 140 or 180.
RDP_SCALE="100"

# [REMOVABLE MEDIA MOUNT POINT]
REMOVABLE_MEDIA="/run/media"

# [EXTRA FREERDP FLAGS]
RDP_FLAGS="/cert:tofu /sound /microphone +home-drive"

# [DEBUG] — appends to ~/.local/share/winapps/winapps.log.
DEBUG="true"

# [AUTOMATICALLY PAUSE WINDOWS] — 'on' or 'off'; incompatible with 'manual'.
AUTOPAUSE="off"
AUTOPAUSE_TIME="300"

# [FREERDP COMMAND]
# Leave blank to auto-detect (xfreerdp / xfreerdp3 / the Flathub build).
FREERDP_COMMAND=""
WINAPPS_CONF_EOF
        # The file holds the Windows password in plaintext.
        chmod 600 "$_WINAPPS_CONF"
        info "Wrote a configuration template to $_WINAPPS_CONF (mode 600)."
    fi

    # WinApps is a client — it cannot do anything without a Windows VM behind it.
    if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null && ! command -v virsh &>/dev/null; then
        warn "No VM backend found. WinApps needs Docker, Podman or libvirt/KVM — install one from the Development tab first."
    fi

    case ":$PATH:" in
        *":$_WINAPPS_BIN:"*) ;;
        *) warn "$_WINAPPS_BIN is not on your PATH — add it, or the 'winapps-setup' command and the generated app launchers will not resolve." ;;
    esac

    _winapps_offer_vm

    info "WinApps prerequisites installed. Remaining steps:"
    if (( _WINAPPS_VM_STARTED )); then
        info "  1. Wait for Windows to finish installing — watch it at http://127.0.0.1:8006."
    else
        info "  1. Create the Windows VM — '${_WINAPPS_COMPOSE[*]:-docker compose} --file $_WINAPPS_SRC/compose.yaml up -d'."
        info "     Watch the install at http://127.0.0.1:8006 and wait for it to reach the desktop."
    fi
    info "  2. Make sure the Windows username and password in $_WINAPPS_CONF match the VM."
    info "  3. Run 'winapps-setup --user' to detect Windows applications and create desktop launchers."
    info "Windows itself is licensed separately: it installs and runs unactivated, but"
    info "activation needs your own Retail/Volume key, and RDP RemoteApp requires Pro or better."
}

uninstall_winapps() {
    info "Uninstalling WinApps..."

    # Let upstream remove its own launchers and .desktop files where it can —
    # it knows which of the files in ~/.local/bin belong to it.
    if [[ -f "$_WINAPPS_BIN/winapps" && -f "$_WINAPPS_SRC/setup.sh" ]]; then
        bash "$_WINAPPS_SRC/setup.sh" --user --uninstall || \
            warn "Upstream's uninstaller failed — removing the WinApps files directly."
    fi

    # Clean up whatever is left, including a source tree that was never fully
    # installed (upstream's uninstaller leaves the source behind by design).
    rm -f "$_WINAPPS_BIN/winapps" "$_WINAPPS_BIN/winapps-setup"
    rm -rf "$_WINAPPS_SRC" "$HOME/.local/share/winapps"

    # Any launcher still pointing at the removed binary is now dead. Match the
    # path literally (-F) and glob the directory rather than recursing, so a
    # stray subdirectory cannot turn this into a wider search.
    local _desktop
    while IFS= read -r _desktop; do
        [[ -n "$_desktop" ]] && rm -f "$_desktop"
    done < <(grep -lF -d skip -e "$_WINAPPS_BIN/winapps" \
        "$HOME/.local/share/applications/"*.desktop 2>/dev/null || true)

    if [[ -d "$_WINAPPS_SYS_SRC" ]]; then
        warn "A system-wide WinApps install remains at $_WINAPPS_SYS_SRC — remove it with 'sudo winapps-setup --system --uninstall'."
    fi

    # Left in place on purpose: it holds credentials the user typed, and
    # upstream's own uninstaller preserves it too.
    [[ -f "$_WINAPPS_CONF" ]] && \
        info "Kept your configuration at $_WINAPPS_CONF. Delete $_WINAPPS_CONF_DIR yourself if you want it gone."

    # The Windows VM is never torn down here. Its volume holds a full Windows
    # installation and whatever the user saved inside it — removing that is not
    # something an uninstall of the Linux-side client should decide.
    local _rt
    for _rt in docker podman; do
        command -v "$_rt" &>/dev/null || continue
        if "$_rt" ps --all --filter name=WinApps --format '{{.Names}}' 2>/dev/null | grep -qx WinApps; then
            warn "The 'WinApps' Windows VM container is still present and was NOT removed."
            warn "It holds your Windows installation and its files. Remove it deliberately with:"
            warn "  ${_rt} rm -f WinApps && ${_rt} volume rm winapps_data"
            break
        fi
    done
    info "The FreeRDP, dialog and netcat packages were left installed."
}

update_winapps() {
    info "Updating WinApps..."
    if [[ ! -d "$_WINAPPS_SRC/.git" ]]; then
        warn "No WinApps source checkout at $_WINAPPS_SRC — nothing to update."
        return 0
    fi
    git -C "$_WINAPPS_SRC" pull --no-rebase --recurse-submodules || {
        error "Failed to update the WinApps source."
        return 1
    }
    # Application definitions can change between revisions; re-running setup is
    # how upstream picks them up, but it needs the Windows VM running.
    info "Source updated. Re-run 'winapps-setup --user' with Windows running to refresh the app launchers."
}

get_version_winapps() {
    local _src=""
    [[ -d "$_WINAPPS_SRC/.git" ]] && _src="$_WINAPPS_SRC"
    [[ -z "$_src" && -d "$_WINAPPS_SYS_SRC/.git" ]] && _src="$_WINAPPS_SYS_SRC"
    [[ -n "$_src" ]] || return 1
    # Upstream publishes no releases or tags, so the commit date and hash are
    # the only version identifiers available.
    git -C "$_src" log -1 --date=format:'%Y.%m.%d' --format='%cd-%h' 2>/dev/null || echo ""
}
