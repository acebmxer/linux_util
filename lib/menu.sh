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

# Respect the NO_COLOR standard (https://no-color.org/), non-interactive terminals,
# and the --no-color CLI flag.
if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${NO_COLOR_FLAG:-false}" == "true" ]]; then
    BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN=""
fi

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
    local system_tasks=${#SYSTEM_TASKS[@]}
    local utilities_start=$system_tasks
    local utilities_count=$((total - system_tasks))

    # Re-query terminal width on every draw (supports live resize via SIGWINCH)
    local term_width=${COLUMNS:-80}

    # Force 2 columns by calculating rows needed
    local system_rows_per_column=$(( (system_tasks + 1) / 2 ))  # ceil(system_tasks / 2) for 2 columns
    local rows_per_column=$(( (utilities_count + 1) / 2 ))      # ceil(utilities_count / 2) for 2 columns

    # Always 2 columns (unless fewer items)
    local num_columns=$(( utilities_count > 0 ? 2 : 0 ))
    local system_num_columns=$(( system_tasks > 0 ? 2 : 0 ))

    local col_width=40
    local content_width=$(( col_width * 2 ))

    # Centre the content block horizontally in the terminal
    local margin=0
    (( term_width > content_width )) && margin=$(( (term_width - content_width) / 2 ))
    local pad=""
    (( margin > 0 )) && printf -v pad '%*s' "$margin" ''

    # Clear-to-end-of-line — appended to every line so shorter redraws
    # overwrite longer previous lines without leaving ghost characters
    local eol=$'\033[K'

    local dry_run_label=""
    [[ "$DRY_RUN" == "true" ]] && dry_run_label="  ${BOLD}${YELLOW}[DRY RUN]${RESET}"

    # Pre-build repeated-character strings without subshells
    local inner_width=$((content_width - 2))
    local border_fill sep_fill
    printf -v border_fill '%*s' "$inner_width" ''; border_fill="${border_fill// /═}"
    printf -v sep_fill '%*s' "$content_width" ''; sep_fill="${sep_fill// /-}"

    # Build entire menu into a single buffer and flush at once.
    # This eliminates SSH flicker caused by many individual write() syscalls.
    local _buf=""

    # Cursor home — no clear-screen, overwrite in place for flicker-free rendering.
    # Per-line \033[K and trailing \033[J clean up stale characters.
    _buf+=$'\033[H'

    # ── Banner (dynamic width, centred text) ──
    local banner_text="Linux System Setup & Utilities - Select Programs/Tasks"
    local banner_len=${#banner_text}
    local blpad=$(( (inner_width - banner_len) / 2 ))
    local brpad=$(( inner_width - banner_len - blpad ))
    local blspaces="" brspaces=""
    (( blpad > 0 )) && printf -v blspaces '%*s' "$blpad" ''
    (( brpad > 0 )) && printf -v brspaces '%*s' "$brpad" ''

    _buf+="${pad}${eol}"$'\n'
    _buf+="${pad}${BOLD}${CYAN}╔${border_fill}╗${RESET}${eol}"$'\n'
    _buf+="${pad}${BOLD}${CYAN}║${blspaces}${banner_text}${brspaces}║${RESET}${dry_run_label}${eol}"$'\n'
    _buf+="${pad}${BOLD}${CYAN}╚${border_fill}╝${RESET}${eol}"$'\n'
    _buf+="${pad}${eol}"$'\n'

    # ── Commit & system info (centred within content area) ──
    local _commit_plain="Script commit: ${CACHED_LOCAL_COMMIT}  |  Latest commit: ${CACHED_REMOTE_COMMIT}"
    local _clpad=$(( (content_width - ${#_commit_plain}) / 2 ))
    (( _clpad < 0 )) && _clpad=0
    local _cspaces=""
    (( _clpad > 0 )) && printf -v _cspaces '%*s' "$_clpad" ''
    _buf+="${pad}${_cspaces}Script commit: ${BOLD}${CACHED_LOCAL_COMMIT}${RESET}  |  Latest commit: ${BOLD}${CACHED_REMOTE_COMMIT}${RESET}${eol}"$'\n'

    if [[ "$CACHED_LOCAL_COMMIT" != "unknown" && "$CACHED_REMOTE_COMMIT" != "unknown" && "$CACHED_LOCAL_COMMIT" != "$CACHED_REMOTE_COMMIT" ]]; then
        local _ood_text="Script out of date, please update."
        local _olpad=$(( (content_width - ${#_ood_text}) / 2 ))
        (( _olpad < 0 )) && _olpad=0
        local _ospaces=""
        (( _olpad > 0 )) && printf -v _ospaces '%*s' "$_olpad" ''
        _buf+="${pad}${_ospaces}${BOLD}${YELLOW}${_ood_text}${RESET}${eol}"$'\n'
    fi

    local _sys_plain="Detected System: ${DISTRO_NAME}   Version: ${DISTRO_VERSION_ID}"
    local _slpad=$(( (content_width - ${#_sys_plain}) / 2 ))
    (( _slpad < 0 )) && _slpad=0
    local _sspaces=""
    (( _slpad > 0 )) && printf -v _sspaces '%*s' "$_slpad" ''
    _buf+="${pad}${_sspaces}Detected System: ${BOLD}${DISTRO_NAME}${RESET}   Version: ${BOLD}${DISTRO_VERSION_ID}${RESET}${eol}"$'\n'

    # Display Timeshift last snapshot if available
    if [[ "${TIMESHIFT_AVAILABLE:-false}" == "true" ]]; then
        local _snap_label="Timeshift"
        [[ "${SNAPSHOT_BACKEND:-}" == "snapper" ]] && _snap_label="Snapper"
        local _ts_plain="Last ${_snap_label} Snapshot: ${TIMESHIFT_LAST_SNAPSHOT:-No snapshots found}"
        local _tlpad=$(( (content_width - ${#_ts_plain}) / 2 ))
        (( _tlpad < 0 )) && _tlpad=0
        local _tspaces=""
        (( _tlpad > 0 )) && printf -v _tspaces '%*s' "$_tlpad" ''
        _buf+="${pad}${_tspaces}Last ${_snap_label} Snapshot: ${BOLD}${TIMESHIFT_LAST_SNAPSHOT:-No snapshots found}${RESET}${eol}"$'\n'
    fi

    _buf+="${pad}${eol}"$'\n'

    # Display System Tasks section
    _buf+="${pad}${BOLD}${CYAN}System Tasks:${RESET}${eol}"$'\n'
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
                local padding=$((col_width - visible_len))
                [[ $padding -lt 2 ]] && padding=2
                item="${item}$(printf '%*s' $padding '')"
            fi

            line="${line}${item}"
        done
        _buf+="${pad}${line}${eol}"$'\n'
    done

    _buf+="${pad}${eol}"$'\n'
    _buf+="${pad}${DIM}${sep_fill}${RESET}${eol}"$'\n'
    _buf+="${pad}${eol}"$'\n'
    _buf+="${pad}${BOLD}${CYAN}Utilities:${RESET}${eol}"$'\n'

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
                local padding=$((col_width - visible_len))
                [[ $padding -lt 2 ]] && padding=2
                item="${item}$(printf '%*s' $padding '')"
            fi

            line="${line}${item}"
        done
        _buf+="${pad}${line}${eol}"$'\n'
    done

    _buf+="${pad}${eol}"$'\n'
    _buf+="${pad}${sep_fill}${eol}"$'\n'

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

    _buf+="${pad}${CYAN}Actions: ${GREEN}Install: ${install_count}${RESET} | ${RED}Uninstall: ${uninstall_count}${RESET} | ${YELLOW}Update: ${update_count}${RESET}${eol}"$'\n'
    _buf+="${pad}${eol}"$'\n'
    _buf+="${pad}${YELLOW}↑/↓/←/→ navigate  SPACE select  U update installed  A select-all  D deselect-all  ENTER confirm  Q quit${RESET}${eol}"$'\n'
    _buf+="${pad}${eol}"$'\n'
    _buf+="${pad}${DIM}Legend: ${GREEN}[✓]${RESET}${DIM} select  ${YELLOW}[U]${RESET}${DIM} update  ${RESET}${DIM}[ ]${RESET}${DIM} none  ${MAGENTA}(installed)${RESET}${DIM} = on system${RESET}${eol}"$'\n'
    _buf+="${pad}${DIM}[✓] on installed = uninstall; [✓] on missing = install; [U] on installed = update.${RESET}${eol}"$'\n'

    # Clear any leftover lines below from a previous (taller) render
    _buf+=$'\033[J'

    # Single write flushes entire menu — eliminates per-line SSH flicker
    printf '%s' "$_buf"
}

# Redraw the menu in-place — cursor home is embedded in draw_menu's buffer
# so the entire position-move + repaint is a single atomic write.
redraw_menu() {
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
    local sys_tasks=${#SYSTEM_TASKS[@]}
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

# Main selection loop
run_selection_menu() {
    local total=${#UTILITIES[@]}

    # Check which utilities are already installed
    check_installed_utilities

    # Fetch commit info once to avoid network call on every redraw
    CACHED_LOCAL_COMMIT=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local _remote_full
    _remote_full=$(git -C "$SCRIPT_DIR" ls-remote origin HEAD 2>/dev/null | awk '{print $1}')
    if [[ -n "$_remote_full" ]]; then
        CACHED_REMOTE_COMMIT="${_remote_full:0:7}"
    else
        CACHED_REMOTE_COMMIT="unknown"
    fi

    # Build navigation column layout once (dynamic — adapts to UTILITIES count)
    build_nav_columns

    # Setup terminal
    hide_cursor
    stty -echo

    # Cleanup on exit
    trap 'show_cursor; stty echo; echo ""; cleanup_on_exit' EXIT

    # Redraw on terminal resize (update COLUMNS for centering recalculation)
    trap 'COLUMNS=$(tput cols 2>/dev/null || echo 80); redraw_menu' WINCH

    # Initial draw
    clear
    draw_menu

    while true; do
        local key=$(read_key)

        # Multi-column navigation model.
        # UP/DOWN stays within the same column (wrapping at the ends);
        # LEFT/RIGHT jumps one column in that direction to the same row.

        # Determine which column the cursor is in and its position within it.
        local _nav_col=-1
        local _nav_pos=-1
        local _c _r
        for (( _c=0; _c<NAV_NUM_COLS; _c++ )); do
            local _start=${NAV_COL_START[$_c]}
            local _size=${NAV_COL_SIZE[$_c]}
            for (( _r=0; _r<_size; _r++ )); do
                if [[ ${NAV_FLAT[$(( _start + _r ))]} -eq $CURSOR ]]; then
                    _nav_col=$_c
                    _nav_pos=$_r
                    break 2
                fi
            done
        done
        # Fallback: keep cursor as-is if somehow not found
        [[ $_nav_col -eq -1 ]] && { _nav_col=0; _nav_pos=0; }

        local _cur_start=${NAV_COL_START[$_nav_col]}
        local _cur_size=${NAV_COL_SIZE[$_nav_col]}

        case "$key" in
            UP)
                local _new_pos=$(( (_nav_pos - 1 + _cur_size) % _cur_size ))
                CURSOR=${NAV_FLAT[$(( _cur_start + _new_pos ))]}
                redraw_menu
                ;;
            DOWN)
                local _new_pos=$(( (_nav_pos + 1) % _cur_size ))
                CURSOR=${NAV_FLAT[$(( _cur_start + _new_pos ))]}
                redraw_menu
                ;;
            LEFT)
                if (( _nav_col > 0 )); then
                    local _target_col=$(( _nav_col - 1 ))
                    local _target_start=${NAV_COL_START[$_target_col]}
                    local _target_size=${NAV_COL_SIZE[$_target_col]}
                    local _cur_sys=${NAV_COL_SYS_SIZE[$_nav_col]}
                    local _target_sys=${NAV_COL_SYS_SIZE[$_target_col]}
                    local _target_pos
                    if (( _nav_pos < _cur_sys )); then
                        _target_pos=$(( _nav_pos < _target_sys ? _nav_pos : _target_sys - 1 ))
                    else
                        local _util_row=$(( _nav_pos - _cur_sys ))
                        local _target_util_size=$(( _target_size - _target_sys ))
                        if (( _target_util_size > 0 )); then
                            _target_pos=$(( _target_sys + (_util_row < _target_util_size ? _util_row : _target_util_size - 1) ))
                        else
                            _target_pos=$(( _target_size - 1 ))
                        fi
                    fi
                    CURSOR=${NAV_FLAT[$(( _target_start + _target_pos ))]}
                fi
                redraw_menu
                ;;
            RIGHT)
                if (( _nav_col < NAV_NUM_COLS - 1 )); then
                    local _target_col=$(( _nav_col + 1 ))
                    local _target_start=${NAV_COL_START[$_target_col]}
                    local _target_size=${NAV_COL_SIZE[$_target_col]}
                    local _cur_sys=${NAV_COL_SYS_SIZE[$_nav_col]}
                    local _target_sys=${NAV_COL_SYS_SIZE[$_target_col]}
                    local _target_pos
                    if (( _nav_pos < _cur_sys )); then
                        _target_pos=$(( _nav_pos < _target_sys ? _nav_pos : _target_sys - 1 ))
                    else
                        local _util_row=$(( _nav_pos - _cur_sys ))
                        local _target_util_size=$(( _target_size - _target_sys ))
                        if (( _target_util_size > 0 )); then
                            _target_pos=$(( _target_sys + (_util_row < _target_util_size ? _util_row : _target_util_size - 1) ))
                        else
                            _target_pos=$(( _target_size - 1 ))
                        fi
                    fi
                    CURSOR=${NAV_FLAT[$(( _target_start + _target_pos ))]}
                fi
                redraw_menu
                ;;
            SPACE)
                # Cycle through states: [ ] → [✓] → [U] (if installed) → [ ]
                if [[ ${UPDATE_SELECTED[$CURSOR]} -eq 1 ]]; then
                    # [U] → [ ]
                    UPDATE_SELECTED[$CURSOR]=0
                    SELECTED[$CURSOR]=0
                elif [[ ${SELECTED[$CURSOR]} -eq 1 ]]; then
                    # [✓] → [U] if installed, otherwise [✓] → [ ]
                    SELECTED[$CURSOR]=0
                    if [[ ${INSTALLED[$CURSOR]} -eq 1 ]]; then
                        UPDATE_SELECTED[$CURSOR]=1
                    fi
                else
                    # [ ] → [✓]
                    SELECTED[$CURSOR]=1
                fi
                redraw_menu
                ;;
            UPDATE)
                # Toggle update mode for installed items only
                if [[ ${INSTALLED[$CURSOR]} -eq 1 ]]; then
                    SELECTED[$CURSOR]=0   # clear install/uninstall selection
                    if [[ ${UPDATE_SELECTED[$CURSOR]} -eq 0 ]]; then
                        UPDATE_SELECTED[$CURSOR]=1
                    else
                        UPDATE_SELECTED[$CURSOR]=0
                    fi
                    redraw_menu
                fi
                ;;
            SELECT_ALL)
                for ((i=0; i<${#UTILITIES[@]}; i++)); do
                    SELECTED[$i]=1
                    UPDATE_SELECTED[$i]=0
                done
                redraw_menu
                ;;
            DESELECT_ALL)
                for ((i=0; i<${#UTILITIES[@]}; i++)); do
                    SELECTED[$i]=0
                    UPDATE_SELECTED[$i]=0
                done
                redraw_menu
                ;;
            ENTER)
                # Continue to installation
                show_cursor
                stty echo
                trap cleanup_on_exit EXIT
                return 0
                ;;
            QUIT)
                show_cursor
                stty echo
                trap cleanup_on_exit EXIT
                echo ""
                echo "${YELLOW}Operation cancelled.${RESET}"
                exit 0
                ;;
        esac
    done
}
