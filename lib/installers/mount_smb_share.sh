#!/bin/bash
# Mount SMB/CIFS Share — interactively add a network SMB share to /etc/fstab
# and mount it under the current user's home directory (or a specified path).

# ── Version / status ──────────────────────────────────────────────────────────
get_version_mount_smb_share() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -c "# linux_util:smb " /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} SMB share(s) configured via linux_util"
}

# ── Internal helpers ──────────────────────────────────────────────────────────

_smb_ensure_tools() {
    if ! command -v mount.cifs &>/dev/null; then
        warn "cifs-utils is not installed. Attempting to install..."
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y cifs-utils ;;
            fedora)  sudo "$PKG_MGR" install -y cifs-utils ;;
            rhel)    sudo "$PKG_MGR" install -y cifs-utils ;;
            arch)    sudo pacman -S --noconfirm cifs-utils ;;
            suse)    sudo zypper install -y cifs-utils ;;
            *)       warn "Cannot auto-install cifs-utils on this distro. Install it manually."; return 1 ;;
        esac
    fi
    return 0
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_mount_smb_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Mount SMB/CIFS Network Share                                  ${RESET:-}"
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

    # ── Step 2: Share name ────────────────────────────────────────────────────
    local share_name
    while true; do
        read -rp "Share name (e.g. myshare): " share_name < /dev/tty
        share_name="${share_name// /}"
        if [[ -z "$share_name" ]]; then
            printf '%sShare name cannot be empty.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
            continue
        fi
        break
    done

    # ── Step 3: Credentials ───────────────────────────────────────────────────
    printf '\n' > /dev/tty
    info "Leave username blank to mount as guest (no credentials)."
    local smb_user smb_pass credentials_opts
    read -rp "SMB username [guest]: " smb_user < /dev/tty

    if [[ -z "$smb_user" ]]; then
        credentials_opts="guest,uid=$(id -u),gid=$(id -g)"
    else
        read -rsp "SMB password: " smb_pass < /dev/tty
        printf '\n' > /dev/tty

        # Write a credentials file so the password never appears in fstab
        local creds_dir="/etc/samba/credentials"
        local creds_file="${creds_dir}/$(echo "${server_ip}_${share_name}" | tr -cs 'A-Za-z0-9._-' '_')"

        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            run_as_root mkdir -p "$creds_dir"
            printf 'username=%s\npassword=%s\n' "$smb_user" "$smb_pass" \
                | run_as_root tee "$creds_file" > /dev/null
            run_as_root chmod 600 "$creds_file"
        fi

        credentials_opts="credentials=${creds_file},uid=$(id -u),gid=$(id -g)"
    fi

    # ── Step 4: Mount folder name ─────────────────────────────────────────────
    local default_name
    default_name=$(printf '%s' "${share_name}" | tr -cs 'A-Za-z0-9._-' '_')

    local default_mount_point="/home/${USER}/${default_name}"
    printf '\n' > /dev/tty
    local mount_input
    while true; do
        read -rp "Mount point [default: ${default_mount_point}]: " mount_input < /dev/tty
        [[ -z "$mount_input" ]] && mount_input="$default_mount_point"

        local re_abs='^/[A-Za-z0-9][-A-Za-z0-9_./ ]*$'
        local re_name='^[A-Za-z0-9][-A-Za-z0-9_.]*$'
        if [[ "$mount_input" == /* ]]; then
            # Absolute path — validate each component
            if [[ ! "$mount_input" =~ $re_abs ]]; then
                printf '%sInvalid path. Use an absolute path (e.g. /media/Apps) or a folder name.%s\n' \
                    "${RED:-}" "${RESET:-}" > /dev/tty
                continue
            fi
        else
            # Bare name — validate and expand to home
            if [[ ! "$mount_input" =~ $re_name ]]; then
                printf '%sName must start with a letter or digit and contain only letters, numbers, underscores, hyphens, or dots.%s\n' \
                    "${RED:-}" "${RESET:-}" > /dev/tty
                continue
            fi
            mount_input="/home/${USER}/${mount_input}"
        fi
        break
    done

    local mount_point="$mount_input"
    local smb_source="//${server_ip}/${share_name}"
    local fstab_opts="${credentials_opts},iocharset=utf8,file_mode=0755,dir_mode=0755,nofail,_netdev"

    # ── Step 5: Summary & confirmation ───────────────────────────────────────
    {
        printf '\n'
        printf '  Source:      %s\n' "$smb_source"
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
        printf '  # linux_util:smb %s → %s\n' "$smb_source" "$mount_point"
        printf '  %s\t%s\tcifs\t%s\t0 0\n' "$smb_source" "$mount_point" "$fstab_opts"
        info "[Dry run] Would run: sudo mount ${mount_point}"
        return 0
    fi

    # ── Step 6: Ensure tools ──────────────────────────────────────────────────
    _smb_ensure_tools || return 1

    # ── Step 7: Guard — check fstab for collisions ────────────────────────────
    if grep -qsF "${smb_source} " /etc/fstab || grep -qsF "${smb_source}	" /etc/fstab; then
        warn "An entry for ${smb_source} already exists in /etc/fstab."
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
    fstab_comment="# linux_util:smb ${smb_source} → ${mount_point} — added $(date '+%Y-%m-%d %H:%M:%S')"

    local fstab_entry
    fstab_entry=$(printf '%s\t%s\tcifs\t%s\t0 0' "$smb_source" "$mount_point" "$fstab_opts")

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
