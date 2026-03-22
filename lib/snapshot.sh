#!/bin/bash

# ============================================================================
# Linux Utilities - Snapshot Module (Timeshift / Snapper)
# Provides snapshot integration using Timeshift (all supported distros) or
# Snapper (Arch-based systems with btrfs). If no supported snapshot tool is
# installed, all functions fail quietly and the script continues normally.
# ============================================================================

# Global state
TIMESHIFT_AVAILABLE=false
TIMESHIFT_LAST_SNAPSHOT=""
SNAPSHOT_BACKEND=""  # "timeshift" or "snapper"

# Check if the root filesystem is btrfs.
# Returns 0 if btrfs, 1 otherwise.
_is_btrfs_root() {
    local fstype
    fstype=$(findmnt -n -o FSTYPE / 2>/dev/null)
    [[ "$fstype" == "btrfs" ]]
}

# ============================================================================
# Timeshift Detection & Initialization
# ============================================================================

# Initialize snapshot support. Checks for Timeshift on all distro families,
# and falls back to Snapper on Arch-based systems (e.g. CachyOS with btrfs).
# Sets TIMESHIFT_AVAILABLE=true and SNAPSHOT_BACKEND if a tool is found.
timeshift_init() {
    # Check for Timeshift (supported on all distro families)
    if command -v timeshift &>/dev/null; then
        SNAPSHOT_BACKEND="timeshift"
        TIMESHIFT_AVAILABLE=true
        verbose "Timeshift: Detected and available"

        # Check if a backup device is configured; if not, set one up
        if ! _timeshift_has_device; then
            _timeshift_setup_device
        fi

        # Cache the last snapshot info for the banner
        _timeshift_cache_last_snapshot
        return 0
    fi

    # On Arch-based systems, check for Snapper as an alternative
    if [[ "${DISTRO_FAMILY:-}" == "arch" ]] && command -v snapper &>/dev/null; then
        if _snapper_has_config; then
            SNAPSHOT_BACKEND="snapper"
            TIMESHIFT_AVAILABLE=true
            verbose "Snapper: Detected and available (Arch-based system)"
            _snapper_cache_last_snapshot
            return 0
        else
            verbose "Snapper: Installed but no root config found — skipping"
        fi
    fi

    verbose "Snapshot: No supported snapshot tool found — skipping"
    return 0
}

# ============================================================================
# Device Configuration
# ============================================================================

# Check if Timeshift already has a backup device configured.
# Returns 0 if configured, 1 if not.
_timeshift_has_device() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 1

    # First check: config file must exist and not be in first-run mode.
    # Without a config file, timeshift enters "first run mode" which breaks
    # --create --tags, so we must ensure proper setup before anything else.
    if [[ ! -f /etc/timeshift/timeshift.json ]]; then
        verbose "Timeshift: No config file found — needs setup"
        return 1
    fi

    # Check if the config has a backup device UUID set
    local dev
    dev=$(grep -o '"backup_device_uuid" *: *"[^"]*"' /etc/timeshift/timeshift.json 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"')
    if [[ -n "$dev" && "$dev" != "" ]]; then
        verbose "Timeshift: Device configured via config file (UUID: ${dev})"
        return 0
    fi

    verbose "Timeshift: No backup device configured in config file"
    return 1
}

# Set up a Timeshift backup device. Attempts to auto-detect the boot device.
# If uncertain, prompts the user to select one.
_timeshift_setup_device() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 0

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Timeshift: Backup Device Setup                               ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "Timeshift requires a backup device to store snapshots."
    echo "Detecting available devices..."
    echo ""

    # Get the current root (boot) device
    # Strip btrfs subvolume suffix (e.g. /dev/xvda3[/root] → /dev/xvda3)
    local root_dev root_uuid
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null | head -1 | sed 's/\[.*\]$//')
    root_uuid=$(sudo blkid -s UUID -o value "$root_dev" 2>/dev/null)

    # List devices via timeshift and parse the numbered device table
    local devices_output
    devices_output=$(sudo timeshift --list-devices 2>&1) || true

    echo "$devices_output"
    echo ""

    # Build arrays of device paths and UUIDs from the numbered list
    # Format: "0    >  /dev/xvda2    2.1 GB   ext4"
    local -a _ts_dev_paths=()
    local -a _ts_dev_uuids=()
    while IFS= read -r _line; do
        local _dev_path
        _dev_path=$(echo "$_line" | grep -oP '/dev/\S+')
        if [[ -n "$_dev_path" ]]; then
            _ts_dev_paths+=("$_dev_path")
            local _dev_uuid
            _dev_uuid=$(sudo blkid -s UUID -o value "$_dev_path" 2>/dev/null)
            _ts_dev_uuids+=("${_dev_uuid:-}")
        fi
    done < <(echo "$devices_output" | grep -E '^\s*[0-9]+\s')

    if [[ -n "$root_dev" && -n "$root_uuid" ]]; then
        echo "Current boot device detected: ${BOLD}${root_dev}${RESET} (UUID: ${root_uuid})"
        echo ""
        read -n 1 -rp "Use boot device ${root_dev} for Timeshift snapshots? (Y/n) " _ts_choice
        echo ""

        if [[ ! "$_ts_choice" =~ ^[Nn]$ ]]; then
            # Write config directly — timeshift --snapshot-device always defaults
            # to RSYNC mode, ignoring the filesystem type.  By writing the config
            # ourselves we ensure btrfs_mode is set correctly on btrfs systems.
            _timeshift_write_device_config "$root_uuid"
            echo "${GREEN}Timeshift configured to use: ${root_dev}${RESET}"
            log_info "Timeshift: Configured backup device ${root_dev} (UUID: ${root_uuid})"
            return 0
        fi
    else
        echo "${YELLOW}Could not auto-detect boot device.${RESET}"
        echo ""
    fi

    # Manual device selection — accept a number from the list, device path, or UUID
    echo "Please enter a device number from the list above, a device path (e.g., /dev/sda1), or UUID:"
    read -rp "> " _ts_manual_dev

    if [[ -z "$_ts_manual_dev" ]]; then
        warn "No device selected. Timeshift snapshots will not be available."
        TIMESHIFT_AVAILABLE=false
        return 1
    fi

    # If the user entered a number, resolve it from the device list
    if [[ "$_ts_manual_dev" =~ ^[0-9]+$ ]] && (( _ts_manual_dev < ${#_ts_dev_paths[@]} )); then
        local _selected_dev="${_ts_dev_paths[$_ts_manual_dev]}"
        local _selected_uuid="${_ts_dev_uuids[$_ts_manual_dev]}"
        echo "Selected device: ${BOLD}${_selected_dev}${RESET}"
        local manual_uuid="${_selected_uuid}"
        _ts_manual_dev="$_selected_dev"
    elif [[ "$_ts_manual_dev" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        # Standard UUID format
        local manual_uuid="$_ts_manual_dev"
    elif [[ "$_ts_manual_dev" == /dev/* ]]; then
        # Device path — resolve UUID
        local manual_uuid
        manual_uuid=$(sudo blkid -s UUID -o value "$_ts_manual_dev" 2>/dev/null)
    else
        echo "${YELLOW}Invalid selection: ${_ts_manual_dev}${RESET}"
        warn "No valid device selected. Timeshift snapshots will not be available."
        TIMESHIFT_AVAILABLE=false
        return 1
    fi

    if [[ -n "$manual_uuid" ]]; then
        _timeshift_write_device_config "$manual_uuid"
        echo "${GREEN}Timeshift configured to use: ${_ts_manual_dev}${RESET}"
        log_info "Timeshift: Configured backup device ${_ts_manual_dev} (UUID: ${manual_uuid:-unknown})"
    else
        # No UUID resolved — try timeshift's own device setup as a last resort
        sudo timeshift --snapshot-device "$_ts_manual_dev" --scripted 2>/dev/null || {
            warn "Failed to configure Timeshift device. Snapshots may not work."
            TIMESHIFT_AVAILABLE=false
            return 1
        }
        # Ensure btrfs_mode is correct even when timeshift wrote the config
        if _is_btrfs_root && [[ -f /etc/timeshift/timeshift.json ]]; then
            sudo sed -i 's/"btrfs_mode" *: *"false"/"btrfs_mode" : "true"/' /etc/timeshift/timeshift.json
        fi
        echo "${GREEN}Timeshift configured to use: ${_ts_manual_dev}${RESET}"
        log_info "Timeshift: Configured backup device ${_ts_manual_dev}"
    fi

    return 0
}

# Write device UUID directly to Timeshift config as a fallback.
_timeshift_write_device_config() {
    local uuid="$1"
    local config_file="/etc/timeshift/timeshift.json"

    # Detect filesystem type so timeshift uses the correct snapshot mode
    local btrfs_mode="false"
    local btrfs_home="false"
    if _is_btrfs_root; then
        btrfs_mode="true"
        # Include @home in snapshots if the subvolume exists
        if findmnt -n /home 2>/dev/null | grep -q 'subvol=.*@home'; then
            btrfs_home="true"
        fi
    fi

    if [[ ! -f "$config_file" ]]; then
        sudo mkdir -p /etc/timeshift
        sudo tee "$config_file" > /dev/null <<TSCFG
{
  "backup_device_uuid" : "${uuid}",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "${btrfs_mode}",
  "include_btrfs_home_for_backup" : "${btrfs_home}",
  "include_btrfs_home_for_restore" : "${btrfs_home}",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "false",
  "schedule_daily" : "false",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [],
  "exclude-apps" : []
}
TSCFG
    else
        # Update existing config — replace the backup_device_uuid value
        sudo sed -i "s|\"backup_device_uuid\" *: *\"[^\"]*\"|\"backup_device_uuid\" : \"${uuid}\"|" "$config_file"
    fi

    verbose "Timeshift: Wrote device UUID ${uuid} to ${config_file}"
}

# ============================================================================
# Snapshot Info
# ============================================================================

# Cache the last snapshot information for display in the menu banner.
_timeshift_cache_last_snapshot() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 0

    local list_output
    list_output=$(sudo timeshift --list 2>&1) || true

    # Parse the last snapshot line from timeshift --list output.
    # Typical format:
    #   Num   Name                 Tags  Description
    #   0  >  2025-05-03_02-23-16  O
    local last_line
    last_line=$(echo "$list_output" | grep -E '^\s*[0-9]+\s+>?\s+[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)

    if [[ -n "$last_line" ]]; then
        # Extract the snapshot name (timestamp)
        local snap_name
        snap_name=$(echo "$last_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {print $i; exit}}')

        # Extract tags
        local snap_tags
        snap_tags=$(echo "$last_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[DWMOB]+$/) {print $i; exit}}')

        # Extract description (everything after the tag)
        local snap_desc
        snap_desc=$(echo "$last_line" | sed -E 's/.*[DWMOB]+\s*//' | sed 's/^\s*//')

        if [[ -n "$snap_name" ]]; then
            TIMESHIFT_LAST_SNAPSHOT="${snap_name}"
            [[ -n "$snap_tags" ]] && TIMESHIFT_LAST_SNAPSHOT+=" [${snap_tags}]"
            [[ -n "$snap_desc" ]] && TIMESHIFT_LAST_SNAPSHOT+=" - ${snap_desc}"
        fi
    fi

    if [[ -z "$TIMESHIFT_LAST_SNAPSHOT" ]]; then
        TIMESHIFT_LAST_SNAPSHOT="No snapshots found"
    fi

    verbose "Timeshift: Last snapshot: ${TIMESHIFT_LAST_SNAPSHOT}"
}

# ============================================================================
# Snapper Integration (Arch-based systems)
# ============================================================================

# Check if Snapper has a root configuration.
_snapper_has_config() {
    [[ -f /etc/snapper/configs/root ]]
}

# Cache the last Snapper snapshot info for the menu banner.
_snapper_cache_last_snapshot() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 0

    local list_output
    list_output=$(sudo snapper -c root list 2>&1) || true

    # Parse the last snapshot line. Default snapper output:
    #  # | Type   | Pre # | Date                     | User | Cleanup  | Description
    # Columns: 1=#, 2=Type, 3=Pre#, 4=Date, 5=User, 6=Cleanup, 7=Description
    local last_line
    last_line=$(echo "$list_output" | grep -E '^\s*[0-9]+\s*\|' | grep -v '^\s*0\s*\|' | tail -1)

    if [[ -n "$last_line" ]]; then
        local snap_num snap_date snap_desc
        snap_num=$(echo "$last_line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
        snap_date=$(echo "$last_line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
        snap_desc=$(echo "$last_line" | awk -F'|' '{gsub(/^ +| +$/,"",$7); print $7}')

        TIMESHIFT_LAST_SNAPSHOT="#${snap_num}"
        [[ -n "$snap_date" ]] && TIMESHIFT_LAST_SNAPSHOT+=" ${snap_date}"
        [[ -n "$snap_desc" ]] && TIMESHIFT_LAST_SNAPSHOT+=" - ${snap_desc}"
    fi

    if [[ -z "$TIMESHIFT_LAST_SNAPSHOT" ]]; then
        TIMESHIFT_LAST_SNAPSHOT="No snapshots found"
    fi

    verbose "Snapper: Last snapshot: ${TIMESHIFT_LAST_SNAPSHOT}"
}

# Create a Snapper snapshot. Used as backend when SNAPSHOT_BACKEND=snapper.
# Arguments:
#   $1 - Comment/description for the snapshot (optional)
# Always returns 0 (fail quietly).
_snapper_create_snapshot() {
    local comment="${1:-linux_util: pre-operation snapshot}"

    echo ""
    echo "${BOLD}${CYAN}Creating Snapper snapshot...${RESET}"
    echo "${DIM}Comment: ${comment}${RESET}"
    echo ""

    local snap_output
    if snap_output=$(sudo snapper -c root create --type single --description "$comment" --cleanup-algorithm number 2>&1); then
        echo "${GREEN}✓ Snapper snapshot created successfully${RESET}"
        log_success "Snapper snapshot created: ${comment}"
        verbose "Snapper output: ${snap_output}"
        _snapper_cache_last_snapshot
    else
        echo "${YELLOW}⚠ Snapper snapshot creation failed (continuing anyway)${RESET}"
        log_warning "Snapper snapshot creation failed: ${snap_output}"
        verbose "Snapper error output: ${snap_output}"
    fi

    return 0
}

# ============================================================================
# Snapshot Listing
# ============================================================================

# List all available Timeshift snapshots (interactive display).
# Prints the list and populates SNAPSHOT_NAMES[] with selectable snapshot IDs.
# Returns 0 if snapshots exist, 1 if none found.
declare -a SNAPSHOT_NAMES=()

_timeshift_list_snapshots() {
    SNAPSHOT_NAMES=()
    local list_output
    list_output=$(sudo timeshift --list 2>&1) || true

    echo "$list_output"
    echo ""

    # Parse snapshot names (timestamps) from timeshift --list output
    while IFS= read -r line; do
        local snap_name
        snap_name=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {print $i; exit}}')
        [[ -n "$snap_name" ]] && SNAPSHOT_NAMES+=("$snap_name")
    done < <(echo "$list_output" | grep -E '^\s*[0-9]+\s+>?\s+[0-9]{4}-[0-9]{2}-[0-9]{2}')

    [[ ${#SNAPSHOT_NAMES[@]} -gt 0 ]] && return 0 || return 1
}

_snapper_list_snapshots() {
    SNAPSHOT_NAMES=()
    local list_output
    list_output=$(sudo snapper -c root list 2>&1) || true

    echo "$list_output"
    echo ""

    # Parse snapshot numbers from snapper list output (skip snapshot 0 = current)
    while IFS= read -r line; do
        local snap_num
        snap_num=$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$1); print $1}')
        [[ -n "$snap_num" && "$snap_num" != "0" ]] && SNAPSHOT_NAMES+=("$snap_num")
    done < <(echo "$list_output" | grep -E '^\s*[0-9]+\s*\|' | grep -v '^\s*0\s*\|')

    [[ ${#SNAPSHOT_NAMES[@]} -gt 0 ]] && return 0 || return 1
}

# List snapshots using the active backend.
# Populates SNAPSHOT_NAMES[] and returns 0 if snapshots exist.
timeshift_list_snapshots() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 1

    if [[ "$SNAPSHOT_BACKEND" == "snapper" ]]; then
        _snapper_list_snapshots
    else
        _timeshift_list_snapshots
    fi
}

# ============================================================================
# Snapshot Restore
# ============================================================================

# Restore a Timeshift BTRFS snapshot by replacing the active @ subvolume
# with a writable snapshot from the selected snapshot. The current @ (and
# optionally @home) subvolumes are renamed as backups before the swap.
# Arguments:
#   $1 - Snapshot name/timestamp to restore
# Returns 0 on success, 1 on failure.
_timeshift_btrfs_restore() {
    local snapshot_name="$1"

    # Get the backup device from timeshift config
    local backup_uuid
    backup_uuid=$(grep -o '"backup_device_uuid" *: *"[^"]*"' /etc/timeshift/timeshift.json 2>/dev/null \
        | grep -o '"[^"]*"$' | tr -d '"')

    if [[ -z "$backup_uuid" ]]; then
        echo "${RED}✗ Cannot determine Timeshift backup device from config${RESET}"
        return 1
    fi

    local backup_dev
    backup_dev=$(sudo blkid -U "$backup_uuid" 2>/dev/null)
    if [[ -z "$backup_dev" ]]; then
        echo "${RED}✗ Backup device with UUID ${backup_uuid} not found${RESET}"
        return 1
    fi

    # Mount the btrfs volume at subvolid=5 (top-level) to access all subvolumes
    local mount_point=""
    local _did_mount=false

    # Check if already mounted with access to the snapshot directory
    mount_point=$(findmnt -n -o TARGET "$backup_dev" 2>/dev/null | head -1)

    if [[ -z "$mount_point" ]] || [[ ! -d "${mount_point}/timeshift-btrfs/snapshots" ]]; then
        mount_point="/run/timeshift/btrfs-restore"
        sudo mkdir -p "$mount_point"
        if ! sudo mount -o subvolid=5 "$backup_dev" "$mount_point"; then
            echo "${RED}✗ Failed to mount btrfs volume ${backup_dev} at subvolid=5${RESET}"
            return 1
        fi
        _did_mount=true
    fi

    # Locate the snapshot subvolume
    local snap_root="${mount_point}/timeshift-btrfs/snapshots/${snapshot_name}/@"
    if [[ ! -d "$snap_root" ]]; then
        echo "${RED}✗ Snapshot subvolume not found: ${snap_root}${RESET}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 1
    fi

    echo ""
    echo "${BOLD}Snapshot found: ${snap_root}${RESET}"

    # Check if @home is also in the snapshot
    local snap_home="${mount_point}/timeshift-btrfs/snapshots/${snapshot_name}/@home"
    local has_home=false
    [[ -d "$snap_home" ]] && has_home=true

    echo "  Root subvolume (@): yes"
    echo "  Home subvolume (@home): ${has_home}"
    echo ""

    local _confirm
    read -n 1 -rp "${YELLOW}Proceed with btrfs subvolume restore? (y/N) ${RESET}" _confirm < /dev/tty
    echo ""
    if [[ ! "$_confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Restore cancelled.${RESET}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')

    # Rename current @ subvolume to a backup
    local current_root="${mount_point}/@"
    local backup_name="@_backup_${timestamp}"

    echo ""
    echo "${CYAN}Backing up current root subvolume: @ → ${backup_name}${RESET}"
    if ! sudo mv "$current_root" "${mount_point}/${backup_name}"; then
        echo "${RED}✗ Failed to rename current @ subvolume${RESET}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 1
    fi

    # Create a writable snapshot from the selected snapshot's @
    echo "${CYAN}Creating writable snapshot from ${snapshot_name}/@...${RESET}"
    if ! sudo btrfs subvolume snapshot "$snap_root" "$current_root"; then
        echo "${RED}✗ Failed to create root snapshot — rolling back${RESET}"
        sudo mv "${mount_point}/${backup_name}" "$current_root"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 1
    fi
    echo "${GREEN}✓ Root subvolume restored${RESET}"

    # Restore @home if present in the snapshot
    if [[ "$has_home" == "true" ]]; then
        local current_home="${mount_point}/@home"
        if [[ -d "$current_home" ]]; then
            local home_backup="@home_backup_${timestamp}"
            echo "${CYAN}Backing up current home subvolume: @home → ${home_backup}${RESET}"
            if sudo mv "$current_home" "${mount_point}/${home_backup}"; then
                echo "${CYAN}Restoring @home from snapshot...${RESET}"
                if sudo btrfs subvolume snapshot "$snap_home" "$current_home"; then
                    echo "${GREEN}✓ Home subvolume restored${RESET}"
                else
                    echo "${YELLOW}⚠ Failed to restore @home — restoring backup${RESET}"
                    sudo mv "${mount_point}/${home_backup}" "$current_home"
                    log_warning "Failed to restore @home subvolume"
                fi
            else
                echo "${YELLOW}⚠ Failed to back up @home — skipping home restore${RESET}"
                log_warning "Failed to rename @home for backup"
            fi
        fi
    fi

    sudo sync

    echo ""
    echo "${GREEN}✓ Btrfs subvolume restore completed successfully${RESET}"
    log_success "Btrfs subvolume restore completed: ${snapshot_name}"
    [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
    return 0
}

# Restore a Timeshift snapshot by name.
# Uses rsync or btrfs subvolume swap directly instead of `timeshift --restore`
# because the native restore command always triggers an automatic reboot that
# cannot be suppressed, which breaks SSH sessions. By handling the restore
# ourselves, the script retains control and can offer a clean reboot prompt.
# Arguments:
#   $1 - Snapshot name/timestamp to restore
# Returns 0 on success, 1 on failure.
_timeshift_restore_snapshot() {
    local snapshot_name="$1"

    echo ""
    echo "${BOLD}${CYAN}Restoring Timeshift snapshot: ${snapshot_name}${RESET}"
    echo "${YELLOW}WARNING: This will restore your system to the selected snapshot.${RESET}"
    echo ""

    # Auto-detect the GRUB device (the whole disk containing the root partition).
    # Strip btrfs subvolume suffix (e.g. /dev/xvda3[/root] → /dev/xvda3)
    local grub_device=""
    local root_part
    root_part=$(findmnt -n -o SOURCE / 2>/dev/null | head -1 | sed 's/\[.*\]$//')
    if [[ -n "$root_part" ]]; then
        # Strip partition number/suffix to get the parent disk
        # Handles: /dev/sda1→sda, /dev/nvme0n1p2→nvme0n1, /dev/xvda1→xvda
        local disk_name
        disk_name=$(lsblk -no PKNAME "$root_part" 2>/dev/null | head -1)
        if [[ -n "$disk_name" ]]; then
            grub_device="/dev/${disk_name}"
        fi
    fi

    if [[ -n "$grub_device" && -b "$grub_device" ]]; then
        echo "${DIM}GRUB device detected: ${grub_device}${RESET}"
    else
        echo "${YELLOW}Could not auto-detect GRUB device — GRUB reinstall will be skipped${RESET}"
    fi

    # Route to the appropriate restore method based on Timeshift's configured mode,
    # not the filesystem type. A btrfs filesystem may still use RSYNC mode.
    local ts_mode="RSYNC"
    if grep -q '"btrfs_mode" *: *"true"' /etc/timeshift/timeshift.json 2>/dev/null; then
        ts_mode="BTRFS"
    fi

    if [[ "$ts_mode" == "BTRFS" ]]; then
        echo "${DIM}Timeshift mode: BTRFS — using subvolume restore${RESET}"
        if ! _timeshift_btrfs_restore "$snapshot_name"; then
            return 1
        fi
    else
        echo "${DIM}Timeshift mode: RSYNC — using rsync restore${RESET}"
        if ! _timeshift_rsync_restore "$snapshot_name"; then
            return 1
        fi
    fi

    # Reinstall GRUB bootloader (same as timeshift would do after restore)
    if [[ -n "$grub_device" && -b "$grub_device" ]]; then
        echo ""
        echo "${CYAN}Re-installing GRUB2 bootloader...${RESET}"
        if sudo grub-install "$grub_device" 2>&1; then
            echo "${GREEN}✓ GRUB installed to ${grub_device}${RESET}"
        else
            echo "${YELLOW}⚠ grub-install failed — boot may require manual repair${RESET}"
            log_warning "grub-install failed for device: ${grub_device}"
        fi

        echo "${CYAN}Updating GRUB menu...${RESET}"
        if sudo update-grub 2>&1; then
            echo "${GREEN}✓ GRUB menu updated${RESET}"
        else
            echo "${YELLOW}⚠ update-grub failed${RESET}"
            log_warning "update-grub failed after restore"
        fi
    fi

    echo ""
    echo "${GREEN}✓ Restore completed — a reboot is required to apply changes${RESET}"
    log_success "Timeshift restore completed: ${snapshot_name}"
    return 0
}

# Fallback: restore a Timeshift RSYNC snapshot directly using rsync.
# Timeshift RSYNC snapshots are plain directory trees, so we can restore
# without the timeshift binary. This works around timeshift segfaults and
# other bugs in the native --restore command.
# Arguments:
#   $1 - Snapshot name/timestamp to restore
_timeshift_rsync_restore() {
    local snapshot_name="$1"

    # Locate the snapshot on the backup device
    local snap_dir=""
    local backup_uuid=""
    backup_uuid=$(grep -o '"backup_device_uuid" *: *"[^"]*"' /etc/timeshift/timeshift.json 2>/dev/null \
        | grep -o '"[^"]*"$' | tr -d '"')

    if [[ -z "$backup_uuid" ]]; then
        echo "${RED}✗ Cannot determine Timeshift backup device from config${RESET}"
        return 1
    fi

    # Mount the backup device if not already mounted
    local backup_dev
    backup_dev=$(sudo blkid -U "$backup_uuid" 2>/dev/null)
    if [[ -z "$backup_dev" ]]; then
        echo "${RED}✗ Backup device with UUID ${backup_uuid} not found${RESET}"
        return 1
    fi

    # Mount the backup device. If already mounted (e.g. as / on a root device),
    # check whether the snapshot directory is accessible. If not, mount it at
    # our own path — timeshift may store snapshots in a subvolume only visible
    # from a dedicated mount.
    local mount_point=""
    local _did_mount=false

    mount_point=$(findmnt -n -o TARGET "$backup_dev" 2>/dev/null | head -1)

    # Verify the snapshot directory is actually reachable at this mount point
    if [[ -n "$mount_point" ]] && [[ ! -d "${mount_point}/timeshift/snapshots/${snapshot_name}" ]]; then
        # Existing mount (often /) doesn't expose the snapshot dir — remount
        mount_point=""
    fi

    if [[ -z "$mount_point" ]]; then
        mount_point="/run/timeshift/rsync-restore"
        sudo mkdir -p "$mount_point"
        if ! sudo mount "$backup_dev" "$mount_point"; then
            echo "${RED}✗ Failed to mount backup device ${backup_dev}${RESET}"
            return 1
        fi
        _did_mount=true
    fi

    # Find the snapshot directory
    snap_dir="${mount_point}/timeshift/snapshots/${snapshot_name}/localhost"
    if [[ ! -d "$snap_dir" ]]; then
        echo "${RED}✗ Snapshot directory not found: ${snap_dir}${RESET}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 1
    fi

    echo ""
    echo "${BOLD}Snapshot found: ${snap_dir}${RESET}"
    echo ""

    # Verify rsync is available
    if ! command -v rsync &>/dev/null; then
        echo "${RED}✗ rsync is not installed. Install it with: sudo apt install rsync${RESET}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 1
    fi

    # Standard system directories to exclude from restore (virtual/temp filesystems)
    local -a exclude_dirs=(
        '/dev/*'
        '/proc/*'
        '/sys/*'
        '/tmp/*'
        '/run/*'
        '/mnt/*'
        '/media/*'
        '/lost+found'
        '/swapfile'
    )

    # Also read Timeshift's own exclude list if available
    local ts_exclude_file="${mount_point}/timeshift/snapshots/${snapshot_name}/exclude.list"

    # Build rsync exclude arguments
    local -a rsync_excludes=()
    for ex in "${exclude_dirs[@]}"; do
        rsync_excludes+=(--exclude="$ex")
    done
    if [[ -f "$ts_exclude_file" ]]; then
        rsync_excludes+=(--exclude-from="$ts_exclude_file")
    fi

    # Dry-run first to show what would change
    echo "${CYAN}Running dry-run to preview changes...${RESET}"
    echo ""
    sudo rsync -avPHAXx --delete --dry-run "${rsync_excludes[@]}" \
        "${snap_dir}/" / 2>&1 | tail -5
    echo ""

    local _confirm
    read -n 1 -rp "${YELLOW}Proceed with rsync restore? (y/N) ${RESET}" _confirm < /dev/tty
    echo ""
    if [[ ! "$_confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Restore cancelled.${RESET}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 0
    fi

    echo ""
    echo "${CYAN}Restoring via rsync (this may take several minutes)...${RESET}"
    echo ""

    if sudo rsync -avPHAXx --delete "${rsync_excludes[@]}" \
        "${snap_dir}/" / 2>&1; then
        echo ""
        echo "${GREEN}✓ Rsync restore completed successfully${RESET}"
        log_success "Rsync fallback restore completed: ${snapshot_name}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 0
    else
        echo ""
        echo "${RED}✗ Rsync restore failed${RESET}"
        log_error "Rsync fallback restore failed for snapshot: ${snapshot_name}"
        [[ "$_did_mount" == "true" ]] && sudo umount "$mount_point" 2>/dev/null
        return 1
    fi
}

# Restore a Snapper snapshot by number.
# Arguments:
#   $1 - Snapshot number to rollback to
# Returns 0 on success, 1 on failure.
_snapper_restore_snapshot() {
    local snapshot_num="$1"

    echo ""
    echo "${BOLD}${CYAN}Rolling back to Snapper snapshot #${snapshot_num}${RESET}"
    echo "${YELLOW}WARNING: This will rollback your system to the selected snapshot.${RESET}"
    echo ""

    local snap_output
    if snap_output=$(sudo snapper rollback "$snapshot_num" 2>&1); then
        echo "${GREEN}✓ Snapper rollback completed successfully${RESET}"
        log_success "Snapper rollback completed: snapshot #${snapshot_num}"
        verbose "Snapper output: ${snap_output}"
        return 0
    else
        echo "${RED}✗ Snapper rollback failed${RESET}"
        log_error "Snapper rollback failed: ${snap_output}"
        verbose "Snapper error output: ${snap_output}"
        return 1
    fi
}

# Restore a snapshot using the active backend.
# Arguments:
#   $1 - Snapshot identifier (name for Timeshift, number for Snapper)
# Returns 0 on success, 1 on failure.
timeshift_restore_snapshot() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 1

    if [[ "$SNAPSHOT_BACKEND" == "snapper" ]]; then
        _snapper_restore_snapshot "$@"
    else
        _timeshift_restore_snapshot "$@"
    fi
}

# ============================================================================
# Snapshot Creation
# ============================================================================

# Create a snapshot before performing operations (dispatches to active backend).
# Arguments:
#   $1 - Comment/description for the snapshot (optional)
# Returns 0 on success or if Timeshift is not available (fail quietly).
timeshift_create_snapshot() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 0

    # Dispatch to Snapper backend if active
    if [[ "$SNAPSHOT_BACKEND" == "snapper" ]]; then
        _snapper_create_snapshot "$@"
        return $?
    fi

    # Guard against first-run mode: if the config file is missing, timeshift
    # cannot process --tags and will fail.  Re-run device setup instead.
    if [[ ! -f /etc/timeshift/timeshift.json ]]; then
        verbose "Timeshift: Config file missing — attempting device setup"
        if ! _timeshift_setup_device; then
            log_warning "Timeshift: Could not configure device — skipping snapshot"
            return 0
        fi
    fi

    local comment="${1:-linux_util: pre-operation snapshot}"

    echo ""
    echo "${BOLD}${CYAN}Creating Timeshift snapshot...${RESET}"
    echo "${DIM}Comment: ${comment}${RESET}"
    echo ""

    # Try with --tags O first; some timeshift versions (e.g. Ubuntu 24.04) have a
    # bug that rejects it, so fall back to creating without a tag.
    local ts_output ts_ok=false
    if ts_output=$(sudo timeshift --create --comments "$comment" --tags O --scripted 2>&1); then
        ts_ok=true
    elif ts_output=$(sudo timeshift --create --comments "$comment" --scripted 2>&1); then
        ts_ok=true
    fi

    if [[ "$ts_ok" == "true" ]]; then
        echo "${GREEN}✓ Timeshift snapshot created successfully${RESET}"
        log_success "Timeshift snapshot created: ${comment}"
        verbose "Timeshift output: ${ts_output}"

        # Refresh the cached last snapshot
        _timeshift_cache_last_snapshot
        return 0
    else
        echo "${YELLOW}⚠ Timeshift snapshot creation failed (continuing anyway)${RESET}"
        log_warning "Timeshift snapshot creation failed: ${ts_output}"
        verbose "Timeshift error output: ${ts_output}"
        # Fail quietly — don't block the script
        return 0
    fi
}
