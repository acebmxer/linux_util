#!/bin/bash
# Mount Local Drive — interactively add an unmounted block device to /etc/fstab
# and mount it at a user-specified path.

# ── Version / status ──────────────────────────────────────────────────────────
get_version_mount_local_drive() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -c "# linux_util:mount " /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} drive(s) configured via linux_util"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Extract the value of FIELD="..." from a single lsblk -P output line.
_mld_field() {
    local line="$1" field="$2"
    printf '%s\n' "$line" | sed -n "s/.*${field}=\"\([^\"]*\)\".*/\1/p"
}

# Output one pipe-delimited record per unmounted, formatted partition:
#   INDEX|NAME|UUID|FSTYPE|LABEL|SIZE
_mld_unmounted_list() {
    local idx=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name uuid fstype label size mountpoint
        name=$(_mld_field "$line" "NAME")
        uuid=$(_mld_field "$line" "UUID")
        fstype=$(_mld_field "$line" "FSTYPE")
        label=$(_mld_field "$line" "LABEL")
        size=$(_mld_field "$line" "SIZE")
        mountpoint=$(_mld_field "$line" "MOUNTPOINT")

        # Skip: disk (not partition), no UUID, no filesystem, swap, already mounted
        [[ -z "$uuid" || -z "$fstype" ]] && continue
        [[ "$fstype" == "swap" ]]        && continue
        [[ -n "$mountpoint" ]]           && continue

        (( idx++ )) || true
        printf '%d|%s|%s|%s|%s|%s\n' "$idx" "$name" "$uuid" "$fstype" "$label" "$size"
    done < <(lsblk -Pno NAME,UUID,FSTYPE,LABEL,SIZE,MOUNTPOINT 2>/dev/null)
}

# Return fstab mount options for a given filesystem type.
_mld_fstab_opts() {
    local fstype="$1"
    local uid gid
    uid=$(id -u)
    gid=$(id -g)
    case "$fstype" in
        ntfs|ntfs-3g|ntfs3)
            printf 'uid=%s,gid=%s,umask=0022,nofail' "$uid" "$gid"
            ;;
        vfat|fat|fat16|fat32|msdos|exfat)
            printf 'uid=%s,gid=%s,umask=0022,nofail' "$uid" "$gid"
            ;;
        btrfs)
            printf 'defaults,compress=zstd,nofail'
            ;;
        *)
            # ext2/ext3/ext4, xfs, f2fs, jfs, etc.
            printf 'defaults,nofail'
            ;;
    esac
}

# Return dump and pass fields for a given filesystem type.
_mld_dump_pass() {
    local fstype="$1"
    case "$fstype" in
        ntfs|ntfs-3g|ntfs3|vfat|fat|fat16|fat32|msdos|exfat|btrfs)
            printf '0 0'
            ;;
        *)
            printf '0 2'
            ;;
    esac
}

# Resolve the effective filesystem type to use in fstab.
# For NTFS: prefers kernel ntfs3 driver (5.15+), falls back to ntfs-3g.
_mld_resolve_fstype() {
    local fstype="$1"
    case "$fstype" in
        ntfs)
            if grep -q '^[[:space:]]*ntfs3' /proc/filesystems 2>/dev/null; then
                echo "ntfs3"
            else
                echo "ntfs-3g"
            fi
            ;;
        *)
            echo "$fstype"
            ;;
    esac
}

# Ensure any userspace tools required by the chosen filesystem are present.
# Returns 1 if a hard dependency is missing and cannot be resolved.
_mld_ensure_fs_tools() {
    local fstype="$1"
    case "$fstype" in
        ntfs-3g)
            if ! command -v ntfs-3g &>/dev/null; then
                warn "ntfs-3g is not installed. Attempting to install..."
                case "$DISTRO_FAMILY" in
                    debian)  sudo apt-get install -y ntfs-3g ;;
                    fedora)  sudo "$PKG_MGR" install -y ntfs-3g ;;
                    rhel)    sudo "$PKG_MGR" install -y ntfs-3g ;;
                    arch)    sudo pacman -S --noconfirm ntfs-3g ;;
                    suse)    sudo zypper install -y ntfs-3g ;;
                    *)       warn "Cannot auto-install ntfs-3g on this distro. Install it manually."; return 1 ;;
                esac
            fi
            ;;
        exfat)
            if ! grep -q '^[[:space:]]*exfat' /proc/filesystems 2>/dev/null; then
                warn "exFAT support not loaded. Attempting to install exfatprogs..."
                case "$DISTRO_FAMILY" in
                    debian)  sudo apt-get install -y exfatprogs 2>/dev/null || \
                             sudo apt-get install -y exfat-utils 2>/dev/null || true ;;
                    fedora)  sudo "$PKG_MGR" install -y exfatprogs ;;
                    rhel)    sudo "$PKG_MGR" install -y exfatprogs 2>/dev/null || true ;;
                    arch)    sudo pacman -S --noconfirm exfatprogs ;;
                    suse)    sudo zypper install -y exfatprogs 2>/dev/null || true ;;
                    *)       warn "Cannot auto-install exfat support on this distro. Install it manually."; return 1 ;;
                esac
            fi
            ;;
    esac
    return 0
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_mount_local_drive() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Mount Local Drive                                              ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    # ── Step 1: Collect unmounted drives ──────────────────────────────────────
    info "Scanning for unmounted drives..."
    local -a entries=()
    mapfile -t entries < <(_mld_unmounted_list)

    if (( ${#entries[@]} == 0 )); then
        warn "No unmounted, formatted drives were found."
        info "All detected drives with filesystems are currently mounted."
        return 2
    fi

    # ── Step 2: Display drive table ───────────────────────────────────────────
    {
        printf '\n'
        printf '  %-4s  %-9s  %-7s  %-10s  %-22s  %s\n' \
            "#" "Device" "Size" "Type" "Label" "UUID"
        printf '  %s\n' \
            "────────────────────────────────────────────────────────────────────────────"
        local entry
        for entry in "${entries[@]}"; do
            IFS='|' read -r idx name uuid fstype label size <<< "$entry"
            local display_label="${label:-(no label)}"
            printf '  %-4s  %-9s  %-7s  %-10s  %-22s  %s\n' \
                "${idx})" "/dev/${name}" "$size" "$fstype" "$display_label" "$uuid"
        done
        printf '\n  0)    Cancel\n\n'
    } > /dev/tty

    # ── Step 3: Drive selection ───────────────────────────────────────────────
    local total=${#entries[@]}
    local -a selected=()
    while true; do
        read -rp "Select drives to mount [0 to cancel, e.g. 1  1,3,4  1-4]: " choice < /dev/tty
        choice="${choice// /}"
        if [[ "$choice" == "0" ]]; then
            info "Mount cancelled."
            return 0
        fi
        mapfile -t selected < <(_parse_multi_selection "$choice" "$total")
        if (( ${#selected[@]} == 0 )); then
            printf '%sInvalid selection. Use numbers 1-%d, commas, or ranges (e.g. 1,3  2-4).%s\n' \
                "${RED:-}" "$total" "${RESET:-}" > /dev/tty
            continue
        fi
        break
    done

    # ── Steps 4–11: Mount each selected drive ─────────────────────────────────
    local sel_idx _drive_num=0
    for sel_idx in "${selected[@]}"; do
        (( _drive_num++ )) || true

        local sel_entry="${entries[$((sel_idx - 1))]}"
        IFS='|' read -r _ sel_name sel_uuid sel_fstype sel_label _ <<< "$sel_entry"

        local fstab_fstype
        fstab_fstype=$(_mld_resolve_fstype "$sel_fstype")

        # ── Step 4: Drive header ──────────────────────────────────────────────
        {
            printf '\n'
            printf '  ════════════════════════════════════════════════════════════════════════════\n'
            printf '  Drive %d of %d: /dev/%s%s\n' \
                "$_drive_num" "${#selected[@]}" "$sel_name" "${sel_label:+  [${sel_label}]}"
            printf '  ════════════════════════════════════════════════════════════════════════════\n'
            printf '\n'
        } > /dev/tty

        # ── Step 5: Mount location ────────────────────────────────────────────
        local default_subfolder
        if [[ -n "$sel_label" ]]; then
            default_subfolder=$(printf '%s' "$sel_label" | tr -cs 'A-Za-z0-9._-' '_')
        else
            default_subfolder="$sel_name"
        fi

        local default_mount="/mnt/${default_subfolder}"
        {
            printf '  Enter the full path where this drive should be mounted.\n'
            printf '  Examples: /mnt/%s  or  /home/%s/mnt/%s\n' \
                "$default_subfolder" "$USER" "$default_subfolder"
            printf '  Press ENTER to use the default: %s\n\n' "$default_mount"
        } > /dev/tty

        local mount_point
        while true; do
            read -rp "Mount point [default: ${default_mount}]: " mount_point < /dev/tty

            [[ -z "$mount_point" ]] && mount_point="$default_mount"

            if [[ "$mount_point" != /* ]]; then
                printf '%sPath must be absolute (start with /).%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
                continue
            fi

            mount_point="${mount_point%/}"
            if [[ -z "$mount_point" ]]; then
                printf '%sCannot mount directly on /.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
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
            done <<< "${mount_point#/}/"

            if [[ "$_valid" == "false" ]]; then
                printf '%sEach path component must start with a letter or digit and contain only letters, numbers, underscores, hyphens, or dots.%s\n' \
                    "${RED:-}" "${RESET:-}" > /dev/tty
                continue
            fi

            break
        done

        # ── Step 6: Summary & confirmation ───────────────────────────────────
        {
            printf '\n'
            printf '  Device:      /dev/%s\n' "$sel_name"
            printf '  UUID:        %s\n'      "$sel_uuid"
            printf '  Filesystem:  %s\n'      "$fstab_fstype"
            printf '  Mount point: %s\n'      "$mount_point"
            printf '  fstab opts:  %s  %s\n'  "$(_mld_fstab_opts "$fstab_fstype")" "$(_mld_dump_pass "$fstab_fstype")"
            printf '\n'
        } > /dev/tty

        local confirm
        read -rp "Proceed? [y/N]: " confirm < /dev/tty
        if [[ "${confirm,,}" != "y" ]]; then
            info "Skipped /dev/${sel_name}."
            continue
        fi

        # ── Dry-run path ──────────────────────────────────────────────────────
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            if [[ "$mount_point" != "$HOME"* ]]; then
                info "[Dry run] Would create directory (as root, then chown to ${USER}): ${mount_point}"
            else
                info "[Dry run] Would create directory: ${mount_point}"
            fi
            info "[Dry run] Would back up /etc/fstab"
            info "[Dry run] Would append to /etc/fstab:"
            printf '  # linux_util:mount /dev/%s → %s\n' "$sel_name" "$mount_point"
            printf '  UUID=%s\t%s\t%s\t%s\t%s\n' \
                "$sel_uuid" "$mount_point" "$fstab_fstype" \
                "$(_mld_fstab_opts "$fstab_fstype")" "$(_mld_dump_pass "$fstab_fstype")"
            info "[Dry run] Would run: sudo mount ${mount_point}"
            continue
        fi

        # ── Step 7: Ensure filesystem tools are available ────────────────────
        _mld_ensure_fs_tools "$fstab_fstype" || { error "Missing FS tools for /dev/${sel_name}. Skipping."; continue; }

        # ── Step 8: Guard — check fstab for collisions ───────────────────────
        if grep -qsE "^UUID=${sel_uuid}[[:space:]]" /etc/fstab; then
            warn "UUID ${sel_uuid} already has an entry in /etc/fstab."
            local overwrite
            read -rp "Continue anyway and add a second entry? [y/N]: " overwrite < /dev/tty
            [[ "${overwrite,,}" != "y" ]] && { info "Skipped /dev/${sel_name}."; continue; }
        fi

        if grep -qsE "[[:space:]]${mount_point//\//\\/}[[:space:]]" /etc/fstab; then
            error "Mount point ${mount_point} is already present in /etc/fstab. Skipping."
            continue
        fi

        # ── Step 9: Create mount point directory ─────────────────────────────
        if [[ ! -d "$mount_point" ]]; then
            local _ancestor="$mount_point"
            while [[ ! -e "$_ancestor" ]]; do
                _ancestor=$(dirname "$_ancestor")
            done

            if [[ -w "$_ancestor" ]]; then
                mkdir -p "$mount_point" || { error "Failed to create directory: ${mount_point}. Skipping."; continue; }
            else
                run_as_root mkdir -p "$mount_point" || { error "Failed to create directory: ${mount_point}. Skipping."; continue; }
                if [[ "$mount_point" != "$HOME"* ]]; then
                    run_as_root chown "${USER}:${USER}" "$mount_point" || \
                        warn "Could not set ownership of ${mount_point} to ${USER} — you may need to access it as root."
                fi
            fi
            info "Created mount point: ${mount_point}"
        else
            info "Mount point already exists: ${mount_point}"
        fi

        # ── Step 10: Back up fstab ────────────────────────────────────────────
        local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
        run_as_root cp /etc/fstab "$fstab_backup" || { error "Failed to back up /etc/fstab"; return 1; }
        info "fstab backed up to ${fstab_backup}"

        # ── Step 11: Append fstab entry ───────────────────────────────────────
        local fstab_comment
        fstab_comment="# linux_util:mount /dev/${sel_name}${sel_label:+ (${sel_label})} → ${mount_point} — added $(date '+%Y-%m-%d %H:%M:%S')"

        local fstab_entry
        fstab_entry=$(printf 'UUID=%s\t%s\t%s\t%s\t%s' \
            "$sel_uuid" "$mount_point" "$fstab_fstype" \
            "$(_mld_fstab_opts "$fstab_fstype")" "$(_mld_dump_pass "$fstab_fstype")")

        printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
            | run_as_root tee -a /etc/fstab > /dev/null || {
            error "Failed to write to /etc/fstab. Restoring backup..."
            run_as_root cp "$fstab_backup" /etc/fstab
            return 1
        }

        # ── Step 12: Mount ────────────────────────────────────────────────────
        run_as_root mount "$mount_point" || {
            error "mount failed for ${mount_point}."
            warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${mount_point}"
            warn "If the device type is unsupported, install the required driver and retry."
            continue
        }

        echo ""
        info "Drive mounted successfully."
        info "  Device:      /dev/${sel_name}"
        info "  Mount point: ${mount_point}"
        info "  fstab entry: UUID=${sel_uuid} → ${mount_point} (${fstab_fstype})"
        info "  Backup:      ${fstab_backup}"
        echo ""
    done

    return 0
}

# ── Lifecycle stubs (task is run-on-demand, not idempotent) ───────────────────
check_mount_local_drive()     { return 1; }
uninstall_mount_local_drive() { return 0; }
update_mount_local_drive()    { setup_mount_local_drive; }
