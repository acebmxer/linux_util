#!/bin/bash
# Mount Manager — update or remove existing linux_util-managed fstab mounts.

# ── Shared helpers ────────────────────────────────────────────────────────────

# Outputs one record per linux_util-managed fstab entry:
#   INDEX|TYPE|SOURCE|MOUNT_POINT|FULL_ENTRY_LINE
_mmgr_list_entries() {
    [[ -f /etc/fstab ]] || return 0
    local idx=0
    local ptype="" psource="" pmount=""
    local pending=false

    while IFS= read -r line; do
        if [[ "$line" == "# linux_util:"* ]]; then
            local after_prefix="${line#'# linux_util:'}"
            ptype="${after_prefix%% *}"
            local rest="${after_prefix#"${ptype} "}"
            psource="${rest%% →*}"
            local after_arrow="${rest#*→ }"
            pmount="${after_arrow%% — added*}"
            pending=true
        elif [[ "$pending" == "true" && -n "$line" && "$line" != "#"* ]]; then
            (( idx++ )) || true
            printf '%d|%s|%s|%s|%s\n' "$idx" "$ptype" "$psource" "$pmount" "$line"
            pending=false
            ptype="" psource="" pmount=""
        fi
    done < /etc/fstab
}

_mmgr_display_table() {
    local -n _entries_ref=$1
    {
        printf '\n'
        printf '  %-4s  %-6s  %-38s  %s\n' "#" "Type" "Source" "Mount Point"
        printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────"
        local entry
        for entry in "${_entries_ref[@]}"; do
            IFS='|' read -r eidx etype esource emount _ <<< "$entry"
            printf '  %-4s  %-6s  %-38s  %s\n' "${eidx})" "$etype" "$esource" "$emount"
        done
        printf '\n  0)    Cancel\n\n'
    } > /dev/tty
}

_mmgr_backup_fstab() {
    local backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$backup" || { error "Failed to back up /etc/fstab"; return 1; }
    info "fstab backed up to ${backup}"
    printf '%s' "$backup"
}

# Replace the first tab-separated field in a fstab line
_mmgr_set_field1() {
    local line="$1" new_val="$2"
    local rest="${line#*$'\t'}"
    printf '%s\t%s' "$new_val" "$rest"
}

# Replace the second tab-separated field in a fstab line
_mmgr_set_field2() {
    local line="$1" new_val="$2"
    local f1="${line%%$'\t'*}"
    local rest="${line#*$'\t'}"
    local rest2="${rest#*$'\t'}"
    printf '%s\t%s\t%s' "$f1" "$new_val" "$rest2"
}

# ── Update Mount ──────────────────────────────────────────────────────────────

get_version_update_mount() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -c "^# linux_util:" /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} mount(s) managed via linux_util"
}

setup_update_mount() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Update Existing Mount                                          ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    local -a entries=()
    mapfile -t entries < <(_mmgr_list_entries)

    if (( ${#entries[@]} == 0 )); then
        warn "No linux_util-managed mounts found in /etc/fstab."
        return 2
    fi

    _mmgr_display_table entries

    local total=${#entries[@]}
    local choice
    while true; do
        read -rp "Select mount to update [0-${total}]: " choice < /dev/tty
        [[ "$choice" == "0" ]] && { info "Update cancelled."; return 0; }
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )) && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done

    local sel="${entries[$((choice - 1))]}"
    IFS='|' read -r _ sel_type sel_source sel_mount sel_entry <<< "$sel"

    printf '\n' > /dev/tty
    info "Selected: [${sel_type}] ${sel_source} → ${sel_mount}"
    printf '\n' > /dev/tty

    local new_source="$sel_source"
    local new_mount="$sel_mount"
    local new_creds_file=""
    local old_creds_file=""

    # ── Type-specific source fields ───────────────────────────────────────────
    case "$sel_type" in
        smb)
            local cur_server="${sel_source#//}"
            cur_server="${cur_server%%/*}"
            local cur_share="${sel_source#//${cur_server}/}"

            printf 'Current server IP/hostname : %s\n' "$cur_server" > /dev/tty
            local new_server
            read -rp "New server IP/hostname [Enter to keep]: " new_server < /dev/tty
            [[ -z "$new_server" ]] && new_server="$cur_server"
            new_server="${new_server// /}"

            printf 'Current share name         : %s\n' "$cur_share" > /dev/tty
            local new_share
            read -rp "New share name [Enter to keep]: " new_share < /dev/tty
            [[ -z "$new_share" ]] && new_share="$cur_share"
            new_share="${new_share// /}"

            new_source="//${new_server}/${new_share}"

            # Track credentials file rename if source changed
            if [[ "$new_source" != "$sel_source" ]]; then
                if [[ "$sel_entry" == *"credentials="* ]]; then
                    old_creds_file=$(printf '%s' "$sel_entry" | grep -oP 'credentials=\K[^,]+')
                    if [[ -n "$old_creds_file" && -f "$old_creds_file" ]]; then
                        new_creds_file="/etc/samba/credentials/$(printf '%s' "${new_server}_${new_share}" | tr -cs 'A-Za-z0-9._-' '_')"
                    fi
                fi
            fi
            ;;
        nfs)
            local cur_nfs_server="${sel_source%%:*}"
            local cur_export="${sel_source#*:}"

            printf 'Current server IP/hostname : %s\n' "$cur_nfs_server" > /dev/tty
            local new_nfs_server
            read -rp "New server IP/hostname [Enter to keep]: " new_nfs_server < /dev/tty
            [[ -z "$new_nfs_server" ]] && new_nfs_server="$cur_nfs_server"
            new_nfs_server="${new_nfs_server// /}"

            printf 'Current export path        : %s\n' "$cur_export" > /dev/tty
            local new_export
            read -rp "New export path [Enter to keep]: " new_export < /dev/tty
            [[ -z "$new_export" ]] && new_export="$cur_export"
            new_export="${new_export%/}"

            new_source="${new_nfs_server}:${new_export}"
            ;;
        mount)
            info "Local drive mounts are identified by UUID and cannot have their source changed here."
            info "Only the local mount folder name can be updated."
            ;;
    esac

    # ── Mount point ───────────────────────────────────────────────────────────
    local cur_mount_name="${sel_mount##*/}"
    local mount_base="${sel_mount%/*}"
    printf '\nCurrent local mount folder : %s\n' "$cur_mount_name" > /dev/tty
    local new_mount_name
    read -rp "New mount folder name [Enter to keep]: " new_mount_name < /dev/tty
    [[ -z "$new_mount_name" ]] && new_mount_name="$cur_mount_name"

    if [[ ! "$new_mount_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        error "Invalid mount folder name: ${new_mount_name}"
        return 1
    fi
    new_mount="${mount_base}/${new_mount_name}"

    # ── No-op check ───────────────────────────────────────────────────────────
    if [[ "$new_source" == "$sel_source" && "$new_mount" == "$sel_mount" ]]; then
        info "No changes specified."; return 0
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    {
        printf '\n'
        [[ "$new_source" != "$sel_source" ]] && printf '  Source:      %s  →  %s\n' "$sel_source" "$new_source"
        [[ "$new_mount"  != "$sel_mount"  ]] && printf '  Mount point: %s  →  %s\n' "$sel_mount"  "$new_mount"
        printf '\n'
    } > /dev/tty

    local confirm
    read -rp "Proceed? [y/N]: " confirm < /dev/tty
    [[ "${confirm,,}" != "y" ]] && { info "Update cancelled."; return 0; }

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[Dry run] Would update fstab entry."
        return 0
    fi

    # ── Unmount if currently active ───────────────────────────────────────────
    if mountpoint -q "$sel_mount" 2>/dev/null; then
        info "Unmounting ${sel_mount}..."
        run_as_root umount "$sel_mount" || {
            error "Failed to unmount ${sel_mount}. Aborting update."
            return 1
        }
    fi

    # ── Back up fstab ─────────────────────────────────────────────────────────
    local backup
    backup=$(_mmgr_backup_fstab) || return 1

    # ── Copy credentials file if needed (SMB) ─────────────────────────────────
    if [[ -n "$old_creds_file" && -n "$new_creds_file" && "$old_creds_file" != "$new_creds_file" ]]; then
        run_as_root cp "$old_creds_file" "$new_creds_file"
        run_as_root chmod 600 "$new_creds_file"
        info "Credentials file copied: ${old_creds_file} → ${new_creds_file}"
    fi

    # ── Rewrite fstab ─────────────────────────────────────────────────────────
    local tmpfile
    tmpfile=$(mktemp)
    CLEANUP_FILES+=("$tmpfile")

    local comment_marker="# linux_util:${sel_type} ${sel_source} "
    local skip_next=false
    local found=false

    while IFS= read -r line; do
        if [[ "$line" == "${comment_marker}"* ]]; then
            found=true
            skip_next=true
            local new_comment="# linux_util:${sel_type} ${new_source} → ${new_mount} — added $(date '+%Y-%m-%d %H:%M:%S')"
            printf '%s\n' "$new_comment" >> "$tmpfile"
        elif [[ "$skip_next" == "true" && -n "$line" && "$line" != "#"* ]]; then
            skip_next=false
            local new_entry="$line"
            # Update source (first field)
            [[ "$new_source" != "$sel_source" ]] && new_entry=$(_mmgr_set_field1 "$new_entry" "$new_source")
            # Update mount point (second field)
            [[ "$new_mount" != "$sel_mount" ]] && new_entry=$(_mmgr_set_field2 "$new_entry" "$new_mount")
            # Update credentials file reference in options (fourth field, SMB only)
            if [[ -n "$old_creds_file" && -n "$new_creds_file" && "$old_creds_file" != "$new_creds_file" ]]; then
                new_entry="${new_entry//${old_creds_file}/${new_creds_file}}"
            fi
            printf '%s\n' "$new_entry" >> "$tmpfile"
        else
            printf '%s\n' "$line" >> "$tmpfile"
        fi
    done < /etc/fstab

    if [[ "$found" == "false" ]]; then
        error "Could not find the fstab entry to update."
        run_as_root cp "$backup" /etc/fstab
        rm -f "$tmpfile"
        return 1
    fi

    run_as_root cp "$tmpfile" /etc/fstab || {
        error "Failed to write updated fstab. Restoring backup..."
        run_as_root cp "$backup" /etc/fstab
        return 1
    }

    # ── Update mount directories ──────────────────────────────────────────────
    if [[ "$new_mount" != "$sel_mount" ]]; then
        mkdir -p "$new_mount" || { error "Failed to create directory: ${new_mount}"; return 1; }
        info "Created new mount point: ${new_mount}"
        rmdir "$sel_mount" 2>/dev/null && info "Removed old mount point: ${sel_mount}" || true
    fi

    # ── Remount ───────────────────────────────────────────────────────────────
    run_as_root mount "$new_mount" || {
        warn "Remount failed. Check /etc/fstab and try: sudo mount ${new_mount}"
    }

    echo ""
    info "Mount updated successfully."
    [[ "$new_source" != "$sel_source" ]] && info "  Source:      ${sel_source} → ${new_source}"
    [[ "$new_mount"  != "$sel_mount"  ]] && info "  Mount point: ${sel_mount} → ${new_mount}"
    info "  Backup:      ${backup}"
    echo ""
    return 0
}

check_update_mount()     { return 1; }
uninstall_update_mount() { return 0; }
update_update_mount()    { setup_update_mount; }

# ── Unmount Share ─────────────────────────────────────────────────────────────

get_version_unmount_share() {
    get_version_update_mount
}

setup_unmount_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Unmount / Remove Share                                         ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    local -a entries=()
    mapfile -t entries < <(_mmgr_list_entries)

    if (( ${#entries[@]} == 0 )); then
        warn "No linux_util-managed mounts found in /etc/fstab."
        return 2
    fi

    _mmgr_display_table entries

    local total=${#entries[@]}
    local choice
    while true; do
        read -rp "Select mount to remove [0-${total}]: " choice < /dev/tty
        [[ "$choice" == "0" ]] && { info "Unmount cancelled."; return 0; }
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )) && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done

    local sel="${entries[$((choice - 1))]}"
    IFS='|' read -r _ sel_type sel_source sel_mount _ <<< "$sel"

    {
        printf '\n'
        printf '  Type:        %s\n' "$sel_type"
        printf '  Source:      %s\n' "$sel_source"
        printf '  Mount point: %s\n' "$sel_mount"
        printf '\n'
    } > /dev/tty

    local confirm
    read -rp "Remove this mount from fstab? [y/N]: " confirm < /dev/tty
    [[ "${confirm,,}" != "y" ]] && { info "Unmount cancelled."; return 0; }

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[Dry run] Would unmount ${sel_mount} and remove from /etc/fstab."
        return 0
    fi

    # ── Unmount if active ─────────────────────────────────────────────────────
    if mountpoint -q "$sel_mount" 2>/dev/null; then
        info "Unmounting ${sel_mount}..."
        if ! run_as_root umount "$sel_mount"; then
            error "Failed to unmount ${sel_mount}."
            local force_ans
            read -rp "Continue removing from fstab anyway? [y/N]: " force_ans < /dev/tty
            [[ "${force_ans,,}" != "y" ]] && return 1
        fi
    else
        info "Not currently mounted — proceeding with fstab removal."
    fi

    # ── Back up fstab ─────────────────────────────────────────────────────────
    local backup
    backup=$(_mmgr_backup_fstab) || return 1

    # ── Remove entry from fstab ───────────────────────────────────────────────
    local tmpfile
    tmpfile=$(mktemp)
    CLEANUP_FILES+=("$tmpfile")

    local comment_marker="# linux_util:${sel_type} ${sel_source} "
    local skip_entry=false
    local found=false
    local -a buf=()

    while IFS= read -r line; do
        if [[ "$line" == "${comment_marker}"* ]]; then
            found=true
            # Remove preceding blank line from buffer
            if (( ${#buf[@]} > 0 )) && [[ -z "${buf[-1]}" ]]; then
                unset 'buf[-1]'
            fi
            for bl in "${buf[@]}"; do printf '%s\n' "$bl" >> "$tmpfile"; done
            buf=()
            skip_entry=true
        elif [[ "$skip_entry" == "true" && -n "$line" && "$line" != "#"* ]]; then
            skip_entry=false
            # This is the fstab entry line — skip it (do not write to tmpfile)
        else
            buf+=("$line")
        fi
    done < /etc/fstab

    for bl in "${buf[@]}"; do printf '%s\n' "$bl" >> "$tmpfile"; done

    if [[ "$found" == "false" ]]; then
        error "Could not find the fstab entry to remove."
        rm -f "$tmpfile"
        return 1
    fi

    run_as_root cp "$tmpfile" /etc/fstab || {
        error "Failed to write updated fstab. Restoring backup..."
        run_as_root cp "$backup" /etc/fstab
        return 1
    }
    info "Removed from /etc/fstab."

    # ── Optionally remove mount directory ─────────────────────────────────────
    if [[ -d "$sel_mount" ]]; then
        local rm_ans
        read -rp "Remove mount directory ${sel_mount}? [y/N]: " rm_ans < /dev/tty
        if [[ "${rm_ans,,}" == "y" ]]; then
            if rmdir "$sel_mount" 2>/dev/null; then
                info "Removed directory: ${sel_mount}"
            else
                warn "Directory not empty or could not be removed: ${sel_mount}"
            fi
        fi
    fi

    # ── Remove SMB credentials file if no longer needed ───────────────────────
    if [[ "$sel_type" == "smb" ]]; then
        # Only offer to remove if no other fstab entry references it
        local creds_file
        creds_file="/etc/samba/credentials/$(printf '%s' "${sel_source#//}" | tr '/' '_' | tr -cs 'A-Za-z0-9._-' '_')"
        if [[ -f "$creds_file" ]] && ! grep -qsF "credentials=${creds_file}" /etc/fstab 2>/dev/null; then
            local creds_ans
            read -rp "Remove credentials file ${creds_file}? [y/N]: " creds_ans < /dev/tty
            [[ "${creds_ans,,}" == "y" ]] && run_as_root rm -f "$creds_file" && info "Removed credentials file."
        fi
    fi

    echo ""
    info "Mount removed successfully."
    info "  Source:  ${sel_source}"
    info "  Backup:  ${backup}"
    echo ""
    return 0
}

check_unmount_share()     { return 1; }
uninstall_unmount_share() { return 0; }
update_unmount_share()    { setup_unmount_share; }
