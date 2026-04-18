#!/bin/bash
# Mount NFS Share — interactively add a network NFS export to /etc/fstab
# and mount it under the current user's home directory (or a specified path).

# ── Version / status ──────────────────────────────────────────────────────────
get_version_mount_nfs_share() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -c "# linux_util:nfs " /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} NFS share(s) configured via linux_util"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

_nfs_ensure_tools() {
    local missing=false
    if ! command -v mount.nfs &>/dev/null && ! command -v mount.nfs4 &>/dev/null; then
        missing=true
    fi

    if [[ "$missing" == "true" ]]; then
        warn "NFS client tools are not installed. Attempting to install..."
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y nfs-common ;;
            fedora)  sudo "$PKG_MGR" install -y nfs-utils ;;
            rhel)    sudo "$PKG_MGR" install -y nfs-utils ;;
            arch)    sudo pacman -S --noconfirm nfs-utils ;;
            suse)    sudo zypper install -y nfs-client ;;
            *)       warn "Cannot auto-install NFS tools on this distro. Install them manually."; return 1 ;;
        esac
    fi
    return 0
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_mount_nfs_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Mount NFS Network Share                                        ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    # ── Step 1: Server IP / hostname ──────────────────────────────────────────
    local server_ip
    while true; do
        read -rp "Server IP address or hostname: " server_ip < /dev/tty
        server_ip="${server_ip// /}"
        if [[ -z "$server_ip" ]]; then
            printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi
        break
    done

    # ── Step 2: Export path ───────────────────────────────────────────────────
    local export_path
    while true; do
        read -rp "Export path on server (e.g. /srv/nfs/data): " export_path < /dev/tty
        export_path="${export_path%/}"   # strip trailing slash
        if [[ -z "$export_path" ]]; then
            printf '%sExport path cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi
        if [[ "${export_path:0:1}" != "/" ]]; then
            printf '%sExport path must start with /.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi
        break
    done

    # ── Step 3: NFS version ───────────────────────────────────────────────────
    printf '\n' > /dev/tty
    local nfs_ver
    while true; do
        read -rp "NFS version [4 / 3, default: 4]: " nfs_ver < /dev/tty
        [[ -z "$nfs_ver" ]] && nfs_ver="4"
        if [[ "$nfs_ver" == "4" || "$nfs_ver" == "3" ]]; then
            break
        fi
        printf '%sPlease enter 3 or 4.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done

    # ── Step 4: Mount folder name ─────────────────────────────────────────────
    local default_name
    default_name=$(printf '%s' "${export_path##*/}" | tr -cs 'A-Za-z0-9._-' '_')
    [[ -z "$default_name" ]] && default_name="nfs_share"

    local default_mount_point="/home/${USER}/${default_name}"
    printf '\n' > /dev/tty
    local mount_input
    while true; do
        read -rp "Mount point [default: ${default_mount_point}]: " mount_input < /dev/tty
        [[ -z "$mount_input" ]] && mount_input="$default_mount_point"

        if [[ "$mount_input" == /* ]]; then
            # Absolute path — validate each component
            if [[ ! "$mount_input" =~ ^/[A-Za-z0-9][A-Za-z0-9_./ \-]*$ ]]; then
                printf '%sInvalid path. Use an absolute path (e.g. /media/Apps) or a folder name.%s\n' \
                    "${RED:-}" "${RESET:-}" > /dev/tty
                continue
            fi
        else
            # Bare name — validate and expand to home
            if [[ ! "$mount_input" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
                printf '%sName must start with a letter or digit and contain only letters, numbers, underscores, hyphens, or dots.%s\n' \
                    "${RED:-}" "${RESET:-}" > /dev/tty
                continue
            fi
            mount_input="/home/${USER}/${mount_input}"
        fi
        break
    done

    local mount_point="$mount_input"
    local nfs_source="${server_ip}:${export_path}"
    local fstab_opts="nfsvers=${nfs_ver},rw,soft,intr,timeo=30,retrans=2,nofail,_netdev"

    # ── Step 5: Summary & confirmation ───────────────────────────────────────
    {
        printf '\n'
        printf '  Source:      %s\n' "$nfs_source"
        printf '  NFS version: %s\n' "$nfs_ver"
        printf '  Mount point: %s\n' "$mount_point"
        printf '  Options:     %s\n' "$fstab_opts"
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

    # ── Step 6: Ensure tools ──────────────────────────────────────────────────
    _nfs_ensure_tools || return 1

    # ── Step 7: Guard — check fstab for collisions ────────────────────────────
    if grep -qsF "${nfs_source} " /etc/fstab || grep -qsF "${nfs_source}	" /etc/fstab; then
        warn "An entry for ${nfs_source} already exists in /etc/fstab."
        local overwrite
        read -rp "Continue anyway and add a second entry? [y/N]: " overwrite < /dev/tty
        [[ "${overwrite,,}" != "y" ]] && { info "Mount cancelled."; return 0; }
    fi

    if grep -qsE "[[:space:]]${mount_point//\//\\/}[[:space:]]" /etc/fstab; then
        error "Mount point ${mount_point} is already present in /etc/fstab."
        return 1
    fi

    # ── Step 8: Create mount point directory ──────────────────────────────────
    if [[ ! -d "$mount_point" ]]; then
        mkdir -p "$mount_point" || {
            error "Failed to create directory: ${mount_point}"
            return 1
        }
        info "Created mount point: ${mount_point}"
    else
        info "Mount point already exists: ${mount_point}"
    fi

    # ── Step 9: Back up fstab ─────────────────────────────────────────────────
    local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$fstab_backup" || {
        error "Failed to back up /etc/fstab"
        return 1
    }
    info "fstab backed up to ${fstab_backup}"

    # ── Step 10: Append fstab entry ───────────────────────────────────────────
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

    # ── Step 11: Mount ────────────────────────────────────────────────────────
    run_as_root mount "$mount_point" || {
        error "mount failed for ${mount_point}."
        warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${mount_point}"
        return 1
    }

    echo ""
    info "NFS share mounted successfully."
    info "  Source:      ${nfs_source}"
    info "  Mount point: ${mount_point}"
    info "  Backup:      ${fstab_backup}"
    echo ""
    return 0
}

# ── Lifecycle stubs ───────────────────────────────────────────────────────────
check_mount_nfs_share()     { return 1; }
uninstall_mount_nfs_share() { return 0; }
update_mount_nfs_share()    { setup_mount_nfs_share; }
