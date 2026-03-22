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
    local root_dev root_uuid
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
    root_uuid=$(blkid -s UUID -o value "$root_dev" 2>/dev/null)

    # List devices via timeshift
    local devices_output
    devices_output=$(sudo timeshift --list-devices 2>&1) || true

    echo "$devices_output"
    echo ""

    if [[ -n "$root_dev" && -n "$root_uuid" ]]; then
        echo "Current boot device detected: ${BOLD}${root_dev}${RESET} (UUID: ${root_uuid})"
        echo ""
        read -n 1 -rp "Use boot device ${root_dev} for Timeshift snapshots? (Y/n) " _ts_choice
        echo ""

        if [[ ! "$_ts_choice" =~ ^[Nn]$ ]]; then
            # Configure Timeshift to use the boot device
            sudo timeshift --snapshot-device "$root_uuid" --scripted 2>/dev/null || \
            sudo timeshift --snapshot-device "$root_dev" --scripted 2>/dev/null || {
                # Fallback: write to config directly
                _timeshift_write_device_config "$root_uuid"
            }
            echo "${GREEN}Timeshift configured to use: ${root_dev}${RESET}"
            log_info "Timeshift: Configured backup device ${root_dev} (UUID: ${root_uuid})"
            return 0
        fi
    else
        echo "${YELLOW}Could not auto-detect boot device.${RESET}"
        echo ""
    fi

    # Manual device selection
    echo "Please enter the device path (e.g., /dev/sda1) or UUID for Timeshift snapshots:"
    read -rp "> " _ts_manual_dev

    if [[ -z "$_ts_manual_dev" ]]; then
        warn "No device selected. Timeshift snapshots will not be available."
        TIMESHIFT_AVAILABLE=false
        return 1
    fi

    # If user entered a UUID, use it directly; otherwise get UUID from device path
    if [[ "$_ts_manual_dev" =~ ^[0-9a-fA-F-]+$ ]]; then
        local manual_uuid="$_ts_manual_dev"
    else
        local manual_uuid
        manual_uuid=$(blkid -s UUID -o value "$_ts_manual_dev" 2>/dev/null)
    fi

    if [[ -n "$manual_uuid" ]]; then
        sudo timeshift --snapshot-device "$manual_uuid" --scripted 2>/dev/null || \
        sudo timeshift --snapshot-device "$_ts_manual_dev" --scripted 2>/dev/null || {
            _timeshift_write_device_config "$manual_uuid"
        }
        echo "${GREEN}Timeshift configured to use: ${_ts_manual_dev}${RESET}"
        log_info "Timeshift: Configured backup device ${_ts_manual_dev} (UUID: ${manual_uuid:-unknown})"
    else
        sudo timeshift --snapshot-device "$_ts_manual_dev" --scripted 2>/dev/null || {
            warn "Failed to configure Timeshift device. Snapshots may not work."
            TIMESHIFT_AVAILABLE=false
            return 1
        }
        echo "${GREEN}Timeshift configured to use: ${_ts_manual_dev}${RESET}"
        log_info "Timeshift: Configured backup device ${_ts_manual_dev}"
    fi

    return 0
}

# Write device UUID directly to Timeshift config as a fallback.
_timeshift_write_device_config() {
    local uuid="$1"
    local config_file="/etc/timeshift/timeshift.json"

    if [[ ! -f "$config_file" ]]; then
        sudo mkdir -p /etc/timeshift
        sudo tee "$config_file" > /dev/null <<TSCFG
{
  "backup_device_uuid" : "${uuid}",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "false",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
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

# Restore a Timeshift snapshot by name.
# Arguments:
#   $1 - Snapshot name/timestamp to restore
# Returns 0 on success, 1 on failure.
_timeshift_restore_snapshot() {
    local snapshot_name="$1"

    echo ""
    echo "${BOLD}${CYAN}Restoring Timeshift snapshot: ${snapshot_name}${RESET}"
    echo "${YELLOW}WARNING: This will restore your system to the selected snapshot.${RESET}"
    echo ""

    local ts_output
    if ts_output=$(sudo timeshift --restore --snapshot "$snapshot_name" --scripted --yes 2>&1); then
        echo "${GREEN}✓ Timeshift restore completed successfully${RESET}"
        log_success "Timeshift restore completed: ${snapshot_name}"
        verbose "Timeshift output: ${ts_output}"
        return 0
    else
        echo "${RED}✗ Timeshift restore failed${RESET}"
        log_error "Timeshift restore failed: ${ts_output}"
        verbose "Timeshift error output: ${ts_output}"
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
