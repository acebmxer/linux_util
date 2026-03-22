#!/bin/bash

# ============================================================================
# Linux Utilities - Timeshift Module
# Provides Timeshift snapshot integration for Debian/Ubuntu-based systems.
# If Timeshift is not installed or the system is not Debian-family,
# all functions fail quietly and the script continues normally.
# ============================================================================

# Global state
TIMESHIFT_AVAILABLE=false
TIMESHIFT_LAST_SNAPSHOT=""

# ============================================================================
# Timeshift Detection & Initialization
# ============================================================================

# Check if Timeshift is installed and the system is Debian-family.
# Sets TIMESHIFT_AVAILABLE=true if both conditions are met.
timeshift_init() {
    # Only support Debian-family systems (Ubuntu, Debian, Mint, Pop, etc.)
    if [[ "${DISTRO_FAMILY:-}" != "debian" ]]; then
        verbose "Timeshift: Skipping — not a Debian/Ubuntu-based system"
        return 0
    fi

    if ! command -v timeshift &>/dev/null; then
        verbose "Timeshift: Not installed — skipping snapshot integration"
        return 0
    fi

    TIMESHIFT_AVAILABLE=true
    verbose "Timeshift: Detected and available"

    # Check if a backup device is configured; if not, set one up
    if ! _timeshift_has_device; then
        _timeshift_setup_device
    fi

    # Cache the last snapshot info for the banner
    _timeshift_cache_last_snapshot
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
# Snapshot Creation
# ============================================================================

# Create a Timeshift snapshot before performing operations.
# Arguments:
#   $1 - Comment/description for the snapshot (optional)
# Returns 0 on success or if Timeshift is not available (fail quietly).
timeshift_create_snapshot() {
    [[ "$TIMESHIFT_AVAILABLE" != "true" ]] && return 0

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
