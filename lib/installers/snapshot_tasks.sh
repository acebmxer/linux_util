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
    while true; do
        read -n 1 -rp "${YELLOW}This will restore your system to snapshot ${_selected}. Continue? (y/N) ${RESET}" _confirm < /dev/tty
        echo ""
        [[ $'\e' == "$_confirm" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
        _confirm="${_confirm:-N}"
        case "$_confirm" in
            y|Y) break ;;
            n|N) echo "${YELLOW}Restore cancelled.${RESET}"; return 2 ;;
            *) echo "  Please press Y or N." ;;
        esac
    done

    # Offer a safety snapshot before restoring
    echo ""
    timeshift_prompt_create_snapshot "before restore"

    # Perform the restore
    timeshift_restore_snapshot "$_selected"
}

# --- Delete Snapshot(s) ---

setup_delete_snapshot() {
    if [[ "$TIMESHIFT_AVAILABLE" != "true" ]]; then
        warn "No snapshot tool available. Please install Timeshift or configure Snapper first."
        return 1
    fi

    local _snap_label="Timeshift"
    [[ "$SNAPSHOT_BACKEND" == "snapper" ]] && _snap_label="Snapper"

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Delete ${_snap_label} Snapshot(s)                             ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    echo "Available snapshots:"
    echo ""

    if ! timeshift_list_snapshots; then
        warn "No snapshots found. Nothing to delete."
        return 1
    fi

    if [[ ${#SNAPSHOT_NAMES[@]} -eq 0 ]]; then
        warn "No snapshots found. Nothing to delete."
        return 1
    fi

    # Display numbered list
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
    echo "Enter the number(s) to delete (e.g. 1 or 1 3 5), or 0 to cancel:"
    echo ""

    local _input
    read -rp "> " _input < /dev/tty

    if [[ -z "$_input" || "$_input" == "0" ]]; then
        echo "${YELLOW}Delete cancelled.${RESET}"
        return 2
    fi

    # Resolve selections to snapshot names
    local -a _to_delete=()
    local _invalid=false
    for _num in $_input; do
        if [[ "$_num" =~ ^[0-9]+$ ]] && (( _num >= 1 && _num <= ${#SNAPSHOT_NAMES[@]} )); then
            _to_delete+=("${SNAPSHOT_NAMES[$((_num - 1))]}")
        else
            echo "${RED}Invalid selection: ${_num}${RESET}"
            _invalid=true
        fi
    done

    if [[ "$_invalid" == "true" || ${#_to_delete[@]} -eq 0 ]]; then
        echo "${YELLOW}No valid snapshots selected. Delete cancelled.${RESET}"
        return 2
    fi

    echo ""
    echo "${YELLOW}The following snapshots will be permanently deleted:${RESET}"
    for snap in "${_to_delete[@]}"; do
        echo "  - ${snap}"
    done
    echo ""

    local _confirm
    while true; do
        read -n 1 -rp "${YELLOW}Proceed? (y/N) ${RESET}" _confirm < /dev/tty
        echo ""
        [[ $'\e' == "$_confirm" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
        _confirm="${_confirm:-N}"
        case "$_confirm" in
            y|Y) break ;;
            n|N) echo "${YELLOW}Delete cancelled.${RESET}"; return 2 ;;
            *) echo "  Please press Y or N." ;;
        esac
    done

    if [[ "$SNAPSHOT_BACKEND" == "snapper" ]]; then
        _snapper_delete_snapshots "${_to_delete[@]}"
    else
        timeshift_delete_snapshots "${_to_delete[@]}"
    fi
}
