#!/bin/bash

# ============================================================================
# Linux Utilities - Menu Module
# Provides TUI menu rendering and keyboard navigation functions
# ============================================================================

# Terminal control sequences
CSI=$'\x1b['
BOLD="${CSI}1m"
DIM="${CSI}2m"
RESET="${CSI}0m"
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
BLUE="${CSI}34m"
MAGENTA="${CSI}35m"
CYAN="${CSI}36m"

# Hide cursor
hide_cursor() { printf "${CSI}?25l"; }
# Show cursor
show_cursor() { printf "${CSI}?25h"; }
# Move cursor up N lines
cursor_up() { printf "${CSI}%dA" "$1"; }
# Move cursor to beginning of line
cursor_start() { printf "\r"; }
# Clear line
clear_line() { printf "${CSI}2K"; }

# Draw the menu
# COLUMN LAYOUT MATH (2-column format, do not modify):
# ├─ system_rows_per_column = ceil(system_tasks / 2)
# │  Example: 5 tasks → (5+1)/2 = 3 rows per column
# │  Result: [left column rows 0-2, right column rows 0-2, some empty]
# │
# ├─ rows_per_column = ceil(utilities_count / 2)
# │  Example: 14 utils → (14+1)/2 = 7 rows per column
# │  Result: [left column 0-6, right column 0-6]
# │
# ├─ Rendering order (top-down, then next column):
# │  LEFT column:  index 0, 1, 2, ...
# │  RIGHT column: index rows_per_column, rows_per_column+1, ...
# │
# └─ Item position calculation: idx = col * rows_per_column + row
#    LEFT (col=0):  0, 1, 2, 3...  RIGHT (col=1): 7, 8, 9...
draw_menu() {
    local total=${#UTILITIES[@]}
    local system_tasks=$SYSTEM_TASK_COUNT
    local utilities_start=$system_tasks
    local utilities_count=$((total - system_tasks))

    # Force 2 columns by calculating rows needed
    local system_rows_per_column=$(( (system_tasks + 1) / 2 ))  # ceil(system_tasks / 2) for 2 columns
    local rows_per_column=$(( (utilities_count + 1) / 2 ))      # ceil(utilities_count / 2) for 2 columns

    # Always 2 columns (unless fewer items)
    local num_columns=$(( utilities_count > 0 ? 2 : 0 ))
    local system_num_columns=$(( system_tasks > 0 ? 2 : 0 ))

    local sys_col_width=40
    local util_col_width=40

    local dry_run_label=""
    [[ "$DRY_RUN" == "true" ]] && dry_run_label="  ${BOLD}${YELLOW}[DRY RUN]${RESET}"

    echo ""
    echo "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${CYAN}║   Linux System Setup & Utilities - Select Programs/Tasks     ║${RESET}${dry_run_label}"
    echo "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # Display commit version info (values pre-fetched once in run_selection_menu)
    echo "       Script commit: ${BOLD}${CACHED_LOCAL_COMMIT}${RESET}  |  Latest commit: ${BOLD}${CACHED_REMOTE_COMMIT}${RESET}"
    if [[ "$CACHED_LOCAL_COMMIT" != "unknown" && "$CACHED_REMOTE_COMMIT" != "unknown" && "$CACHED_LOCAL_COMMIT" != "$CACHED_REMOTE_COMMIT" ]]; then
        echo "  ${BOLD}${YELLOW}Script out of date, please update.${RESET}"
    fi
    echo ""

    # Display System Tasks section
    echo "${BOLD}${CYAN}System Tasks:${RESET}"
    for ((row=0; row<system_rows_per_column; row++)); do
        local line=""
        for ((col=0; col<system_num_columns; col++)); do
            local task_idx=$((col * system_rows_per_column + row))
            local i=$task_idx

            # Skip if index is beyond system tasks
            if [[ $i -ge $system_tasks ]]; then
                continue
            fi

            local prefix="  "
            local checkbox="[ ]"
            local name="${UTILITIES[$i]}"
            local status_tag=""

            # Highlight current item
            if [[ $i -eq $CURSOR ]]; then
                prefix="${BOLD}${BLUE}▸ ${RESET}"
            fi

            # Show selection / update-queued state
            if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
                checkbox="${YELLOW}[U]${RESET}"
            elif [[ ${SELECTED[$i]} -eq 1 ]]; then
                checkbox="${GREEN}[✓]${RESET}"
            fi

            # VERSION DISPLAY LOGIC:
            # ├─ If utility is installed AND has version info → "(vX.Y.Z)" in MAGENTA
            # ├─ If utility is installed but NO version info → "(installed)" in MAGENTA
            # └─ If utility not installed → no status tag displayed
            # IMPORTANT: INSTALLED_VERSIONS[$i] is populated by get_version_*() functions
            # during check_installed_utilities() (line 3220-3232)
            # Show installed status (with version if available)
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                local ver="${INSTALLED_VERSIONS[$i]:-}"
                if [[ -n "$ver" ]]; then
                    status_tag=" ${MAGENTA}(v${ver})${RESET}"
                else
                    status_tag=" ${MAGENTA}(installed)${RESET}"
                fi
            fi

            local item=""
            if [[ $i -eq $CURSOR ]]; then
                item="${prefix}${checkbox} ${BOLD}${name}${RESET}${status_tag}"
            else
                item="${prefix}${checkbox} ${name}${status_tag}"
            fi

            # COLUMN PADDING CALCULATION (for alignment in 2-column layout):
            # Spacing is NOT hard-coded—it's calculated based on item width.
            # util_col_width = 40 chars max per column (line 3286)
            # visible_len = actual width of: "  " + "[X]" + " " + name + " (vX.Y.Z)"
            # padding = util_col_width - visible_len (minimum 2 spaces)
            # This ensures right column aligns regardless of name/version length.
            # Add padding for columns using visible width (no ANSI codes)
            if [[ $col -lt $((system_num_columns - 1)) ]]; then
                local plain_status=""
                if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                    local pver="${INSTALLED_VERSIONS[$i]:-}"
                    if [[ -n "$pver" ]]; then
                        plain_status=" (v${pver})"
                    else
                        plain_status=" (installed)"
                    fi
                fi
                # Visible chars: prefix (2), checkbox (3), space (1), name, status text
                local visible_len=$((2 + 3 + 1 + ${#name} + ${#plain_status}))
                local padding=$((util_col_width - visible_len))
                [[ $padding -lt 2 ]] && padding=2
                item="${item}$(printf '%*s' $padding '')"
            fi

            line="${line}${item}"
        done
        echo "$line"
    done

    echo ""
    echo "${DIM}----------------------------------------------------------------${RESET}"
    echo ""
    echo "${BOLD}${CYAN}Utilities:${RESET}"

    # Build items for utilities in columns
    # RENDERING LOGIC IDENTICAL TO SYSTEM TASKS SECTION ABOVE:
    # Loop through rows (0 to rows_per_column-1), then columns (left=0, right=1)
    # Calculate array index: utilities_start + (col * rows_per_column + row)
    # This produces left column top-to-bottom, then right column top-to-bottom
    for ((row=0; row<rows_per_column; row++)); do
        local line=""
        for ((col=0; col<num_columns; col++)); do
            local util_idx=$((col * rows_per_column + row))
            local i=$((utilities_start + util_idx))

            # Skip if index is beyond total items
            if [[ $i -ge $total ]]; then
                continue
            fi

            local prefix="  "
            local checkbox="[ ]"
            local name="${UTILITIES[$i]}"
            local status_tag=""

            # Highlight current item
            if [[ $i -eq $CURSOR ]]; then
                prefix="${BOLD}${BLUE}▸ ${RESET}"
            fi

            # Show selection / update-queued state
            if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
                checkbox="${YELLOW}[U]${RESET}"
            elif [[ ${SELECTED[$i]} -eq 1 ]]; then
                checkbox="${GREEN}[✓]${RESET}"
            fi

            # Show installed status (with version if available)
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                local ver="${INSTALLED_VERSIONS[$i]:-}"
                if [[ -n "$ver" ]]; then
                    status_tag=" ${MAGENTA}(v${ver})${RESET}"
                else
                    status_tag=" ${MAGENTA}(installed)${RESET}"
                fi
            fi

            local item=""
            if [[ $i -eq $CURSOR ]]; then
                item="${prefix}${checkbox} ${BOLD}${name}${RESET}${status_tag}"
            else
                item="${prefix}${checkbox} ${name}${status_tag}"
            fi

            # Add padding for columns using visible width (no ANSI codes)
            if [[ $col -lt $((num_columns - 1)) ]]; then
                local plain_status=""
                if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                    local pver="${INSTALLED_VERSIONS[$i]:-}"
                    if [[ -n "$pver" ]]; then
                        plain_status=" (v${pver})"
                    else
                        plain_status=" (installed)"
                    fi
                fi
                # Visible chars: prefix (2), checkbox (3), space (1), name, status text
                local visible_len=$((2 + 3 + 1 + ${#name} + ${#plain_status}))
                local padding=$((util_col_width - visible_len))
                [[ $padding -lt 2 ]] && padding=2
                item="${item}$(printf '%*s' $padding '')"
            fi

            line="${line}${item}"
        done
        echo "$line"
    done

    echo ""
    echo "----------------------------------------------------------------"

    # Count selected items and categorize actions
    local install_count=0
    local uninstall_count=0
    local update_count=0
    for ((i=0; i<total; i++)); do
        if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
            ((update_count++))
        elif [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                ((uninstall_count++))
            else
                ((install_count++))
            fi
        fi
    done

    echo "${CYAN}Actions: ${GREEN}Install: ${install_count}${RESET} | ${RED}Uninstall: ${uninstall_count}${RESET} | ${YELLOW}Update: ${update_count}${RESET}"
    echo ""
    echo "${YELLOW}↑/↓/←/→ navigate  SPACE select  U update installed  A select-all  D deselect-all  ENTER confirm  Q quit${RESET}"
    echo ""
}

# Redraw the menu (clear and redraw for reliability)
redraw_menu() {
    clear
    draw_menu
}

# Dynamically build navigational columns used by keyboard navigation.
# Each visual display-column (spanning both System Tasks and Utilities) becomes
# one navigational column.  Supports any number of columns.
# Results are stored in NAV_FLAT (packed indices), NAV_COL_START (offsets),
# NAV_COL_SIZE (lengths), and NAV_NUM_COLS.
build_nav_columns() {
    NAV_FLAT=()
    NAV_COL_START=()
    NAV_COL_SIZE=()
    NAV_COL_SYS_SIZE=()   # system-task count per column (for section-aware LEFT/RIGHT)
    NAV_NUM_COLS=0
    local total=${#UTILITIES[@]}
    local sys_tasks=$SYSTEM_TASK_COUNT
    local utilities_count=$(( total - sys_tasks ))

    # Force 2 columns by calculating rows needed
    local sys_rows=$(( (sys_tasks + 1) / 2 ))         # ceil(sys_tasks / 2) for 2 columns
    local util_rows=$(( (utilities_count + 1) / 2 ))  # ceil(utilities_count / 2) for 2 columns

    # Always 2 columns (unless fewer items)
    local sys_cols=$(( sys_tasks > 0 ? 2 : 0 ))
    local util_cols=$(( utilities_count > 0 ? 2 : 0 ))
    local max_cols=$(( sys_cols > util_cols ? sys_cols : util_cols ))
    NAV_NUM_COLS=$max_cols

    for (( c=0; c<max_cols; c++ )); do
        NAV_COL_START+=( ${#NAV_FLAT[@]} )
        local col_size=0
        local col_sys_size=0

        # Add system task items for this column
        for (( r=0; r<sys_rows; r++ )); do
            local idx=$(( c * sys_rows + r ))
            if (( idx < sys_tasks )); then
                NAV_FLAT+=( "$idx" )
                (( col_size++ ))
                (( col_sys_size++ ))
            fi
        done

        # Add utility items for this column
        for (( r=0; r<util_rows; r++ )); do
            local u_idx=$(( c * util_rows + r ))
            if (( u_idx < utilities_count )); then
                NAV_FLAT+=( "$(( sys_tasks + u_idx ))" )
                (( col_size++ ))
            fi
        done

        NAV_COL_SIZE+=( "$col_size" )
        NAV_COL_SYS_SIZE+=( "$col_sys_size" )
    done
}

# Read a single keypress
read_key() {
    local key
    IFS= read -rsn1 key

    # Check for escape sequence (arrow keys)
    if [[ $key == $ESC ]]; then
        read -rsn2 -t 0.1 key
        case "$key" in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            '[C') echo "RIGHT" ;;
            '[D') echo "LEFT" ;;
            *) echo "OTHER" ;;
        esac
    elif [[ $key == "" ]]; then
        echo "ENTER"
    elif [[ $key == " " ]]; then
        echo "SPACE"
    elif [[ $key == "q" ]] || [[ $key == "Q" ]]; then
        echo "QUIT"
    elif [[ $key == "a" ]] || [[ $key == "A" ]]; then
        echo "SELECT_ALL"
    elif [[ $key == "d" ]] || [[ $key == "D" ]]; then
        echo "DESELECT_ALL"
    elif [[ $key == "u" ]] || [[ $key == "U" ]]; then
        echo "UPDATE"
    else
        echo "OTHER"
    fi
}

# Navigation arrays (initialized in run_selection_menu)
declare -a NAV_FLAT=()
declare -a NAV_COL_START=()
declare -a NAV_COL_SIZE=()
declare -a NAV_COL_SYS_SIZE=()
NAV_NUM_COLS=0

# Escape key for terminal input
ESC=$'\x1b'
