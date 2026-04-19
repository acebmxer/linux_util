#!/bin/bash
# Mount SMB Share — interactively discover and mount an SMB/CIFS share from a
# remote server, writing a persistent entry to /etc/fstab.

# ── Version / status ──────────────────────────────────────────────────────────
get_version_mount_smb_share() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -c "# linux_util:smb " /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} SMB share(s) configured via linux_util"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Ensure cifs-utils and smbclient are installed.
_msb_ensure_smb_tools() {
    if command -v smbclient &>/dev/null && command -v mount.cifs &>/dev/null; then
        return 0
    fi
    warn "SMB client tools not found. Attempting to install..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y cifs-utils smbclient ;;
        fedora)  sudo "$PKG_MGR" install -y cifs-utils samba-client ;;
        rhel)    sudo "$PKG_MGR" install -y cifs-utils samba-client ;;
        arch)    sudo pacman -S --noconfirm cifs-utils smbclient ;;
        suse)    sudo zypper install -y cifs-utils samba-client ;;
        *)
            warn "Cannot auto-install SMB tools on this distro. Install cifs-utils and smbclient manually."
            return 1
            ;;
    esac
    if ! command -v smbclient &>/dev/null || ! command -v mount.cifs &>/dev/null; then
        error "SMB tools still not available after install attempt."
        return 1
    fi
    return 0
}

# Query disk shares from a server using a temporary credentials file.
# Outputs one pipe-delimited record per share: INDEX|SHARE_NAME
_msb_share_list() {
    local server="$1"
    local username="$2"
    local password="$3"

    local tmp_creds
    tmp_creds=$(mktemp)
    chmod 600 "$tmp_creds"
    printf 'username=%s\npassword=%s\n' "$username" "$password" > "$tmp_creds"

    local raw
    raw=$(smbclient -L "//${server}" -A "$tmp_creds" 2>/dev/null)
    rm -f "$tmp_creds"

    local idx=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([^[:space:]]+)[[:space:]]+Disk ]]; then
            local share_name="${BASH_REMATCH[1]}"
            [[ "$share_name" == *'$' ]] && continue   # skip administrative shares
            (( idx++ )) || true
            printf '%d|%s\n' "$idx" "$share_name"
        fi
    done <<< "$raw"
}

# Derive a sanitised filename stem from a server name.
_msb_creds_path() {
    local server="$1"
    local stem
    stem=$(printf '%s' "$server" | tr -cs 'A-Za-z0-9._-' '_')
    stem="${stem%_}"
    printf '%s/.smb-credentials-%s' "$HOME" "$stem"
}

# Add a KDE Plasma Places entry so the mount appears under "Remote" in Dolphin.
_msb_add_kde_place() {
    local smb_source="$1"   # e.g. //10.0.0.1/data
    local mount_point="$2"

    local places_file="${HOME}/.local/share/user-places.xbel"
    [[ -f "$places_file" ]] || return 0

    local udi="/org/kde/fstab/${smb_source}:${mount_point}"
    grep -qF "$udi" "$places_file" && return 0

    python3 - "$places_file" "$udi" <<'PYEOF'
import sys
path, udi = sys.argv[1], sys.argv[2]
entry = (
    ' <separator>\n'
    '  <info>\n'
    '   <metadata owner="http://www.kde.org">\n'
    f'    <UDI>{udi}</UDI>\n'
    '    <isSystemItem>true</isSystemItem>\n'
    '   </metadata>\n'
    '  </info>\n'
    ' </separator>\n'
)
with open(path) as f:
    content = f.read()
with open(path, 'w') as f:
    f.write(content.replace('</xbel>', entry + '</xbel>'))
PYEOF
    info "Added KDE Places entry: ${mount_point}"
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_mount_smb_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Mount SMB Share                                                ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    # ── Step 1: Ensure SMB tools are present ─────────────────────────────────
    _msb_ensure_smb_tools || return 1

    # ── Step 2: Prompt for server IP / hostname ───────────────────────────────
    local server
    while true; do
        read -rp "SMB server IP or hostname: " server < /dev/tty
        server="${server// /}"
        if [[ -z "$server" ]]; then
            printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi
        break
    done

    # ── Step 3: Prompt for credentials ───────────────────────────────────────
    local username password
    while true; do
        read -rp "Username: " username < /dev/tty
        username="${username// /}"
        [[ -n "$username" ]] && break
        printf '%sUsername cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done

    read -rsp "Password (hidden, press ENTER for none): " password < /dev/tty
    printf '\n' > /dev/tty

    # ── Step 4: Discover shares ───────────────────────────────────────────────
    info "Querying SMB shares on ${server}..."
    local -a shares=()
    mapfile -t shares < <(_msb_share_list "$server" "$username" "$password")

    if (( ${#shares[@]} == 0 )); then
        error "No accessible SMB shares found on ${server}."
        warn "Check credentials, server reachability, and that shares are visible."
        return 1
    fi

    # ── Step 5: Display shares table ─────────────────────────────────────────
    {
        printf '\n'
        printf '  %-4s  %s\n' "#" "Share Name"
        printf '  %s\n' "────────────────────────────────────────"
        local share_entry
        for share_entry in "${shares[@]}"; do
            IFS='|' read -r idx share_name <<< "$share_entry"
            printf '  %-4s  %s\n' "${idx})" "$share_name"
        done
        printf '\n  0)    Cancel\n\n'
    } > /dev/tty

    # ── Step 6: Share selection ───────────────────────────────────────────────
    local total=${#shares[@]}
    local choice
    while true; do
        read -rp "Select share to mount [0-${total}]: " choice < /dev/tty
        if [[ "$choice" == "0" ]]; then
            info "Mount cancelled."
            return 0
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
            break
        fi
        printf '%sInvalid selection. Enter a number between 0 and %d.%s\n' \
            "${RED:-}" "$total" "${RESET:-}" > /dev/tty
    done

    local sel_entry="${shares[$((choice - 1))]}"
    IFS='|' read -r _ sel_share <<< "$sel_entry"

    local default_subfolder
    default_subfolder=$(printf '%s' "$sel_share" | tr -cs 'A-Za-z0-9._-' '_')
    default_subfolder="${default_subfolder%_}"
    [[ -z "$default_subfolder" || "$default_subfolder" == "_" ]] && default_subfolder="smb"

    # ── Step 7: Mount location ────────────────────────────────────────────────
    {
        printf '\n'
        printf '  Mount location — base directory is /home/%s\n' "$USER"
        printf '  Specify a subfolder path (e.g. /media/%s).\n' "$default_subfolder"
        printf '  Press ENTER to use the default: /media/%s\n\n' "$default_subfolder"
    } > /dev/tty

    local subfolder_input mount_point
    while true; do
        read -rp "Subfolder [default: /media/${default_subfolder}]: " subfolder_input < /dev/tty
        [[ -z "$subfolder_input" ]] && subfolder_input="/media/${default_subfolder}"
        subfolder_input="${subfolder_input#/}"
        subfolder_input="${subfolder_input%/}"

        if [[ -z "$subfolder_input" ]]; then
            printf '%sPath cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi

        local _valid=true _component
        while IFS= read -r -d '/' _component || [[ -n "$_component" ]]; do
            _component="${_component%$'\n'}"
            [[ -z "$_component" ]] && continue
            if [[ ! "$_component" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
                _valid=false
                break
            fi
        done <<< "${subfolder_input}/"

        if [[ "$_valid" == "false" ]]; then
            printf '%sEach path component must start with a letter or digit and contain only letters, numbers, underscores, hyphens, or dots.%s\n' \
                "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi

        mount_point="/home/${USER}/${subfolder_input}"
        break
    done

    # ── Step 8: Summary & confirmation ───────────────────────────────────────
    local smb_source="//${server}/${sel_share}"
    local creds_file
    creds_file=$(_msb_creds_path "$server")
    local fstab_opts
    fstab_opts="credentials=${creds_file},uid=$(id -u),gid=$(id -g),nofail,_netdev,iocharset=utf8"

    {
        printf '\n'
        printf '  Server:      %s\n'  "$server"
        printf '  Share:       %s\n'  "$sel_share"
        printf '  Source:      %s\n'  "$smb_source"
        printf '  Mount point: %s\n'  "$mount_point"
        printf '  Credentials: %s\n'  "$creds_file"
        printf '  fstab opts:  %s  0 0\n' "$fstab_opts"
        printf '\n'
    } > /dev/tty

    local confirm
    read -rp "Proceed? [y/N]: " confirm < /dev/tty
    if [[ "${confirm,,}" != "y" ]]; then
        info "Mount cancelled."
        return 0
    fi

    # ── Dry-run path ──────────────────────────────────────────────────────────
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[Dry run] Would create directory: ${mount_point}"
        info "[Dry run] Would write credentials file: ${creds_file}"
        info "[Dry run] Would back up /etc/fstab"
        info "[Dry run] Would append to /etc/fstab:"
        printf '  # linux_util:smb %s → %s\n' "$smb_source" "$mount_point"
        printf '  %s\t%s\tcifs\t%s\t0 0\n' "$smb_source" "$mount_point" "$fstab_opts"
        info "[Dry run] Would run: sudo mount ${mount_point}"
        return 0
    fi

    # ── Step 9: Guard — check fstab for collisions ────────────────────────────
    if grep -qsF "$smb_source" /etc/fstab; then
        warn "${smb_source} already has an entry in /etc/fstab."
        local overwrite
        read -rp "Continue anyway and add a second entry? [y/N]: " overwrite < /dev/tty
        [[ "${overwrite,,}" != "y" ]] && { info "Mount cancelled."; return 0; }
    fi

    if grep -qsE "[[:space:]]${mount_point//\//\\/}[[:space:]]" /etc/fstab; then
        error "Mount point ${mount_point} is already present in /etc/fstab."
        return 1
    fi

    # ── Step 10: Create mount point directory ─────────────────────────────────
    if [[ ! -d "$mount_point" ]]; then
        mkdir -p "$mount_point" || {
            error "Failed to create directory: ${mount_point}"
            return 1
        }
        info "Created mount point: ${mount_point}"
    else
        info "Mount point already exists: ${mount_point}"
    fi

    # ── Step 11: Write credentials file ──────────────────────────────────────
    printf 'username=%s\npassword=%s\n' "$username" "$password" > "$creds_file"
    chmod 600 "$creds_file"
    info "Credentials written to ${creds_file}"

    # ── Step 12: Back up fstab ────────────────────────────────────────────────
    local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$fstab_backup" || {
        error "Failed to back up /etc/fstab"
        return 1
    }
    info "fstab backed up to ${fstab_backup}"

    # ── Step 13: Append fstab entry ───────────────────────────────────────────
    local fstab_comment
    fstab_comment="# linux_util:smb ${smb_source} → ${mount_point} — added $(date '+%Y-%m-%d %H:%M:%S')"
    local fstab_entry
    fstab_entry=$(printf '%s\t%s\tcifs\t%s\t0 0' "$smb_source" "$mount_point" "$fstab_opts")

    printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
        | run_as_root tee -a /etc/fstab > /dev/null || {
        error "Failed to write to /etc/fstab. Restoring backup..."
        run_as_root cp "$fstab_backup" /etc/fstab
        return 1
    }

    # ── Step 14: Mount ────────────────────────────────────────────────────────
    run_as_root mount "$mount_point" || {
        error "mount failed for ${mount_point}."
        warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${mount_point}"
        warn "Check that the server is reachable and the credentials are correct."
        return 1
    }

    _msb_add_kde_place "$smb_source" "$mount_point"

    echo ""
    info "SMB share mounted successfully."
    info "  Source:      ${smb_source}"
    info "  Mount point: ${mount_point}"
    info "  Backup:      ${fstab_backup}"
    echo ""
    return 0
}

# ── Lifecycle stubs ───────────────────────────────────────────────────────────
check_mount_smb_share()     { return 1; }
uninstall_mount_smb_share() { return 0; }
update_mount_smb_share()    { setup_mount_smb_share; }
