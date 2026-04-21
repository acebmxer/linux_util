#!/bin/bash
# Update Mount — interactively modify an existing linux_util-managed NFS or
# local disk mount: change server, share, or mount location, then re-mount.

# ── Version / status ──────────────────────────────────────────────────────────
get_version_update_mount() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -cE '^# linux_util:(nfs|smb|mount) ' /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} linux_util-managed mount(s)"
}

# ── Shared helper: prompt user for a full absolute mount point path ───────────
# Accepts an optional hint for the default path suffix (e.g. "docker-data").
# Prints the resolved absolute mount point to stdout.
_um_prompt_mount_point() {
    local default_subfolder="$1"
    local default_mount="/mnt/${default_subfolder}"
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
    printf '%s' "$mount_point"
}

# ── Shared helper: create a mount point directory, using sudo when needed ─────
# Hands ownership to the current user when the path is outside $HOME.
_um_create_mount_point() {
    local dir="$1"
    [[ -d "$dir" ]] && return 0

    local _ancestor="$dir"
    while [[ ! -e "$_ancestor" ]]; do
        _ancestor=$(dirname "$_ancestor")
    done

    if [[ -w "$_ancestor" ]]; then
        mkdir -p "$dir" || { error "Failed to create directory: ${dir}"; return 1; }
    else
        run_as_root mkdir -p "$dir" || { error "Failed to create directory: ${dir}"; return 1; }
        if [[ "$dir" != "$HOME"* ]]; then
            run_as_root chown "${USER}:${USER}" "$dir" || \
                warn "Could not set ownership of ${dir} to ${USER} — you may need to access it as root."
        fi
    fi
    info "Created mount point: ${dir}"
}

# ── NFS update branch ─────────────────────────────────────────────────────────
_um_update_nfs() {
    local sel_source="$1"        # e.g. 10.0.0.1:/exports/data
    local sel_mount_point="$2"
    local sel_mounted="$3"       # yes / no

    local cur_server cur_share
    cur_server="${sel_source%%:*}"
    cur_share="${sel_source#*:}"

    {
        printf '\n  Current NFS mount:\n'
        printf '    Server:      %s\n'       "$cur_server"
        printf '    Share:       %s\n'       "$cur_share"
        printf '    Mount point: %s\n'       "$sel_mount_point"
        printf '    Status:      %s\n\n'     "$([[ "$sel_mounted" == "yes" ]] && echo "mounted" || echo "not mounted")"
        printf '  What would you like to change?\n\n'
        printf '  1)  Server (IP / hostname)\n'
        printf '  2)  Share (NFS export path)\n'
        printf '  3)  Mount location\n'
        printf '  4)  All (full re-setup)\n'
        printf '  0)  Cancel\n\n'
    } > /dev/tty

    local what_choice
    while true; do
        read -rp "Select [0-4]: " what_choice < /dev/tty
        [[ "$what_choice" =~ ^[0-4]$ ]] && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done
    [[ "$what_choice" == "0" ]] && { info "Cancelled."; return 0; }

    local new_server new_share new_mount_point

    # ── Collect new values ────────────────────────────────────────────────────
    case "$what_choice" in
        1)  # Change server only — keep same share path and mount location
            while true; do
                read -rp "New NFS server IP or hostname [current: ${cur_server}]: " new_server < /dev/tty
                new_server="${new_server// /}"
                [[ -z "$new_server" ]] && new_server="$cur_server"
                [[ -n "$new_server" ]] && break
                printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done
            new_share="$cur_share"
            new_mount_point="$sel_mount_point"
            ;;

        2)  # Change share — query exports from the current server
            new_server="$cur_server"
            new_mount_point="$sel_mount_point"
            info "Querying NFS exports from ${new_server}..."
            local -a nfs_exports=()
            mapfile -t nfs_exports < <(_mns_export_list "$new_server")
            if (( ${#nfs_exports[@]} == 0 )); then
                error "No NFS exports found on ${new_server}."
                return 1
            fi
            {
                printf '\n'
                printf '  %-4s  %-35s  %s\n' "#" "Export Path" "Allowed Clients"
                printf '  %s\n' "────────────────────────────────────────────────────────────────────────────"
                local export_entry
                for export_entry in "${nfs_exports[@]}"; do
                    IFS='|' read -r idx export_path clients <<< "$export_entry"
                    printf '  %-4s  %-35s  %s\n' "${idx})" "$export_path" "$clients"
                done
                printf '\n  0)    Cancel\n\n'
            } > /dev/tty
            local share_total=${#nfs_exports[@]}
            local share_choice
            while true; do
                read -rp "Select new share [0-${share_total}]: " share_choice < /dev/tty
                [[ "$share_choice" == "0" ]] && { info "Cancelled."; return 0; }
                if [[ "$share_choice" =~ ^[0-9]+$ ]] && (( share_choice >= 1 && share_choice <= share_total )); then
                    break
                fi
                printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done
            IFS='|' read -r _ new_share _ <<< "${nfs_exports[$((share_choice - 1))]}"
            ;;

        3)  # Change mount location — keep same server and share
            new_server="$cur_server"
            new_share="$cur_share"
            local default_mp
            default_mp=$(basename "$new_share" | tr -cs 'A-Za-z0-9._-' '_')
            default_mp="${default_mp%_}"
            [[ -z "$default_mp" || "$default_mp" == "_" ]] && default_mp="nfs"
            {
                printf '\n  Specify a new mount location.\n'
                printf '  Current: %s\n\n' "$sel_mount_point"
            } > /dev/tty
            new_mount_point=$(_um_prompt_mount_point "$default_mp")
            if [[ "$new_mount_point" == "$sel_mount_point" ]]; then
                warn "New mount point is the same as the current one. Nothing to do."
                return 0
            fi
            ;;

        4)  # Full re-setup — prompt server, then pick share, then mount location
            while true; do
                read -rp "NFS server IP or hostname [current: ${cur_server}]: " new_server < /dev/tty
                new_server="${new_server// /}"
                [[ -z "$new_server" ]] && new_server="$cur_server"
                [[ -n "$new_server" ]] && break
                printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done
            info "Querying NFS exports from ${new_server}..."
            local -a nfs_exports=()
            mapfile -t nfs_exports < <(_mns_export_list "$new_server")
            if (( ${#nfs_exports[@]} == 0 )); then
                error "No NFS exports found on ${new_server}."
                return 1
            fi
            {
                printf '\n'
                printf '  %-4s  %-35s  %s\n' "#" "Export Path" "Allowed Clients"
                printf '  %s\n' "────────────────────────────────────────────────────────────────────────────"
                for export_entry in "${nfs_exports[@]}"; do
                    IFS='|' read -r idx export_path clients <<< "$export_entry"
                    printf '  %-4s  %-35s  %s\n' "${idx})" "$export_path" "$clients"
                done
                printf '\n  0)    Cancel\n\n'
            } > /dev/tty
            local share_total=${#nfs_exports[@]}
            local share_choice
            while true; do
                read -rp "Select share [0-${share_total}]: " share_choice < /dev/tty
                [[ "$share_choice" == "0" ]] && { info "Cancelled."; return 0; }
                if [[ "$share_choice" =~ ^[0-9]+$ ]] && (( share_choice >= 1 && share_choice <= share_total )); then
                    break
                fi
                printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done
            IFS='|' read -r _ new_share _ <<< "${nfs_exports[$((share_choice - 1))]}"
            local default_mp
            default_mp=$(basename "$new_share" | tr -cs 'A-Za-z0-9._-' '_')
            default_mp="${default_mp%_}"
            [[ -z "$default_mp" || "$default_mp" == "_" ]] && default_mp="nfs"
            {
                printf '\n  Specify a mount location.\n'
                printf '  Current: %s\n\n' "$sel_mount_point"
            } > /dev/tty
            new_mount_point=$(_um_prompt_mount_point "$default_mp")
            ;;
    esac

    local new_source="${new_server}:${new_share}"
    local fstab_opts="defaults,nofail,_netdev"

    # ── Summary & confirmation ────────────────────────────────────────────────
    {
        printf '\n  Proposed changes:\n'
        printf '    Old source:  %s\n'   "$sel_source"
        printf '    New source:  %s\n'   "$new_source"
        printf '    Old mount:   %s\n'   "$sel_mount_point"
        printf '    New mount:   %s\n'   "$new_mount_point"
        printf '\n  The old share will be unmounted and remounted with the new settings.\n\n'
    } > /dev/tty
    local confirm
    while true; do
        read -rp "Proceed? [y/N]: " confirm < /dev/tty
        case "${confirm,,}" in
            y) break ;;
            n|'') info "Cancelled."; return 0 ;;
            *) printf '%sPlease enter y or n.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty ;;
        esac
    done

    # ── Dry-run ───────────────────────────────────────────────────────────────
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        [[ "$sel_mounted" == "yes" ]] && info "[Dry run] Would unmount ${sel_mount_point}"
        info "[Dry run] Would remove fstab entry for ${sel_mount_point}"
        [[ "$sel_mount_point" != "$new_mount_point" ]] && info "[Dry run] Would rmdir ${sel_mount_point}"
        info "[Dry run] Would create directory ${new_mount_point}"
        info "[Dry run] Would write fstab: ${new_source} → ${new_mount_point} (${fstab_opts})"
        info "[Dry run] Would run: sudo mount ${new_mount_point}"
        return 0
    fi

    # ── Back up fstab ─────────────────────────────────────────────────────────
    local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$fstab_backup" || { error "Failed to back up /etc/fstab"; return 1; }
    info "fstab backed up to ${fstab_backup}"

    # ── Unmount old ───────────────────────────────────────────────────────────
    if [[ "$sel_mounted" == "yes" ]]; then
        run_as_root umount "$sel_mount_point" || { error "umount failed for ${sel_mount_point}. Aborting."; return 1; }
        info "Unmounted ${sel_mount_point}"
    fi

    # ── Remove KDE Places entry for old mount ─────────────────────────────────
    _ums_remove_kde_place "$sel_mount_point"

    # ── Remove old fstab entry ────────────────────────────────────────────────
    _ums_remove_fstab "$sel_mount_point" || {
        error "Failed to remove old fstab entry. Restoring backup..."
        run_as_root cp "$fstab_backup" /etc/fstab
        return 1
    }
    info "Removed old fstab entry"

    # ── Remove old mount point directory (only when location changed) ─────────
    if [[ "$sel_mount_point" != "$new_mount_point" && -d "$sel_mount_point" ]]; then
        if run_as_root rmdir "$sel_mount_point" 2>/dev/null; then
            info "Removed directory ${sel_mount_point}"
        else
            warn "Directory ${sel_mount_point} is not empty — left in place."
        fi
    fi

    # ── Create new mount point ────────────────────────────────────────────────
    _um_create_mount_point "$new_mount_point" || return 1

    # ── Write new fstab entry ─────────────────────────────────────────────────
    local fstab_comment="# linux_util:nfs ${new_source} → ${new_mount_point} — updated $(date '+%Y-%m-%d %H:%M:%S')"
    local fstab_entry
    fstab_entry=$(printf '%s\t%s\tnfs\t%s\t0 0' "$new_source" "$new_mount_point" "$fstab_opts")
    printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
        | run_as_root tee -a /etc/fstab > /dev/null || {
        error "Failed to write to /etc/fstab. Restoring backup..."
        run_as_root cp "$fstab_backup" /etc/fstab
        return 1
    }

    # ── Mount ─────────────────────────────────────────────────────────────────
    run_as_root mount "$new_mount_point" || {
        error "mount failed for ${new_mount_point}."
        warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${new_mount_point}"
        return 1
    }

    _mns_add_kde_place "$new_source" "$new_mount_point"

    echo ""
    info "NFS mount updated successfully."
    info "  Source:      ${new_source}"
    info "  Mount point: ${new_mount_point}"
    info "  Backup:      ${fstab_backup}"
    echo ""
    return 0
}

# ── SMB update branch ────────────────────────────────────────────────────────
_um_update_smb() {
    local sel_source="$1"        # e.g. //10.0.0.1/data
    local sel_mount_point="$2"
    local sel_mounted="$3"       # yes / no

    local cur_server cur_share
    cur_server="${sel_source#//}"
    cur_server="${cur_server%%/*}"
    cur_share="${sel_source#//${cur_server}/}"

    local cur_creds_file
    cur_creds_file=$(_msb_creds_path "$cur_server")

    {
        printf '\n  Current SMB mount:\n'
        printf '    Server:      %s\n'   "$cur_server"
        printf '    Share:       %s\n'   "$cur_share"
        printf '    Mount point: %s\n'   "$sel_mount_point"
        printf '    Status:      %s\n\n' "$([[ "$sel_mounted" == "yes" ]] && echo "mounted" || echo "not mounted")"
        printf '  What would you like to change?\n\n'
        printf '  1)  Server (IP / hostname)\n'
        printf '  2)  Share\n'
        printf '  3)  Credentials (username / password)\n'
        printf '  4)  Mount location\n'
        printf '  5)  All (full re-setup)\n'
        printf '  0)  Cancel\n\n'
    } > /dev/tty

    local what_choice
    while true; do
        read -rp "Select [0-5]: " what_choice < /dev/tty
        [[ "$what_choice" =~ ^[0-5]$ ]] && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done
    [[ "$what_choice" == "0" ]] && { info "Cancelled."; return 0; }

    local new_server new_share new_username new_password new_mount_point

    # Prompt for updated credentials, falling back to values in the existing creds file.
    _um_smb_prompt_creds() {
        local _cur_creds="$1"
        local _cur_user=""
        [[ -f "$_cur_creds" ]] && _cur_user=$(grep '^username=' "$_cur_creds" | cut -d= -f2-)
        while true; do
            read -rp "Username [current: ${_cur_user:-none}]: " new_username < /dev/tty
            new_username="${new_username// /}"
            [[ -z "$new_username" ]] && new_username="$_cur_user"
            [[ -n "$new_username" ]] && break
            printf '%sUsername cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
        done
        read -rsp "Password (hidden, press ENTER to keep current): " new_password < /dev/tty
        printf '\n' > /dev/tty
        if [[ -z "$new_password" && -f "$_cur_creds" ]]; then
            new_password=$(grep '^password=' "$_cur_creds" | cut -d= -f2-)
        fi
    }

    # List shares and let the user pick one; sets new_share on success, returns 1 on cancel.
    _um_smb_pick_share() {
        local _srv="$1" _user="$2" _pass="$3"
        info "Querying SMB shares on ${_srv}..."
        local -a _shares=()
        mapfile -t _shares < <(_msb_share_list "$_srv" "$_user" "$_pass")
        if (( ${#_shares[@]} == 0 )); then
            error "No accessible SMB shares found on ${_srv}."
            return 1
        fi
        {
            printf '\n'
            printf '  %-4s  %s\n' "#" "Share Name"
            printf '  %s\n' "────────────────────────────────────────"
            local _e
            for _e in "${_shares[@]}"; do
                IFS='|' read -r _i _n <<< "$_e"
                printf '  %-4s  %s\n' "${_i})" "$_n"
            done
            printf '\n  0)    Cancel\n\n'
        } > /dev/tty
        local _total=${#_shares[@]} _c
        while true; do
            read -rp "Select share [0-${_total}]: " _c < /dev/tty
            [[ "$_c" == "0" ]] && return 1
            if [[ "$_c" =~ ^[0-9]+$ ]] && (( _c >= 1 && _c <= _total )); then break; fi
            printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
        done
        IFS='|' read -r _ new_share <<< "${_shares[$(( _c - 1))]}"
    }

    case "$what_choice" in
        1)  # Change server — re-prompt credentials and pick share from new server
            while true; do
                read -rp "New SMB server IP or hostname [current: ${cur_server}]: " new_server < /dev/tty
                new_server="${new_server// /}"
                [[ -z "$new_server" ]] && new_server="$cur_server"
                [[ -n "$new_server" ]] && break
                printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done
            _um_smb_prompt_creds "$cur_creds_file"
            _um_smb_pick_share "$new_server" "$new_username" "$new_password" || { info "Cancelled."; return 0; }
            new_mount_point="$sel_mount_point"
            ;;

        2)  # Change share only — reuse current server and credentials
            new_server="$cur_server"
            new_mount_point="$sel_mount_point"
            local cur_user="" cur_pass=""
            [[ -f "$cur_creds_file" ]] && cur_user=$(grep '^username=' "$cur_creds_file" | cut -d= -f2-)
            [[ -f "$cur_creds_file" ]] && cur_pass=$(grep '^password=' "$cur_creds_file" | cut -d= -f2-)
            new_username="$cur_user"
            new_password="$cur_pass"
            _um_smb_pick_share "$new_server" "$new_username" "$new_password" || { info "Cancelled."; return 0; }
            ;;

        3)  # Change credentials only
            new_server="$cur_server"
            new_share="$cur_share"
            new_mount_point="$sel_mount_point"
            _um_smb_prompt_creds "$cur_creds_file"
            ;;

        4)  # Change mount location
            new_server="$cur_server"
            new_share="$cur_share"
            local cur_user="" cur_pass=""
            [[ -f "$cur_creds_file" ]] && cur_user=$(grep '^username=' "$cur_creds_file" | cut -d= -f2-)
            [[ -f "$cur_creds_file" ]] && cur_pass=$(grep '^password=' "$cur_creds_file" | cut -d= -f2-)
            new_username="$cur_user"
            new_password="$cur_pass"
            local default_mp
            default_mp=$(printf '%s' "$new_share" | tr -cs 'A-Za-z0-9._-' '_')
            default_mp="${default_mp%_}"
            [[ -z "$default_mp" || "$default_mp" == "_" ]] && default_mp="smb"
            {
                printf '\n  Specify a new mount location.\n'
                printf '  Current: %s\n\n' "$sel_mount_point"
            } > /dev/tty
            new_mount_point=$(_um_prompt_mount_point "$default_mp")
            if [[ "$new_mount_point" == "$sel_mount_point" ]]; then
                warn "New mount point is the same as the current one. Nothing to do."
                return 0
            fi
            ;;

        5)  # Full re-setup
            while true; do
                read -rp "SMB server IP or hostname [current: ${cur_server}]: " new_server < /dev/tty
                new_server="${new_server// /}"
                [[ -z "$new_server" ]] && new_server="$cur_server"
                [[ -n "$new_server" ]] && break
                printf '%sServer address cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done
            _um_smb_prompt_creds "$cur_creds_file"
            _um_smb_pick_share "$new_server" "$new_username" "$new_password" || { info "Cancelled."; return 0; }
            local default_mp
            default_mp=$(printf '%s' "$new_share" | tr -cs 'A-Za-z0-9._-' '_')
            default_mp="${default_mp%_}"
            [[ -z "$default_mp" || "$default_mp" == "_" ]] && default_mp="smb"
            {
                printf '\n  Specify a mount location.\n'
                printf '  Current: %s\n\n' "$sel_mount_point"
            } > /dev/tty
            new_mount_point=$(_um_prompt_mount_point "$default_mp")
            ;;
    esac

    local new_source="//${new_server}/${new_share}"
    local new_creds_file
    new_creds_file=$(_msb_creds_path "$new_server")
    local fstab_opts
    fstab_opts="credentials=${new_creds_file},uid=$(id -u),gid=$(id -g),nofail,_netdev,iocharset=utf8"

    # ── Summary & confirmation ────────────────────────────────────────────────
    {
        printf '\n  Proposed changes:\n'
        printf '    Old source:  %s\n'  "$sel_source"
        printf '    New source:  %s\n'  "$new_source"
        printf '    Old mount:   %s\n'  "$sel_mount_point"
        printf '    New mount:   %s\n'  "$new_mount_point"
        printf '\n  The old share will be unmounted and remounted with the new settings.\n\n'
    } > /dev/tty
    local confirm
    while true; do
        read -rp "Proceed? [y/N]: " confirm < /dev/tty
        case "${confirm,,}" in
            y) break ;;
            n|'') info "Cancelled."; return 0 ;;
            *) printf '%sPlease enter y or n.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty ;;
        esac
    done

    # ── Dry-run ───────────────────────────────────────────────────────────────
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        [[ "$sel_mounted" == "yes" ]] && info "[Dry run] Would unmount ${sel_mount_point}"
        info "[Dry run] Would remove fstab entry for ${sel_mount_point}"
        [[ "$sel_mount_point" != "$new_mount_point" ]] && info "[Dry run] Would rmdir ${sel_mount_point}"
        info "[Dry run] Would write credentials file: ${new_creds_file}"
        info "[Dry run] Would create directory ${new_mount_point}"
        info "[Dry run] Would write fstab: ${new_source} → ${new_mount_point} (${fstab_opts})"
        info "[Dry run] Would run: sudo mount ${new_mount_point}"
        return 0
    fi

    # ── Back up fstab ─────────────────────────────────────────────────────────
    local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    run_as_root cp /etc/fstab "$fstab_backup" || { error "Failed to back up /etc/fstab"; return 1; }
    info "fstab backed up to ${fstab_backup}"

    # ── Unmount old ───────────────────────────────────────────────────────────
    if [[ "$sel_mounted" == "yes" ]]; then
        run_as_root umount "$sel_mount_point" || { error "umount failed for ${sel_mount_point}. Aborting."; return 1; }
        info "Unmounted ${sel_mount_point}"
    fi

    # ── Remove KDE Places entry for old mount ─────────────────────────────────
    _ums_remove_kde_place "$sel_mount_point"

    # ── Remove old fstab entry ────────────────────────────────────────────────
    _ums_remove_fstab "$sel_mount_point" || {
        error "Failed to remove old fstab entry. Restoring backup..."
        run_as_root cp "$fstab_backup" /etc/fstab
        return 1
    }
    info "Removed old fstab entry"

    # ── Remove old mount point directory (only when location changed) ─────────
    if [[ "$sel_mount_point" != "$new_mount_point" && -d "$sel_mount_point" ]]; then
        if run_as_root rmdir "$sel_mount_point" 2>/dev/null; then
            info "Removed directory ${sel_mount_point}"
        else
            warn "Directory ${sel_mount_point} is not empty — left in place."
        fi
    fi

    # ── Create new mount point ────────────────────────────────────────────────
    _um_create_mount_point "$new_mount_point" || return 1

    # ── Write credentials file ────────────────────────────────────────────────
    printf 'username=%s\npassword=%s\n' "$new_username" "$new_password" > "$new_creds_file"
    chmod 600 "$new_creds_file"
    info "Credentials written to ${new_creds_file}"

    # ── Write new fstab entry ─────────────────────────────────────────────────
    local fstab_comment="# linux_util:smb ${new_source} → ${new_mount_point} — updated $(date '+%Y-%m-%d %H:%M:%S')"
    local fstab_entry
    fstab_entry=$(printf '%s\t%s\tcifs\t%s\t0 0' "$new_source" "$new_mount_point" "$fstab_opts")
    printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
        | run_as_root tee -a /etc/fstab > /dev/null || {
        error "Failed to write to /etc/fstab. Restoring backup..."
        run_as_root cp "$fstab_backup" /etc/fstab
        return 1
    }

    # ── Mount ─────────────────────────────────────────────────────────────────
    run_as_root mount "$new_mount_point" || {
        error "mount failed for ${new_mount_point}."
        warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${new_mount_point}"
        return 1
    }

    _msb_add_kde_place "$new_source" "$new_mount_point"

    echo ""
    info "SMB mount updated successfully."
    info "  Source:      ${new_source}"
    info "  Mount point: ${new_mount_point}"
    info "  Backup:      ${fstab_backup}"
    echo ""
    return 0
}

# ── Local disk update branch ──────────────────────────────────────────────────
_um_update_local() {
    local sel_source="$1"        # e.g. UUID=xxxx-xxxx
    local sel_mount_point="$2"
    local sel_fstype="$3"
    local sel_mounted="$4"       # yes / no

    local cur_uuid="${sel_source#UUID=}"

    {
        printf '\n  Current local disk mount:\n'
        printf '    Source:      %s\n'   "$sel_source"
        printf '    Filesystem:  %s\n'   "$sel_fstype"
        printf '    Mount point: %s\n'   "$sel_mount_point"
        printf '    Status:      %s\n\n' "$([[ "$sel_mounted" == "yes" ]] && echo "mounted" || echo "not mounted")"
        printf '  What would you like to change?\n\n'
        printf '  1)  Disk\n'
        printf '  2)  Mount location\n'
        printf '  0)  Cancel\n\n'
    } > /dev/tty

    local what_choice
    while true; do
        read -rp "Select [0-2]: " what_choice < /dev/tty
        [[ "$what_choice" =~ ^[0-2]$ ]] && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done
    [[ "$what_choice" == "0" ]] && { info "Cancelled."; return 0; }

    case "$what_choice" in
        1)  # Change disk
            # Must unmount first so the current disk appears in the available list.
            {
                printf '\n  Changing the disk requires unmounting the current drive first.\n'
                printf '  You will then select the replacement disk from the available list.\n\n'
            } > /dev/tty
            local pre_confirm
            while true; do
                read -rp "Proceed to unmount and select new disk? [y/N]: " pre_confirm < /dev/tty
                case "${pre_confirm,,}" in
                    y) break ;;
                    n|'') info "Cancelled."; return 0 ;;
                    *) printf '%sPlease enter y or n.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty ;;
                esac
            done

            # Back up fstab before any changes
            local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
            run_as_root cp /etc/fstab "$fstab_backup" || { error "Failed to back up /etc/fstab"; return 1; }
            info "fstab backed up to ${fstab_backup}"

            # Unmount old disk
            if [[ "$sel_mounted" == "yes" ]]; then
                run_as_root umount "$sel_mount_point" || { error "umount failed for ${sel_mount_point}. Aborting."; return 1; }
                info "Unmounted ${sel_mount_point}"
            fi

            # Show available disks (now includes the old one)
            info "Scanning for available drives..."
            local -a disk_entries=()
            mapfile -t disk_entries < <(_mld_unmounted_list)
            if (( ${#disk_entries[@]} == 0 )); then
                warn "No unmounted drives found."
                info "Restoring previous mount..."
                run_as_root cp "$fstab_backup" /etc/fstab
                [[ "$sel_mounted" == "yes" ]] && run_as_root mount "$sel_mount_point"
                return 1
            fi
            {
                printf '\n'
                printf '  %-4s  %-9s  %-7s  %-10s  %-22s  %s\n' "#" "Device" "Size" "Type" "Label" "UUID"
                printf '  %s\n' "────────────────────────────────────────────────────────────────────────────"
                local disk_entry
                for disk_entry in "${disk_entries[@]}"; do
                    IFS='|' read -r idx name uuid fstype label size <<< "$disk_entry"
                    local display_label="${label:-(no label)}"
                    printf '  %-4s  %-9s  %-7s  %-10s  %-22s  %s\n' \
                        "${idx})" "/dev/${name}" "$size" "$fstype" "$display_label" "$uuid"
                done
                printf '\n  0)    Cancel (restore previous mount)\n\n'
            } > /dev/tty

            local disk_total=${#disk_entries[@]}
            local disk_choice
            while true; do
                read -rp "Select new drive [0-${disk_total}]: " disk_choice < /dev/tty
                if [[ "$disk_choice" == "0" ]]; then
                    info "Cancelled. Restoring previous mount..."
                    [[ "$sel_mounted" == "yes" ]] && run_as_root mount "$sel_mount_point"
                    return 0
                fi
                if [[ "$disk_choice" =~ ^[0-9]+$ ]] && (( disk_choice >= 1 && disk_choice <= disk_total )); then
                    break
                fi
                printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            done

            local sel_disk="${disk_entries[$((disk_choice - 1))]}"
            local new_name new_uuid new_fstype new_label
            IFS='|' read -r _ new_name new_uuid new_fstype new_label _ <<< "$sel_disk"
            local fstab_fstype
            fstab_fstype=$(_mld_resolve_fstype "$new_fstype")

            # Show summary and confirm
            {
                printf '\n  Proposed changes:\n'
                printf '    Old source:  %s\n'   "$sel_source"
                printf '    New source:  UUID=%s  (/dev/%s%s)\n' \
                    "$new_uuid" "$new_name" "${new_label:+  [${new_label}]}"
                printf '    Mount point: %s  (unchanged)\n\n' "$sel_mount_point"
            } > /dev/tty
            local confirm
            while true; do
                read -rp "Proceed? [y/N]: " confirm < /dev/tty
                case "${confirm,,}" in
                    y) break ;;
                    n|'')
                        info "Cancelled. Restoring previous mount..."
                        [[ "$sel_mounted" == "yes" ]] && run_as_root mount "$sel_mount_point"
                        return 0
                        ;;
                    *) printf '%sPlease enter y or n.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty ;;
                esac
            done

            # Dry-run (post-unmount path)
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                info "[Dry run] Would remove fstab entry for ${sel_mount_point}"
                info "[Dry run] Would write fstab: UUID=${new_uuid} → ${sel_mount_point} (${fstab_fstype})"
                info "[Dry run] Would run: sudo mount ${sel_mount_point}"
                return 0
            fi

            # Remove old fstab entry
            _ums_remove_fstab "$sel_mount_point" || {
                error "Failed to update fstab. Restoring backup and remounting..."
                run_as_root cp "$fstab_backup" /etc/fstab
                [[ "$sel_mounted" == "yes" ]] && run_as_root mount "$sel_mount_point"
                return 1
            }
            info "Removed old fstab entry"

            # Ensure filesystem tools for new disk
            _mld_ensure_fs_tools "$fstab_fstype" || return 1

            # Write new fstab entry
            local fstab_comment="# linux_util:mount /dev/${new_name}${new_label:+ (${new_label})} → ${sel_mount_point} — updated $(date '+%Y-%m-%d %H:%M:%S')"
            local fstab_entry
            fstab_entry=$(printf 'UUID=%s\t%s\t%s\t%s\t%s' \
                "$new_uuid" "$sel_mount_point" "$fstab_fstype" \
                "$(_mld_fstab_opts "$fstab_fstype")" "$(_mld_dump_pass "$fstab_fstype")")
            printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
                | run_as_root tee -a /etc/fstab > /dev/null || {
                error "Failed to write to /etc/fstab. Restoring backup..."
                run_as_root cp "$fstab_backup" /etc/fstab
                return 1
            }

            # Mount new disk at existing mount point
            run_as_root mount "$sel_mount_point" || {
                error "mount failed for ${sel_mount_point}."
                warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${sel_mount_point}"
                return 1
            }

            echo ""
            info "Local disk updated successfully."
            info "  New source:  UUID=${new_uuid}  (/dev/${new_name})"
            info "  Mount point: ${sel_mount_point}"
            info "  Backup:      ${fstab_backup}"
            echo ""
            return 0
            ;;

        2)  # Change mount location — keep same UUID and filesystem
            local default_mp
            default_mp=$(basename "$sel_mount_point" | tr -cs 'A-Za-z0-9._-' '_')
            default_mp="${default_mp%_}"
            [[ -z "$default_mp" || "$default_mp" == "_" ]] && default_mp="disk"
            {
                printf '\n  Specify a new mount location.\n'
                printf '  Current: %s\n\n' "$sel_mount_point"
            } > /dev/tty
            local new_mount_point
            new_mount_point=$(_um_prompt_mount_point "$default_mp")
            if [[ "$new_mount_point" == "$sel_mount_point" ]]; then
                warn "New mount point is the same as the current one. Nothing to do."
                return 0
            fi

            local fstab_fstype
            fstab_fstype=$(_mld_resolve_fstype "$sel_fstype")

            # Summary & confirmation
            {
                printf '\n  Proposed changes:\n'
                printf '    Source:      %s  (unchanged)\n' "$sel_source"
                printf '    Old mount:   %s\n'              "$sel_mount_point"
                printf '    New mount:   %s\n\n'            "$new_mount_point"
            } > /dev/tty
            local confirm
            while true; do
                read -rp "Proceed? [y/N]: " confirm < /dev/tty
                case "${confirm,,}" in
                    y) break ;;
                    n|'') info "Cancelled."; return 0 ;;
                    *) printf '%sPlease enter y or n.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty ;;
                esac
            done

            # Dry-run
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                [[ "$sel_mounted" == "yes" ]] && info "[Dry run] Would unmount ${sel_mount_point}"
                info "[Dry run] Would remove fstab entry for ${sel_mount_point}"
                info "[Dry run] Would rmdir ${sel_mount_point}"
                info "[Dry run] Would create directory ${new_mount_point}"
                info "[Dry run] Would write fstab: ${sel_source} → ${new_mount_point} (${fstab_fstype})"
                info "[Dry run] Would run: sudo mount ${new_mount_point}"
                return 0
            fi

            # Back up fstab
            local fstab_backup="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
            run_as_root cp /etc/fstab "$fstab_backup" || { error "Failed to back up /etc/fstab"; return 1; }
            info "fstab backed up to ${fstab_backup}"

            # Unmount
            if [[ "$sel_mounted" == "yes" ]]; then
                run_as_root umount "$sel_mount_point" || { error "umount failed for ${sel_mount_point}. Aborting."; return 1; }
                info "Unmounted ${sel_mount_point}"
            fi

            # Remove old fstab entry
            _ums_remove_fstab "$sel_mount_point" || {
                error "Failed to update fstab. Restoring backup and remounting..."
                run_as_root cp "$fstab_backup" /etc/fstab
                [[ "$sel_mounted" == "yes" ]] && run_as_root mount "$sel_mount_point"
                return 1
            }
            info "Removed old fstab entry"

            # Remove old mount point directory
            if [[ -d "$sel_mount_point" ]]; then
                if run_as_root rmdir "$sel_mount_point" 2>/dev/null; then
                    info "Removed directory ${sel_mount_point}"
                else
                    warn "Directory ${sel_mount_point} is not empty — left in place."
                fi
            fi

            # Create new mount point
            _um_create_mount_point "$new_mount_point" || return 1

            # Ensure filesystem tools
            _mld_ensure_fs_tools "$fstab_fstype" || return 1

            # Write new fstab entry
            local fstab_comment="# linux_util:mount ${sel_source} → ${new_mount_point} — updated $(date '+%Y-%m-%d %H:%M:%S')"
            local fstab_entry
            fstab_entry=$(printf '%s\t%s\t%s\t%s\t%s' \
                "$sel_source" "$new_mount_point" "$fstab_fstype" \
                "$(_mld_fstab_opts "$fstab_fstype")" "$(_mld_dump_pass "$fstab_fstype")")
            printf '\n%s\n%s\n' "$fstab_comment" "$fstab_entry" \
                | run_as_root tee -a /etc/fstab > /dev/null || {
                error "Failed to write to /etc/fstab. Restoring backup..."
                run_as_root cp "$fstab_backup" /etc/fstab
                return 1
            }

            # Mount
            run_as_root mount "$new_mount_point" || {
                error "mount failed for ${new_mount_point}."
                warn "The fstab entry was written — review /etc/fstab and try: sudo mount ${new_mount_point}"
                return 1
            }

            echo ""
            info "Local disk mount location updated successfully."
            info "  Source:      ${sel_source}"
            info "  Mount point: ${new_mount_point}"
            info "  Backup:      ${fstab_backup}"
            echo ""
            return 0
            ;;
    esac
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_update_mount() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Update Mount                                                   ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    # ── Step 1: Mount type selection ──────────────────────────────────────────
    {
        printf '  Which type of mount would you like to update?\n\n'
        printf '  1)  NFS Share\n'
        printf '  2)  SMB Share\n'
        printf '  3)  Local Disk\n'
        printf '  0)  Cancel\n\n'
    } > /dev/tty
    local type_choice
    while true; do
        read -rp "Select [0-3]: " type_choice < /dev/tty
        [[ "$type_choice" =~ ^[0-3]$ ]] && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done
    [[ "$type_choice" == "0" ]] && { info "Cancelled."; return 0; }

    local filter_type
    case "$type_choice" in
        1) filter_type="nfs" ;;
        2) filter_type="smb" ;;
        3) filter_type="mount" ;;
    esac

    # ── Step 2: Collect and filter managed mounts ─────────────────────────────
    local -a all_entries=()
    mapfile -t all_entries < <(_ums_managed_list)

    if (( ${#all_entries[@]} == 0 )); then
        warn "No linux_util-managed mounts found in /etc/fstab."
        return 0
    fi

    local -a entries=()
    local entry
    for entry in "${all_entries[@]}"; do
        IFS='|' read -r _ etype _ _ _ _ <<< "$entry"
        [[ "$etype" == "$filter_type" ]] && entries+=("$entry")
    done

    local type_label
    case "$filter_type" in
        nfs)   type_label="NFS share" ;;
        smb)   type_label="SMB share" ;;
        mount) type_label="local disk" ;;
    esac

    if (( ${#entries[@]} == 0 )); then
        warn "No linux_util-managed ${type_label} mounts found in /etc/fstab."
        return 0
    fi

    # ── Step 3: Display mount table ───────────────────────────────────────────
    {
        printf '\n'
        if [[ "$filter_type" == "mount" ]]; then
            printf '  %-4s  %-12s  %-10s  %-30s  %s\n' "#" "Status" "Type" "Source" "Mount Point"
        else
            printf '  %-4s  %-12s  %-34s  %s\n' "#" "Status" "Source" "Mount Point"
        fi
        printf '  %s\n' "──────────────────────────────────────────────────────────────────────────────────────"
        local i=1
        for entry in "${entries[@]}"; do
            IFS='|' read -r _ _ source mount_point fstype mounted <<< "$entry"
            local status_label
            [[ "$mounted" == "yes" ]] && status_label="[mounted]" || status_label="[unmounted]"
            if [[ "$filter_type" == "mount" ]]; then
                printf '  %-4s  %-12s  %-10s  %-30s  %s\n' "${i})" "$status_label" "$fstype" "$source" "$mount_point"
            else
                printf '  %-4s  %-12s  %-34s  %s\n' "${i})" "$status_label" "$source" "$mount_point"
            fi
            (( i++ )) || true
        done
        printf '\n  0)    Cancel\n\n'
    } > /dev/tty

    # ── Step 4: Mount selection ───────────────────────────────────────────────
    local total=${#entries[@]}
    local choice
    while true; do
        read -rp "Select ${type_label} mount to update [0-${total}]: " choice < /dev/tty
        [[ "$choice" == "0" ]] && { info "Cancelled."; return 0; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then
            break
        fi
        printf '%sInvalid selection. Enter a number between 0 and %d.%s\n' \
            "${RED:-}" "$total" "${RESET:-}" > /dev/tty
    done

    local sel_entry="${entries[$((choice - 1))]}"
    local sel_type sel_source sel_mount_point sel_fstype sel_mounted
    IFS='|' read -r _ sel_type sel_source sel_mount_point sel_fstype sel_mounted <<< "$sel_entry"

    # ── Step 5: Route to the appropriate update handler ───────────────────────
    case "$filter_type" in
        nfs)
            _mns_ensure_nfs_tools || return 1
            _um_update_nfs "$sel_source" "$sel_mount_point" "$sel_mounted"
            ;;
        smb)
            _msb_ensure_smb_tools || return 1
            _um_update_smb "$sel_source" "$sel_mount_point" "$sel_mounted"
            ;;
        mount)
            _um_update_local "$sel_source" "$sel_mount_point" "$sel_fstype" "$sel_mounted"
            ;;
    esac
}

# ── Lifecycle stubs ───────────────────────────────────────────────────────────
check_update_mount()     { return 1; }
uninstall_update_mount() { return 0; }
update_update_mount()    { setup_update_mount; }
