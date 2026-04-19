#!/bin/bash
# Mount NFS Share — interactively discover and mount an NFS export from a remote
# server, writing a persistent entry to /etc/fstab.

# ── Version / status ──────────────────────────────────────────────────────────
get_version_mount_nfs_share() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -c "# linux_util:nfs " /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} NFS share(s) configured via linux_util"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Ensure nfs-common / nfs-utils is installed (provides mount.nfs and showmount).
_mns_ensure_nfs_tools() {
    if command -v showmount &>/dev/null && command -v mount.nfs &>/dev/null; then
        return 0
    fi
    warn "NFS client tools not found. Attempting to install..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y nfs-common ;;
        fedora)  sudo "$PKG_MGR" install -y nfs-utils ;;
        rhel)    sudo "$PKG_MGR" install -y nfs-utils ;;
        arch)    sudo pacman -S --noconfirm nfs-utils ;;
        suse)    sudo zypper install -y nfs-client ;;
        *)
            warn "Cannot auto-install NFS tools on this distro. Install nfs-common or nfs-utils manually."
            return 1
            ;;
    esac

    if ! command -v showmount &>/dev/null || ! command -v mount.nfs &>/dev/null; then
        error "NFS tools still not available after install attempt."
        return 1
    fi
    return 0
}

# Query exports from a server and output one pipe-delimited record per export:
#   INDEX|EXPORT_PATH|ALLOWED_CLIENTS
_mns_export_list() {
    local server="$1"
    local idx=0
    local raw
    raw=$(showmount -e --no-headers "$server" 2>/dev/null) || return 1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local export_path clients
        export_path=$(awk '{print $1}' <<< "$line")
        clients=$(awk '{$1=""; print $0}' <<< "$line" | sed 's/^ *//')
        [[ -z "$export_path" ]] && continue
        (( idx++ )) || true
        printf '%d|%s|%s\n' "$idx" "$export_path" "$clients"
    done <<< "$raw"
}

# Add a KDE Plasma Places entry so the mount appears under "Remote" in Dolphin.
_mns_add_kde_place() {
    local nfs_source="$1"   # e.g. 10.100.10.183:/mnt/data/Apps
    local mount_point="$2"  # e.g. /home/nick/media/Apps

    local places_file="${HOME}/.local/share/user-places.xbel"
    [[ -f "$places_file" ]] || return 0

    local udi="/org/kde/fstab/${nfs_source}:${mount_point}"
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
setup_mount_nfs_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Mount NFS Share                                                ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    # ── Step 1: Ensure NFS tools are present ─────────────────────────────────
    _mns_ensure_nfs_tools || return 1

    # ── Step 2: Prompt for server IP / hostname ───────────────────────────────
    local server
    while true; do
        read -rp "NFS server IP or hostname: " server < /dev/tty
        server="${server// /}"   # strip accidental spaces
        if [[ -z "$server" ]]; then
            printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi
        break
    done

    # ── Step 3: Discover exports ──────────────────────────────────────────────
    info "Querying NFS exports from ${server}..."
    local -a exports=()
    mapfile -t exports < <(_mns_export_list "$server")

    if (( ${#exports[@]} == 0 )); then
        error "No NFS exports found on ${server}."
        warn "Check that the server is reachable, NFS is running, and exports are configured."
        return 1
    fi

    # ── Step 4: Display exports table ────────────────────────────────────────
    {
        printf '\n'
        printf '  %-4s  %-35s  %s\n' "#" "Export Path" "Allowed Clients"
        printf '  %s\n' "────────────────────────────────────────────────────────────────────────────"
        local export_entry
        for export_entry in "${exports[@]}"; do
            IFS='|' read -r idx export_path clients <<< "$export_entry"
            printf '  %-4s  %-35s  %s\n' "${idx})" "$export_path" "$clients"
        done
        printf '\n  0)    Cancel\n\n'
    } > /dev/tty

    # ── Step 5: Share selection ───────────────────────────────────────────────
    local total=${#exports[@]}
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

    local sel_entry="${exports[$((choice - 1))]}"
    IFS='|' read -r _ sel_export _ <<< "$sel_entry"

    # Derive a default subfolder name from the last component of the export path
    local default_subfolder
    default_subfolder=$(basename "$sel_export" | tr -cs 'A-Za-z0-9._-' '_')
    default_subfolder="${default_subfolder%_}"
    [[ -z "$default_subfolder" || "$default_subfolder" == "_" ]] && default_subfolder="nfs"

    # ── Step 6: Mount location ────────────────────────────────────────────────
    {
        printf '\n'
        printf '  Mount location — base directory is %s\n' "/home/${USER}"
        printf '  Specify a subfolder path (e.g. /media/%s).\n' "$default_subfolder"
        printf '  Press ENTER to use the default: /media/%s\n\n' "$default_subfolder"
    } > /dev/tty

    local subfolder_input mount_point
    while true; do
        read -rp "Subfolder [default: /media/${default_subfolder}]: " subfolder_input < /dev/tty

        # Blank → use default
        [[ -z "$subfolder_input" ]] && subfolder_input="/media/${default_subfolder}"

        # Strip leading slash so we can re-attach cleanly, then strip trailing slashes
        subfolder_input="${subfolder_input#/}"
        subfolder_input="${subfolder_input%/}"

        if [[ -z "$subfolder_input" ]]; then
            printf '%sPath cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi

        # Validate each path component
        local _valid=true _component
        while IFS= read -r -d '/' _component || [[ -n "$_component" ]]; do
            _component="${_component%$'\n'}"  # strip trailing newline added by <<<
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

    # ── Step 7: Summary & confirmation ───────────────────────────────────────
    local nfs_source="${server}:${sel_export}"
    local fstab_opts="defaults,nofail,_netdev"

    {
        printf '\n'
        printf '  Server:      %s\n'   "$server"
        printf '  Export:      %s\n'   "$sel_export"
        printf '  Source:      %s\n'   "$nfs_source"
        printf '  Mount point: %s\n'   "$mount_point"
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
        info "[Dry run] Would back up /etc/fstab"
        info "[Dry run] Would append to /etc/fstab:"
        printf '  # linux_util:nfs %s → %s\n' "$nfs_source" "$mount_point"
        printf '  %s\t%s\tnfs\t%s\t0 0\n' "$nfs_source" "$mount_point" "$fstab_opts"
        info "[Dry run] Would run: sudo mount ${mount_point}"
        return 0
    fi

    # ── Step 8: Guard — check fstab for collisions ───────────────────────────
    if grep -qsF "$nfs_source" /etc/fstab; then
        warn "${nfs_source} already has an entry in /etc/fstab."
        local overwrite
        read -rp "Continue anyway and add a second entry? [y/N]: " overwrite < /dev/tty
        [[ "${overwrite,,}" != "y" ]] && { info "Mount cancelled."; return 0; }
    fi

    if grep -qsE "[[:space:]]${mount_point//\//\\/}[[:space:]]" /etc/fstab; then
        error "Mount point ${mount_point} is already present in /etc/fstab."
        return 1
    fi

    # ── Step 9: Create mount point directory ─────────────────────────────────
    if [[ ! -d "$mount_point" ]]; then
        mkdir -p "$mount_point" || {
            error "Failed to create directory: ${mount_point}"
            return 1
        }
        info "Created mount point: ${mount_point}"
    else
        info "Mount point already exists: ${mount_point}"
    fi

    # ── Step 10: Back up fstab ────────────────────────────────────────────────
    local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$fstab_backup" || {
        error "Failed to back up /etc/fstab"
        return 1
    }
    info "fstab backed up to ${fstab_backup}"

    # ── Step 11: Append fstab entry ───────────────────────────────────────────
    local fstab_comment
    fstab_comment="# linux_util:nfs ${nfs_source} → ${mount_point} — added $(date '+%Y-%m-%d %H:%M:%S')"

    local fstab_entry
    fstab_entry=$(printf '%s\t%s\tnfs\t%s\t0 0' "$nfs_source" "$mount_point" "$fstab_opts")

    printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
        | run_as_root tee -a /etc/fstab > /dev/null || {
        error "Failed to write to /etc/fstab. Restoring backup..."
        run_as_root cp "$fstab_backup" /etc/fstab
        return 1
    }

    # ── Step 12: Mount ────────────────────────────────────────────────────────
    run_as_root mount "$mount_point" || {
        error "mount failed for ${mount_point}."
        warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${mount_point}"
        warn "Check that the server is reachable and the export allows this host."
        return 1
    }

    _mns_add_kde_place "$nfs_source" "$mount_point"

    echo ""
    info "NFS share mounted successfully."
    info "  Source:      ${nfs_source}"
    info "  Mount point: ${mount_point}"
    info "  Backup:      ${fstab_backup}"
    echo ""
    return 0
}

# ── Lifecycle stubs (task is run-on-demand, not idempotent) ───────────────────
check_mount_nfs_share()     { return 1; }
uninstall_mount_nfs_share() { return 0; }
update_mount_nfs_share()    { setup_mount_nfs_share; }
