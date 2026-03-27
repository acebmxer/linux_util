#!/bin/bash
# Snapshot system tasks — Create Snapshot and Restore Snapshot
# Uses the snapshot backend (Timeshift or Snapper) configured in lib/snapshot.sh

# --- Create Snapshot ---

setup_create_snapshot() {
    if [[ "$TIMESHIFT_AVAILABLE" != "true" ]]; then
        warn "No snapshot tool available. Please install Timeshift or configure Snapper first."
        return 1
    fi

    local _snap_label="Timeshift"
    [[ "$SNAPSHOT_BACKEND" == "snapper" ]] && _snap_label="Snapper"

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Create ${_snap_label} Snapshot                                ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    read -rp "Enter a description for this snapshot (or press Enter for default): " _snap_desc < /dev/tty
    [[ -z "$_snap_desc" ]] && _snap_desc="linux_util: manual snapshot"

    timeshift_create_snapshot "$_snap_desc"
}

# --- Restore Snapshot ---

setup_restore_snapshot() {
    if [[ "$TIMESHIFT_AVAILABLE" != "true" ]]; then
        warn "No snapshot tool available. Please install Timeshift or configure Snapper first."
        return 1
    fi

    local _snap_label="Timeshift"
    [[ "$SNAPSHOT_BACKEND" == "snapper" ]] && _snap_label="Snapper"

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Restore ${_snap_label} Snapshot                               ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    echo "Available snapshots:"
    echo ""

    if ! timeshift_list_snapshots; then
        warn "No snapshots found. Nothing to restore."
        return 1
    fi

    if [[ ${#SNAPSHOT_NAMES[@]} -eq 0 ]]; then
        warn "No snapshots found. Nothing to restore."
        return 1
    fi

    # Display numbered choices
    echo "Select a snapshot to restore:"
    echo ""
    for ((i=0; i<${#SNAPSHOT_NAMES[@]}; i++)); do
        local snap_name="${SNAPSHOT_NAMES[$i]}"
        local snap_date="${snap_name%%_*}"
        local snap_time="${snap_name##*_}"
        snap_time="${snap_time//-/:}"
        local snap_display
        snap_display="$(date -d "${snap_date} ${snap_time}" '+%d %b %Y %I:%M %p' 2>/dev/null)" \
            || snap_display="${snap_name}"
        echo "  $((i + 1))) ${snap_display}"
    done
    echo ""
    echo "  0) Cancel"
    echo ""

    local _choice
    while true; do
        read -rp "Enter selection [0-${#SNAPSHOT_NAMES[@]}]: " _choice < /dev/tty
        if [[ "$_choice" == "0" ]]; then
            echo "${YELLOW}Restore cancelled.${RESET}"
            return 2
        fi
        if [[ "$_choice" =~ ^[0-9]+$ ]] && (( _choice >= 1 && _choice <= ${#SNAPSHOT_NAMES[@]} )); then
            break
        fi
        echo "${RED}Invalid selection. Please try again.${RESET}"
    done

    local _selected="${SNAPSHOT_NAMES[$((_choice - 1))]}"
    echo ""
    echo "Selected snapshot: ${BOLD}${_selected}${RESET}"
    echo ""

    # Confirm before proceeding
    read -n 1 -rp "${YELLOW}This will restore your system to snapshot ${_selected}. Continue? (y/N) ${RESET}" _confirm < /dev/tty
    echo ""
    if [[ ! "$_confirm" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}Restore cancelled.${RESET}"
        return 2
    fi

    # Create a safety snapshot before restoring
    echo ""
    echo "${CYAN}Creating safety snapshot before restore...${RESET}"
    timeshift_create_snapshot "before restore"

    # Perform the restore
    timeshift_restore_snapshot "$_selected"
}
