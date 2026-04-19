#!/bin/bash
# Unmount Share — interactively select and remove a linux_util-managed mount:
# unmounts the share, removes the mount point directory, clears the fstab entry,
# and removes the KDE Dolphin Places entry if present.

# ── Version / status ──────────────────────────────────────────────────────────
get_version_unmount_share() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -cE '^# linux_util:(nfs|smb|mount) ' /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} linux_util-managed mount(s)"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Output one pipe-delimited record per linux_util-managed fstab entry:
#   INDEX|TYPE|SOURCE|MOUNT_POINT|FSTYPE|MOUNTED
_ums_managed_list() {
    local idx=0
    local prev_type=""
    local in_entry=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^#\ linux_util:(nfs|smb|mount)\  ]]; then
            prev_type="${BASH_REMATCH[1]}"
            in_entry=true
        elif [[ "$in_entry" == true && ! "$line" =~ ^# && -n "$line" ]]; then
            local source mount_point fstype
            source=$(awk '{print $1}' <<< "$line")
            mount_point=$(awk '{print $2}' <<< "$line")
            fstype=$(awk '{print $3}' <<< "$line")
            local mounted="no"
            findmnt -n "$mount_point" &>/dev/null && mounted="yes"
            (( idx++ )) || true
            printf '%d|%s|%s|%s|%s|%s\n' "$idx" "$prev_type" "$source" "$mount_point" "$fstype" "$mounted"
            in_entry=false
            prev_type=""
        else
            in_entry=false
            prev_type=""
        fi
    done < /etc/fstab
}

# Remove the comment + fstab entry for a given mount point.
# Reads fstab as current user, writes back as root via tee.
_ums_remove_fstab() {
    local mount_point="$1"
    local new_content
    new_content=$(python3 - /etc/fstab "$mount_point" <<'PYEOF'
import sys, re
path, mp = sys.argv[1], sys.argv[2]
with open(path) as f:
    lines = f.readlines()
new_lines = []
i = 0
while i < len(lines):
    if re.match(r'^# linux_util:(nfs|smb|mount) ', lines[i]) and i + 1 < len(lines):
        fields = lines[i + 1].split()
        if len(fields) >= 2 and fields[1] == mp:
            if new_lines and new_lines[-1].strip() == '':
                new_lines.pop()
            i += 2
            continue
    new_lines.append(lines[i])
    i += 1
sys.stdout.write(''.join(new_lines))
PYEOF
    ) || { error "Failed to process /etc/fstab"; return 1; }
    printf '%s' "$new_content" | run_as_root tee /etc/fstab > /dev/null
}

# Remove the KDE Places separator entry for a given mount point.
_ums_remove_kde_place() {
    local mount_point="$1"
    local places_file="${HOME}/.local/share/user-places.xbel"
    [[ -f "$places_file" ]] || return 0
    grep -qF "$mount_point" "$places_file" || return 0
    python3 - "$places_file" "$mount_point" <<'PYEOF'
import sys, re
path, mp = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
pattern = (
    r'\s*<separator>\s*<info>\s*<metadata owner="http://www\.kde\.org">'
    r'\s*<UDI>[^<]*' + re.escape(mp) + r'[^<]*</UDI>'
    r'\s*<isSystemItem>true</isSystemItem>'
    r'\s*</metadata>\s*</info>\s*</separator>'
)
with open(path, 'w') as f:
    f.write(re.sub(pattern, '', content))
PYEOF
    info "Removed KDE Places entry for ${mount_point}"
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_unmount_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Unmount Share                                                  ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    # ── Step 1: Collect managed mounts ───────────────────────────────────────
    local -a entries=()
    mapfile -t entries < <(_ums_managed_list)

    if (( ${#entries[@]} == 0 )); then
        warn "No linux_util-managed mounts found in /etc/fstab."
        return 0
    fi

    # ── Step 2: Display table ─────────────────────────────────────────────────
    {
        printf '\n'
        printf '  %-4s  %-12s  %-8s  %-34s  %s\n' "#" "Status" "Type" "Source" "Mount Point"
        printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────────────"
        local entry
        for entry in "${entries[@]}"; do
            IFS='|' read -r idx type source mount_point fstype mounted <<< "$entry"
            local status_label type_label
            [[ "$mounted" == "yes" ]] && status_label="[mounted]" || status_label="[unmounted]"
            case "$type" in
                nfs) type_label="NFS" ;;
                smb) type_label="SMB" ;;
                *)   type_label="$fstype" ;;
            esac
            printf '  %-4s  %-12s  %-8s  %-34s  %s\n' \
                "${idx})" "$status_label" "$type_label" "$source" "$mount_point"
        done
        printf '\n  0)    Cancel\n\n'
    } > /dev/tty

    # ── Step 3: Selection ─────────────────────────────────────────────────────
    local total=${#entries[@]}
    local choice
    while true; do
        read -rp "Select share to unmount [0-${total}]: " choice < /dev/tty
        if [[ "$choice" == "0" ]]; then
            info "Cancelled."
            return 0
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
            break
        fi
        printf '%sInvalid selection. Enter a number between 0 and %d.%s\n' \
            "${RED:-}" "$total" "${RESET:-}" > /dev/tty
    done

    local sel_entry="${entries[$((choice - 1))]}"
    IFS='|' read -r _ sel_type sel_source sel_mount_point _ sel_mounted <<< "$sel_entry"

    # ── Step 4: Confirmation ──────────────────────────────────────────────────
    {
        printf '\n'
        printf '  Source:      %s\n' "$sel_source"
        printf '  Mount point: %s\n' "$sel_mount_point"
        printf '  Status:      %s\n' "$([[ "$sel_mounted" == "yes" ]] && echo "currently mounted" || echo "not mounted")"
        printf '\n  This will unmount, remove the directory, and delete the fstab entry.\n\n'
    } > /dev/tty

    local confirm
    read -rp "Proceed? [y/N]: " confirm < /dev/tty
    [[ "${confirm,,}" != "y" ]] && { info "Cancelled."; return 0; }

    # ── Dry-run path ──────────────────────────────────────────────────────────
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        [[ "$sel_mounted" == "yes" ]] && info "[Dry run] Would run: sudo umount ${sel_mount_point}"
        info "[Dry run] Would remove fstab entry for ${sel_mount_point}"
        info "[Dry run] Would rmdir ${sel_mount_point}"
        [[ "$sel_type" == "nfs" || "$sel_type" == "smb" ]] && info "[Dry run] Would remove KDE Places entry"
        return 0
    fi

    # ── Step 5: Back up fstab ─────────────────────────────────────────────────
    local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$fstab_backup" || {
        error "Failed to back up /etc/fstab"
        return 1
    }
    info "fstab backed up to ${fstab_backup}"

    # ── Step 6: Unmount ───────────────────────────────────────────────────────
    if [[ "$sel_mounted" == "yes" ]]; then
        run_as_root umount "$sel_mount_point" || {
            error "umount failed for ${sel_mount_point}. Aborting."
            return 1
        }
        info "Unmounted ${sel_mount_point}"
    fi

    # ── Step 7: Remove fstab entry ────────────────────────────────────────────
    _ums_remove_fstab "$sel_mount_point" || return 1
    info "Removed fstab entry for ${sel_mount_point}"

    # ── Step 8: Remove mount point directory ──────────────────────────────────
    if [[ -d "$sel_mount_point" ]]; then
        if run_as_root rmdir "$sel_mount_point" 2>/dev/null; then
            info "Removed directory ${sel_mount_point}"
        else
            warn "Directory ${sel_mount_point} is not empty — left in place."
        fi
    fi

    # ── Step 9: Remove KDE Places entry ──────────────────────────────────────
    _ums_remove_kde_place "$sel_mount_point"

    echo ""
    info "Share unmounted and removed successfully."
    info "  Source:  ${sel_source}"
    info "  Backup:  ${fstab_backup}"
    echo ""
    return 0
}

# ── Lifecycle stubs ───────────────────────────────────────────────────────────
check_unmount_share()     { return 1; }
uninstall_unmount_share() { return 0; }
update_unmount_share()    { setup_unmount_share; }
