#!/bin/bash

# ============================================================================
# Linux Utilities - Menu Module (Linutil-Style TUI)
# Provides a bordered panel TUI with tabs, search, scrolling, and system info
# ============================================================================

# Enable extended globbing for ANSI-stripping in _visible_len
shopt -s extglob

# ============================================================================
# TERMINAL CONTROL & COLOR DEFINITIONS
# ============================================================================

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
WHITE="${CSI}37m"
BG_BLUE="${CSI}44m"
BG_CYAN="${CSI}46m"
UNDERLINE="${CSI}4m"

# Respect the NO_COLOR standard (https://no-color.org/), non-interactive terminals,
# and the --no-color CLI flag.
if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${NO_COLOR_FLAG:-false}" == "true" ]]; then
    BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN=""
    WHITE="" BG_BLUE="" BG_CYAN="" UNDERLINE=""
fi

# Cursor control
hide_cursor() { printf "${CSI}?25l"; }
show_cursor() { printf "${CSI}?25h"; }

# Escape key for terminal input
ESC=$'\x1b'

# ============================================================================
# BOX-DRAWING CHARACTERS
# ============================================================================

_BD_TL="┌" _BD_TR="┐" _BD_BL="└" _BD_BR="┘"
_BD_H="─"  _BD_V="│"
_BD_TJ="┬" _BD_BJ="┴" _BD_LJ="├" _BD_RJ="┤" _BD_X="┼"

# ============================================================================
# TUI STATE VARIABLES
# ============================================================================

# Focus state: "tabs" or "items"
_FOCUS="items"

# Active tab: 0 = System Tasks, 1 = Utilities
_ACTIVE_TAB=0

# Tab definitions — populated at runtime from CATEGORIES in run_selection_menu
_TAB_NAMES=()

# Per-tab cursor position within the filtered item list
_TAB_CURSOR=()

# Per-tab scroll offset (viewport top)
_TAB_SCROLL=()

# Per-tab active subcategory (empty string = top level, non-empty = inside a subcategory)
_TAB_SUBCAT=()

# Active profile cursor: 0-based index into PROFILES[] array.
# Updated by UP/DOWN while _FOCUS=="profiles"; reset to 0 on menu entry.
_PROFILES_CURSOR=0

# Sentinel value used as the index for the ".." (go-up) entry
_SUBCAT_UP_SENTINEL=-1

# Search state
_SEARCH_ACTIVE=false
_SEARCH_QUERY=""
declare -a _SEARCH_FILTERED=()

# System info cache (populated once by _gather_sysinfo)
_SYSINFO_HOST=""
_SYSINFO_OS=""
_SYSINFO_KERNEL=""
_SYSINFO_CPU=""
_SYSINFO_GPU=""
_SYSINFO_MEM=""
_SYSINFO_DISK=""
_SYSINFO_UPTIME=""
_SYSINFO_OS_AGE=""
_SYSINFO_PACKAGES=""
_SYSINFO_WM=""
_SYSINFO_DE=""

# Layout geometry (recalculated on resize)
_TERM_ROWS=0
_TERM_COLS=0
_LEFT_W=0
_RIGHT_W=0
_MAIN_H=0
_ITEMS_H=0
_DESC_H=0

# Global flag: true while the TUI menu is actively displayed
_MENU_ACTIVE=false

# Flag: set to true by WINCH trap so _calc_layout re-queries the terminal size
_NEEDS_SIZE_REFRESH=true

# Flag: set to true by WINCH trap; main loop performs the actual redraw
_NEEDS_REDRAW=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Return visible length of a string (strip ANSI escape sequences)
# Result stored in _VLEN to avoid subshells in hot path
_VLEN=0
_visible_len() {
    local str="$1"
    # Strip all CSI sequences (ESC [ ... final_byte)
    local stripped="${str//$'\x1b'\[*([0-9;])m/}"
    # Also strip any remaining ESC sequences
    stripped="${stripped//$'\x1b'\[*([0-9;?])[a-zA-Z]/}"
    _VLEN=${#stripped}
}

# Pad or truncate a string to exact visible width
# Usage: _pad_or_truncate "string" width
# Output stored in global _POT_RESULT to avoid subshell
_POT_RESULT=""
_pad_or_truncate() {
    local str="$1"
    local target_w="$2"
    _visible_len "$str"
    local vlen=$_VLEN

    if (( vlen == target_w )); then
        _POT_RESULT="$str"
    elif (( vlen < target_w )); then
        local pad_n=$(( target_w - vlen ))
        local padding=""
        printf -v padding '%*s' "$pad_n" ''
        _POT_RESULT="${str}${padding}"
    else
        # Truncate: walk character by character, tracking visible length
        local result="" vis=0 i=0 len=${#str}
        local in_esc=false
        while (( i < len && vis < target_w )); do
            local ch="${str:$i:1}"
            if [[ "$in_esc" == true ]]; then
                result+="$ch"
                # End of CSI sequence
                [[ "$ch" =~ [a-zA-Z] ]] && in_esc=false
            elif [[ "$ch" == $'\x1b' ]]; then
                result+="$ch"
                in_esc=true
            else
                if (( vis < target_w )); then
                    result+="$ch"
                    (( vis++ ))
                fi
            fi
            (( i++ ))
        done
        # Close any open ANSI with reset
        _POT_RESULT="${result}${RESET}"
    fi
}

# Generate a horizontal line of repeated characters
# Usage: _hline width [char]
_HLINE_RESULT=""
_hline() {
    local w="$1"
    local ch="${2:-$_BD_H}"
    printf -v _HLINE_RESULT '%*s' "$w" ''
    _HLINE_RESULT="${_HLINE_RESULT// /$ch}"
}

# ============================================================================
# CATEGORY FILTER
# ============================================================================

# Parallel arrays describing each entry in the filtered list:
#   _SEARCH_FILTERED    — utility index (only valid when type == "utility")
#   _SEARCH_ITEM_TYPE   — "utility" | "subcat" | "up"
#   _SEARCH_ITEM_LABEL  — display label (subcategory name for "subcat", ".." for "up")
declare -a _SEARCH_ITEM_TYPE=()
declare -a _SEARCH_ITEM_LABEL=()

# Rebuild the filtered item list based on active tab, subcategory, and search query.
# When a search query is active, search ALL categories (flat, no subcategory drilling)
# and auto-switch _ACTIVE_TAB to the category containing the first/best match.
_rebuild_filtered() {
    _SEARCH_FILTERED=()
    _SEARCH_ITEM_TYPE=()
    _SEARCH_ITEM_LABEL=()
    local i total=${#UTILITIES[@]}
    local query_lower="${_SEARCH_QUERY,,}"

    if [[ -n "$_SEARCH_QUERY" ]]; then
        # Search mode: scan every utility regardless of category/subcategory
        for (( i=0; i<total; i++ )); do
            local name="${UTILITIES[$i]}"
            if [[ "${name,,}" == *"$query_lower"* ]]; then
                _SEARCH_FILTERED+=("$i")
                _SEARCH_ITEM_TYPE+=("utility")
                _SEARCH_ITEM_LABEL+=("$name")
            fi
        done

        # Auto-switch active tab to the category of the first match
        if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
            local first_idx=${_SEARCH_FILTERED[0]}
            local first_name="${UTILITIES[$first_idx]}"
            local first_cat=""
            # Check if it's a system task
            local _st
            for _st in "${SYSTEM_TASKS[@]}"; do
                if [[ "$_st" == "$first_name" ]]; then
                    first_cat="System Tasks"
                    break
                fi
            done
            # Otherwise look up UTILITY_CATEGORY
            [[ -z "$first_cat" ]] && first_cat="${UTILITY_CATEGORY[$first_name]:-}"
            # Find the tab index for that category
            local t
            for (( t=0; t<${#_TAB_NAMES[@]}; t++ )); do
                if [[ "${_TAB_NAMES[$t]}" == "$first_cat" ]]; then
                    _ACTIVE_TAB=$t
                    break
                fi
            done
        fi
    else
        # Normal mode: filter by active category and active subcategory
        local category="${_TAB_NAMES[$_ACTIVE_TAB]:-System Tasks}"
        local active_subcat="${_TAB_SUBCAT[$_ACTIVE_TAB]:-}"

        if [[ -n "$active_subcat" ]]; then
            # --- Inside a subcategory: show ".." then items belonging to this subcategory ---
            _SEARCH_FILTERED+=("-1")      # ".." entry uses sentinel index
            _SEARCH_ITEM_TYPE+=("up")
            _SEARCH_ITEM_LABEL+=("..")

            for (( i=0; i<total; i++ )); do
                local name="${UTILITIES[$i]}"
                local item_cat=""
                if [[ "$category" == "System Tasks" ]]; then
                    local _st
                    for _st in "${SYSTEM_TASKS[@]}"; do
                        [[ "$_st" == "$name" ]] && item_cat="System Tasks" && break
                    done
                else
                    item_cat="${UTILITY_CATEGORY[$name]:-}"
                fi
                local item_subcat="${UTILITY_SUBCATEGORY[$name]:-}"
                if [[ "$item_cat" == "$category" && "$item_subcat" == "$active_subcat" ]]; then
                    _SEARCH_FILTERED+=("$i")
                    _SEARCH_ITEM_TYPE+=("utility")
                    _SEARCH_ITEM_LABEL+=("$name")
                fi
            done
        else
            # --- Top level of a category: show items, then subcategory folders (or vice versa) ---

            # Collect distinct subcategory names present in this category
            declare -A _seen_subcats=()
            local -a _ordered_subcats=()
            for (( i=0; i<total; i++ )); do
                local name="${UTILITIES[$i]}"
                local item_cat=""
                if [[ "$category" == "System Tasks" ]]; then
                    local _st
                    for _st in "${SYSTEM_TASKS[@]}"; do
                        [[ "$_st" == "$name" ]] && item_cat="System Tasks" && break
                    done
                else
                    item_cat="${UTILITY_CATEGORY[$name]:-}"
                fi
                if [[ "$item_cat" == "$category" ]]; then
                    local sc="${UTILITY_SUBCATEGORY[$name]:-}"
                    if [[ -n "$sc" && -z "${_seen_subcats[$sc]:-}" ]]; then
                        _seen_subcats["$sc"]=1
                        _ordered_subcats+=("$sc")
                    fi
                fi
            done

            # Apply explicit subcategory ordering if defined for this category
            if [[ -n "${SUBCATEGORY_ORDER[$category]:-}" ]]; then
                IFS='|' read -ra _sc_explicit <<< "${SUBCATEGORY_ORDER[$category]}"
                local -a _reordered_subcats=()
                for _sc_o in "${_sc_explicit[@]}"; do
                    for _sc_e in "${_ordered_subcats[@]}"; do
                        [[ "$_sc_e" == "$_sc_o" ]] && _reordered_subcats+=("$_sc_e") && break
                    done
                done
                # Append any subcategories not listed in the explicit order
                for _sc_e in "${_ordered_subcats[@]}"; do
                    local _sc_found=0
                    for _sc_o in "${_sc_explicit[@]}"; do
                        [[ "$_sc_e" == "$_sc_o" ]] && _sc_found=1 && break
                    done
                    (( _sc_found == 0 )) && _reordered_subcats+=("$_sc_e")
                done
                _ordered_subcats=("${_reordered_subcats[@]}")
            fi

            # Interleaved mode: emit items and subcategory folders in registration order.
            # When the first item of a new subcategory is encountered, emit its folder
            # entry at that position. Items belonging to an already-seen subcategory are
            # skipped at the top level (they appear inside the folder when drilled into).
            # Plain (uncategorised) items are emitted directly as they are encountered.
            if [[ -n "${SUBCATEGORY_INTERLEAVED[$category]:-}" ]]; then
                declare -A _seen_interleaved=()
                for (( i=0; i<total; i++ )); do
                    local name="${UTILITIES[$i]}"
                    local item_cat=""
                    if [[ "$category" == "System Tasks" ]]; then
                        local _st
                        for _st in "${SYSTEM_TASKS[@]}"; do
                            [[ "$_st" == "$name" ]] && item_cat="System Tasks" && break
                        done
                    else
                        item_cat="${UTILITY_CATEGORY[$name]:-}"
                    fi
                    if [[ "$item_cat" == "$category" ]]; then
                        local sc="${UTILITY_SUBCATEGORY[$name]:-}"
                        if [[ -n "$sc" ]]; then
                            if [[ -z "${_seen_interleaved[$sc]:-}" ]]; then
                                _seen_interleaved["$sc"]=1
                                _SEARCH_FILTERED+=("-1")
                                _SEARCH_ITEM_TYPE+=("subcat")
                                _SEARCH_ITEM_LABEL+=("$sc")
                            fi
                        else
                            _SEARCH_FILTERED+=("$i")
                            _SEARCH_ITEM_TYPE+=("utility")
                            _SEARCH_ITEM_LABEL+=("$name")
                        fi
                    fi
                done
            else
                # Default mode: subcategory folders first (respecting SUBCATEGORY_ORDER),
                # then plain (uncategorised) items.
                local sc
                for sc in "${_ordered_subcats[@]}"; do
                    _SEARCH_FILTERED+=("-1")
                    _SEARCH_ITEM_TYPE+=("subcat")
                    _SEARCH_ITEM_LABEL+=("$sc")
                done
                for (( i=0; i<total; i++ )); do
                    local name="${UTILITIES[$i]}"
                    local item_cat=""
                    if [[ "$category" == "System Tasks" ]]; then
                        local _st
                        for _st in "${SYSTEM_TASKS[@]}"; do
                            [[ "$_st" == "$name" ]] && item_cat="System Tasks" && break
                        done
                    else
                        item_cat="${UTILITY_CATEGORY[$name]:-}"
                    fi
                    if [[ "$item_cat" == "$category" && -z "${UTILITY_SUBCATEGORY[$name]:-}" ]]; then
                        _SEARCH_FILTERED+=("$i")
                        _SEARCH_ITEM_TYPE+=("utility")
                        _SEARCH_ITEM_LABEL+=("$name")
                    fi
                done
            fi
        fi
    fi

    # Clamp cursor
    local max=$(( ${#_SEARCH_FILTERED[@]} - 1 ))
    (( max < 0 )) && max=0
    if (( _TAB_CURSOR[_ACTIVE_TAB] > max )); then
        _TAB_CURSOR[$_ACTIVE_TAB]=$max
    fi

    # Sync CURSOR global (only meaningful for utility entries)
    local cur_pos=${_TAB_CURSOR[$_ACTIVE_TAB]}
    if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
        local cur_idx=${_SEARCH_FILTERED[$cur_pos]}
        if [[ "${_SEARCH_ITEM_TYPE[$cur_pos]:-utility}" == "utility" && "$cur_idx" -ge 0 ]]; then
            CURSOR=$cur_idx
        fi
    fi
}

# ============================================================================
# SYSTEM INFO GATHERER
# ============================================================================

# _humanize_duration <seconds>
# Echoes a compact human-readable duration: "Xy Ymo" / "Xmo Yd" / "Xd" / "Xh".
# Calendar units are approximate (year=365d, month=30d) — good enough for an
# "age" readout, not for precise date math.
_humanize_duration() {
    local secs=$(( ${1:-0} ))
    (( secs < 0 )) && secs=0
    local years=$(( secs / 31536000 ))            # 365d
    local months=$(( (secs % 31536000) / 2592000 )) # 30d
    local days=$(( (secs % 2592000) / 86400 ))
    local hours=$(( (secs % 86400) / 3600 ))
    if (( years > 0 )); then
        printf '%dy %dmo' "$years" "$months"
    elif (( months > 0 )); then
        printf '%dmo %dd' "$months" "$days"
    elif (( days > 0 )); then
        printf '%dd' "$days"
    else
        printf '%dh' "$hours"
    fi
}

# _detect_install_epoch
# Echoes a best-effort Unix epoch for when the OS was installed, or nothing if
# undetectable. Heuristic cascade, most install-correlated source first; the
# install date is not canonically recorded on Linux, so this is approximate.
_detect_install_epoch() {
    local epoch=""

    # 1) Debian/Ubuntu installer log directory mtime.
    if [[ -d /var/log/installer ]]; then
        epoch="$(stat -c %Y /var/log/installer 2>/dev/null)"
    fi

    # 2) Filesystem birth time of / (ext4/xfs/btrfs w/ birthtime + new coreutils).
    if [[ -z "$epoch" ]]; then
        local _bw
        _bw="$(stat -c %W / 2>/dev/null)"
        # %W is 0 or '?' when birthtime is unsupported.
        [[ "$_bw" =~ ^[0-9]+$ && "$_bw" -gt 0 ]] && epoch="$_bw"
    fi

    # 3) /lost+found mtime — created by mke2fs at filesystem creation.
    if [[ -z "$epoch" && -d /lost+found ]]; then
        epoch="$(stat -c %Y /lost+found 2>/dev/null)"
    fi

    # 4a) Arch: first timestamp recorded in the pacman log.
    if [[ -z "$epoch" && -f /var/log/pacman.log ]]; then
        local _line
        _line="$(awk 'NF{print; exit}' /var/log/pacman.log 2>/dev/null)"
        # Format: [2023-01-15T10:00:00+0000] ... — extract the bracketed stamp.
        if [[ "$_line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2})[T\ ]([0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            epoch="$(date -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}" +%s 2>/dev/null)"
        fi
    fi

    # 4b) RHEL/Fedora/SUSE: oldest rpm INSTALLTIME (the base system packages).
    if [[ -z "$epoch" ]] && command -v rpm &>/dev/null; then
        epoch="$(rpm -qa --qf '%{INSTALLTIME}\n' 2>/dev/null | sort -n | awk 'NF{print; exit}')"
    fi

    # 5) Last-resort proxy: machine-id mtime (written on first boot/install).
    if [[ -z "$epoch" && -f /etc/machine-id ]]; then
        epoch="$(stat -c %Y /etc/machine-id 2>/dev/null)"
    fi

    # Sanity-check: must be a plausible epoch (after 2000-01-01, not in future).
    if [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch > 946684800 )) && (( epoch <= $(date +%s) )); then
        printf '%s' "$epoch"
    fi
}

_gather_sysinfo() {
    # Hostname
    _SYSINFO_HOST="${HOSTNAME:-$(hostname 2>/dev/null || echo 'unknown')}"

    # OS (from already-detected distro)
    _SYSINFO_OS="${DISTRO_NAME:-Unknown} ${DISTRO_VERSION_ID:-}"

    # Kernel
    _SYSINFO_KERNEL="$(uname -r 2>/dev/null || echo 'unknown')"

    # CPU model (strip trademark noise for readability)
    if [[ -f /proc/cpuinfo ]]; then
        _SYSINFO_CPU="$(awk -F: '/^model name/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo)"
        _SYSINFO_CPU="${_SYSINFO_CPU//(R)/}"
        _SYSINFO_CPU="${_SYSINFO_CPU//(TM)/}"
        _SYSINFO_CPU="${_SYSINFO_CPU// CPU/}"
        _SYSINFO_CPU="${_SYSINFO_CPU//  / }"
        _SYSINFO_CPU="${_SYSINFO_CPU# }"
    fi
    [[ -z "$_SYSINFO_CPU" ]] && _SYSINFO_CPU="unknown"

    # GPU model — three-tier detection (no drivers required for tiers 2 & 3)
    # Tier 1: nvidia-smi (drivers installed, gives clean name)
    if command -v nvidia-smi &>/dev/null; then
        _SYSINFO_GPU="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
    fi
    # Tier 2: lspci (pciutils, reads hardware directly — no drivers needed)
    if [[ -z "$_SYSINFO_GPU" ]] && command -v lspci &>/dev/null; then
        _SYSINFO_GPU="$(lspci 2>/dev/null | grep -i 'vga\|3d controller\|display controller' | head -1 | sed 's/.*: //;s/ (.*//')"
    fi
    # Tier 3: PCI vendor ID via sysfs — works with zero tools installed
    if [[ -z "$_SYSINFO_GPU" ]]; then
        local _pci_dev
        for _pci_dev in /sys/bus/pci/devices/*/class; do
            local _class
            _class="$(cat "$_pci_dev" 2>/dev/null)"
            # 0x0300 = VGA, 0x0302 = 3D controller, 0x0380 = display controller
            if [[ "$_class" == 0x0300* || "$_class" == 0x0302* || "$_class" == 0x0380* ]]; then
                local _vendor
                _vendor="$(cat "${_pci_dev%/class}/vendor" 2>/dev/null)"
                case "$_vendor" in
                    0x10de) _SYSINFO_GPU="NVIDIA (no driver)" ;;
                    0x1002) _SYSINFO_GPU="AMD (no driver)" ;;
                    0x8086) _SYSINFO_GPU="Intel (no driver)" ;;
                    *)      _SYSINFO_GPU="GPU vendor ${_vendor:-unknown}" ;;
                esac
                break
            fi
        done
    fi
    [[ -z "$_SYSINFO_GPU" ]] && _SYSINFO_GPU="unknown"

    # Memory: total and available
    if [[ -f /proc/meminfo ]]; then
        local mem_total_kb mem_avail_kb
        mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
        mem_avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
        if [[ -n "$mem_total_kb" && -n "$mem_avail_kb" ]]; then
            local mem_used_kb=$(( mem_total_kb - mem_avail_kb ))
            # Format as GB with 1 decimal
            local mem_used_g mem_total_g
            mem_used_g=$(awk "BEGIN {printf \"%.1f\", $mem_used_kb/1048576}")
            mem_total_g=$(awk "BEGIN {printf \"%.1f\", $mem_total_kb/1048576}")
            _SYSINFO_MEM="${mem_used_g}G / ${mem_total_g}G"
        fi
    fi
    [[ -z "$_SYSINFO_MEM" ]] && _SYSINFO_MEM="unknown"

    # Disk usage for /
    _SYSINFO_DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    [[ -z "$_SYSINFO_DISK" ]] && _SYSINFO_DISK="unknown"

    # Uptime
    if [[ -f /proc/uptime ]]; then
        local up_secs
        up_secs=$(awk '{printf "%d", $1}' /proc/uptime)
        local days=$(( up_secs / 86400 ))
        local hours=$(( (up_secs % 86400) / 3600 ))
        local mins=$(( (up_secs % 3600) / 60 ))
        if (( days > 0 )); then
            _SYSINFO_UPTIME="${days}d ${hours}h ${mins}m"
        elif (( hours > 0 )); then
            _SYSINFO_UPTIME="${hours}h ${mins}m"
        else
            _SYSINFO_UPTIME="${mins}m"
        fi
    fi
    [[ -z "$_SYSINFO_UPTIME" ]] && _SYSINFO_UPTIME="unknown"

    # OS Age — time since the distro was installed (best-effort; see
    # _detect_install_epoch). Shown as "<age> (<install date>)".
    local _install_epoch
    _install_epoch="$(_detect_install_epoch)"
    if [[ -n "$_install_epoch" ]]; then
        local _now _age_secs _age_human _install_date
        _now="$(date +%s)"
        _age_secs=$(( _now - _install_epoch ))
        _age_human="$(_humanize_duration "$_age_secs")"
        _install_date="$(date -d "@${_install_epoch}" '+%d %b %Y' 2>/dev/null)"
        if [[ -n "$_install_date" ]]; then
            _SYSINFO_OS_AGE="${_age_human} (${_install_date})"
        else
            _SYSINFO_OS_AGE="$_age_human"
        fi
    fi
    [[ -z "$_SYSINFO_OS_AGE" ]] && _SYSINFO_OS_AGE="unknown"

    # Installed package count + manager (uses the already-detected $PKG_MGR).
    # Each branch is guarded by command -v so a missing tool yields "" → unknown.
    local _pkg_count="" _pkg_mgr_label=""
    case "${PKG_MGR:-}" in
        apt)
            if command -v dpkg-query &>/dev/null; then
                _pkg_count="$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l)"
                _pkg_mgr_label="dpkg"
            fi
            ;;
        dnf|yum|zypper)
            if command -v rpm &>/dev/null; then
                _pkg_count="$(rpm -qa 2>/dev/null | wc -l)"
                _pkg_mgr_label="rpm"
            fi
            ;;
        pacman)
            if command -v pacman &>/dev/null; then
                _pkg_count="$(pacman -Qq 2>/dev/null | wc -l)"
                _pkg_mgr_label="pacman"
            fi
            ;;
    esac
    # wc -l emits leading whitespace on some systems; trim it.
    _pkg_count="${_pkg_count//[[:space:]]/}"
    if [[ -n "$_pkg_count" && "$_pkg_count" != 0 ]]; then
        _SYSINFO_PACKAGES="${_pkg_count} (${_pkg_mgr_label})"
    fi
    [[ -z "$_SYSINFO_PACKAGES" ]] && _SYSINFO_PACKAGES="unknown"

    # Desktop Environment — reuse the existing detect_window_button_de() helper
    # (sourced from lib/installers/window_buttons.sh) and map its token to a
    # human-readable name. Fall back to the raw XDG hint when undetected.
    local _de_token=""
    if declare -F detect_window_button_de &>/dev/null; then
        _de_token="$(detect_window_button_de 2>/dev/null)"
    fi
    case "$_de_token" in
        gnome)    _SYSINFO_DE="GNOME" ;;
        kde)      _SYSINFO_DE="KDE Plasma" ;;
        xfce)     _SYSINFO_DE="XFCE" ;;
        cinnamon) _SYSINFO_DE="Cinnamon" ;;
        mate)     _SYSINFO_DE="MATE" ;;
        *)        _SYSINFO_DE="${XDG_CURRENT_DESKTOP:-}" ;;
    esac
    # Strip the common "ubuntu:" / "X-" session prefixes from raw XDG hints.
    _SYSINFO_DE="${_SYSINFO_DE##*:}"
    [[ -z "$_SYSINFO_DE" ]] && _SYSINFO_DE="unknown"

    # Window Manager — best-effort, inherently unreliable without a display.
    # Order: WSLg special-case → wmctrl (_NET_WM_NAME) → env hints → unknown.
    _SYSINFO_WM=""
    if is_wsl && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        _SYSINFO_WM="WSLg"
    elif command -v wmctrl &>/dev/null; then
        _SYSINFO_WM="$(wmctrl -m 2>/dev/null | awk -F': ' '/^Name:/ {print $2; exit}')"
    fi
    if [[ -z "$_SYSINFO_WM" ]]; then
        # Fall back to environment hints when no probe tool is available.
        if [[ -n "${XDG_SESSION_TYPE:-}" && "${XDG_SESSION_TYPE}" == "wayland" ]]; then
            _SYSINFO_WM="${XDG_CURRENT_DESKTOP:+${XDG_CURRENT_DESKTOP##*:} (Wayland)}"
        fi
    fi
    [[ -z "$_SYSINFO_WM" ]] && _SYSINFO_WM="unknown"
}

# ============================================================================
# LAYOUT CALCULATOR
# ============================================================================

_calc_layout() {
    # On first call and after every WINCH signal, re-query the actual terminal
    # size directly from the kernel (TIOCGWINSZ via stty) rather than trusting
    # the LINES/COLUMNS env vars, which can be stale during and after resize.
    if [[ "$_NEEDS_SIZE_REFRESH" == "true" ]]; then
        local _stty
        _stty=$(stty size 2>/dev/null)
        if [[ "$_stty" =~ ^([0-9]+)[[:space:]]([0-9]+)$ ]]; then
            _TERM_ROWS="${BASH_REMATCH[1]}"
            _TERM_COLS="${BASH_REMATCH[2]}"
        else
            # Non-tty fallback (pipes, test harness, CI)
            _TERM_ROWS=${LINES:-24}
            _TERM_COLS=${COLUMNS:-80}
        fi
        _NEEDS_SIZE_REFRESH=false
    fi

    # Left panel width: content-aware, percentage-capped.
    #
    # Each sysinfo row occupies: 2 border chars + 8 label chars (right-aligned)
    # + 2 for ": " + value = value_len + 12.  We find the longest actual value
    # on this machine so the panel is never wider than necessary, but always
    # wide enough to avoid truncating sysinfo on any hardware.
    #
    # The result is:  max(min_w, content_needed)
    #                 capped at: min(max_w, floor(_TERM_COLS * 30 / 100))
    local _overhead=14          # 2 borders + 8 label + 2 ": " + 2 right-margin padding
    local _min_w=28             # never narrower than this
    local _max_w=50             # never wider than this
    local _content_w=_min_w
    local _v
    for _v in "$_SYSINFO_HOST" "$_SYSINFO_OS" "$_SYSINFO_KERNEL" \
              "$_SYSINFO_CPU" "$_SYSINFO_GPU" "$_SYSINFO_MEM" "$_SYSINFO_DISK" \
              "$_SYSINFO_UPTIME" "$_SYSINFO_OS_AGE" "$_SYSINFO_PACKAGES" \
              "$_SYSINFO_WM" "$_SYSINFO_DE"; do
        local _needed=$(( ${#_v} + _overhead ))
        (( _needed > _content_w )) && _content_w=$_needed
    done
    # Also account for tab label lines: "   TabName" needs 3-char prefix + name + 2 borders
    local _tn
    for _tn in "${_TAB_NAMES[@]}"; do
        local _needed=$(( ${#_tn} + 5 ))   # "> " + " " indent + 2 borders
        (( _needed > _content_w )) && _content_w=$_needed
    done
    local _pct_max=$(( _TERM_COLS * 35 / 100 ))
    (( _pct_max < _min_w )) && _pct_max=$_min_w
    (( _pct_max > _max_w )) && _pct_max=$_max_w
    _LEFT_W=$(( _content_w < _pct_max ? _content_w : _pct_max ))
    (( _LEFT_W < _min_w )) && _LEFT_W=$_min_w

    _RIGHT_W=$(( _TERM_COLS - _LEFT_W ))

    # Vertical: title(4) + main + status(4)
    _MAIN_H=$(( _TERM_ROWS - 4 - 4 ))
    (( _MAIN_H < 5 )) && _MAIN_H=5

    # Description panel height: ~30% of main area, clamped to [4, 10]
    _DESC_H=$(( _MAIN_H * 30 / 100 ))
    (( _DESC_H < 4 )) && _DESC_H=4
    (( _DESC_H > 10 )) && _DESC_H=10

    # Items viewport height = main height - header(1) - description area
    _ITEMS_H=$(( _MAIN_H - 1 - _DESC_H ))
    (( _ITEMS_H < 3 )) && _ITEMS_H=3
}

# ============================================================================
# SCROLLING
# ============================================================================

_update_scroll() {
    local tab=$_ACTIVE_TAB
    local cursor_pos=${_TAB_CURSOR[$tab]}
    local scroll=${_TAB_SCROLL[$tab]}
    local visible=$_ITEMS_H
    local total=${#_SEARCH_FILTERED[@]}
    local margin=2

    # Keep cursor within viewport with margin
    if (( cursor_pos < scroll + margin )); then
        scroll=$(( cursor_pos - margin ))
    elif (( cursor_pos >= scroll + visible - margin )); then
        scroll=$(( cursor_pos - visible + margin + 1 ))
    fi

    # Clamp
    (( scroll < 0 )) && scroll=0
    local max_scroll=$(( total - visible ))
    (( max_scroll < 0 )) && max_scroll=0
    (( scroll > max_scroll )) && scroll=$max_scroll

    _TAB_SCROLL[$tab]=$scroll
}

# ============================================================================
# PANEL RENDERERS
# ============================================================================

# --- Title Bar (3 lines) ---
declare -a _TITLE_LINES=()
_render_title() {
    _TITLE_LINES=()
    local eol=$'\033[K'

    # Left cell inner width (between left border │ and divider │)
    local left_inner=$(( _LEFT_W - 2 ))
    # Right cell inner width (between divider │ and right border │)
    # Must be _RIGHT_W - 1 so the title bar is _TERM_COLS wide, matching main panel rows.
    local right_inner=$(( _RIGHT_W - 1 ))

    # --- Line 1: top border ---
    _hline "$left_inner"
    local left_top="$_HLINE_RESULT"
    _hline "$right_inner"
    local right_top="$_HLINE_RESULT"
    _TITLE_LINES+=("${CYAN}${_BD_TL}${left_top}${_BD_TJ}${right_top}${_BD_TR}${RESET}${eol}")

    # --- Line 2: title (left) | search (right) ---
    # Left: app title
    local title_text=" linux_util (${CACHED_LOCAL_BRANCH}: ${CACHED_LOCAL_COMMIT})"
    [[ "$DRY_RUN" == "true" ]] && title_text+=" ${BOLD}${YELLOW}[DRY RUN]${RESET}"
    if [[ "$CACHED_LOCAL_COMMIT" != "unknown" && "$CACHED_REMOTE_COMMIT" != "unknown" && \
          "$CACHED_LOCAL_COMMIT" != "$CACHED_REMOTE_COMMIT" ]]; then
        title_text+=" ${YELLOW}(out of date)${RESET}"
    fi
    _pad_or_truncate "$title_text" "$left_inner"
    local left_cell="${RESET}${BOLD}${_POT_RESULT}${RESET}"

    # Right: search input
    local search_text=""
    if [[ "$_SEARCH_ACTIVE" == true ]]; then
        search_text="${_SEARCH_QUERY}_"
        local max_sw=$(( right_inner - 3 ))
        (( ${#search_text} > max_sw )) && search_text="${search_text: -$max_sw}"
        search_text=" ${BOLD}${WHITE}${search_text}${RESET}"
    elif [[ -n "$_SEARCH_QUERY" ]]; then
        search_text=" ${WHITE}${_SEARCH_QUERY}${RESET}"
    else
        search_text=" ${DIM}Type to search (/)${RESET}"
    fi
    # Search label + input on right side
    local search_label=" ${BOLD}${CYAN}SEARCH${RESET} "
    local search_content="${search_label}${search_text}"
    _pad_or_truncate "$search_content" "$right_inner"
    local right_cell="${_POT_RESULT}"

    # Search border color: bright when active, dimmed otherwise
    local sbc="${CYAN}"
    [[ "$_SEARCH_ACTIVE" == true ]] && sbc="${BOLD}${CYAN}"

    _TITLE_LINES+=("${CYAN}${_BD_V}${left_cell}${sbc}${_BD_V}${RESET}${right_cell}${CYAN}${_BD_V}${RESET}${eol}")

    # --- Line 3: By: PozzaTech (left) | empty (right) ---
    local by_text=" ${DIM}By: ${RESET}${BOLD}${BLUE}PozzaTech${RESET}"
    _pad_or_truncate "$by_text" "$left_inner"
    local by_cell="${_POT_RESULT}"
    _pad_or_truncate "" "$right_inner"
    _TITLE_LINES+=("${CYAN}${_BD_V}${RESET}${by_cell}${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}${eol}")

    # --- Line 4: separator row connecting title to panels ---
    _hline "$left_inner"
    local left_sep="$_HLINE_RESULT"
    _hline "$right_inner"
    local right_sep="$_HLINE_RESULT"
    _TITLE_LINES+=("${CYAN}${_BD_LJ}${left_sep}${_BD_X}${right_sep}${_BD_RJ}${RESET}${eol}")
}

# --- Left Panel (main_height lines) ---
declare -a _LEFT_LINES=()
_render_left() {
    _LEFT_LINES=()
    local inner_w=$(( _LEFT_W - 2 ))  # minus left border + right divider
    local eol=$'\033[K'
    local row=0

    # --- Categories Section ---
    # Category header
    local header=" CATEGORIES"
    _pad_or_truncate "$header" "$inner_w"
    _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${BOLD}${CYAN}${_POT_RESULT}${RESET}${CYAN}${_BD_V}${RESET}")
    (( row++ ))

    # Separator under header
    _hline "$inner_w"
    _LEFT_LINES+=("${CYAN}${_BD_LJ}${_HLINE_RESULT}${_BD_RJ}${RESET}")
    (( row++ ))

    # Tab entries
    local num_tabs=${#_TAB_NAMES[@]}
    for (( t=0; t<num_tabs; t++ )); do
        local tab_text=""
        if (( t == _ACTIVE_TAB )); then
            if [[ "$_FOCUS" == "tabs" ]]; then
                tab_text=" ${BOLD}${YELLOW}> ${_TAB_NAMES[$t]}${RESET}"
            else
                tab_text=" ${YELLOW}> ${_TAB_NAMES[$t]}${RESET}"
            fi
        else
            tab_text="   ${DIM}${_TAB_NAMES[$t]}${RESET}"
        fi
        _pad_or_truncate "$tab_text" "$inner_w"
        _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}")
        (( row++ ))
    done

    # Separator between categories and profiles
    _hline "$inner_w"
    _LEFT_LINES+=("${CYAN}${_BD_LJ}${_HLINE_RESULT}${_BD_RJ}${RESET}")
    (( row++ ))

    # --- Profiles Section ---
    # Rendered only when at least one profile is registered (lib/profiles.sh).
    # Shows a navigable list of curated presets that pre-populate the install
    # queue when activated. Utilities not registered on the current distro
    # are silently skipped by apply_profile() at runtime.
    if (( ${#PROFILES[@]} > 0 )) && (( row < _MAIN_H )); then
        local _phdr=" PROFILES"
        _pad_or_truncate "$_phdr" "$inner_w"
        _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${BOLD}${CYAN}${_POT_RESULT}${RESET}${CYAN}${_BD_V}${RESET}")
        (( row++ ))

        if (( row < _MAIN_H )); then
            _hline "$inner_w"
            _LEFT_LINES+=("${CYAN}${_BD_LJ}${_HLINE_RESULT}${_BD_RJ}${RESET}")
            (( row++ ))
        fi

        local _num_profiles=${#PROFILES[@]}
        for (( p=0; p<_num_profiles; p++ )); do
            (( row >= _MAIN_H )) && break
            local _pname="${PROFILES[$p]}"
            local _ptext=""
            if (( p == _PROFILES_CURSOR )) && [[ "$_FOCUS" == "profiles" ]]; then
                _ptext=" ${BOLD}${YELLOW}> ${_pname}${RESET}"
            elif (( p == _PROFILES_CURSOR )); then
                _ptext=" ${YELLOW}> ${_pname}${RESET}"
            else
                _ptext="   ${DIM}${_pname}${RESET}"
            fi
            _pad_or_truncate "$_ptext" "$inner_w"
            _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}")
            (( row++ ))
        done

        # Separator between profiles and sysinfo
        if (( row < _MAIN_H )); then
            _hline "$inner_w"
            _LEFT_LINES+=("${CYAN}${_BD_LJ}${_HLINE_RESULT}${_BD_RJ}${RESET}")
            (( row++ ))
        fi
    fi

    # --- System Info Section ---
    local sysinfo_header=" SYSTEM DETAILS"
    _pad_or_truncate "$sysinfo_header" "$inner_w"
    _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${BOLD}${CYAN}${_POT_RESULT}${RESET}${CYAN}${_BD_V}${RESET}")
    (( row++ ))

    _hline "$inner_w"
    _LEFT_LINES+=("${CYAN}${_BD_LJ}${_HLINE_RESULT}${_BD_RJ}${RESET}")
    (( row++ ))

    # Sysinfo entries: label + value
    local -a _si_labels=("Host" "OS" "Kernel" "CPU" "GPU" "Mem" "Disk" "Uptime" "OS Age" "Packages" "WM" "DE")
    local -a _si_values=("$_SYSINFO_HOST" "$_SYSINFO_OS" "$_SYSINFO_KERNEL" "$_SYSINFO_CPU" "$_SYSINFO_GPU" "$_SYSINFO_MEM" "$_SYSINFO_DISK" "$_SYSINFO_UPTIME" "$_SYSINFO_OS_AGE" "$_SYSINFO_PACKAGES" "$_SYSINFO_WM" "$_SYSINFO_DE")

    # Surface a WSL indicator when running under Windows Subsystem for Linux.
    if is_wsl; then
        _si_labels+=("Env")
        _si_values+=("WSL${WSL_DISTRO_NAME:+ (${WSL_DISTRO_NAME})}")
    fi

    local label_w=8  # fixed label column width (includes leading space)
    local val_w=$(( inner_w - label_w - 2 ))  # -2 for ": " separator

    for (( s=0; s<${#_si_labels[@]}; s++ )); do
        if (( row >= _MAIN_H )); then
            break
        fi
        local lbl="${_si_labels[$s]}"
        local val="${_si_values[$s]}"

        # Right-align label, truncate value
        printf -v lbl ' %7s' "$lbl"
        local line_text="${BOLD}${CYAN}${lbl}${RESET}${DIM}:${RESET} "
        # Truncate value to fit
        if (( ${#val} > val_w )); then
            val="${val:0:$((val_w - 3))}..."
        fi
        line_text+="${val}"

        _pad_or_truncate "$line_text" "$inner_w"
        _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}")
        (( row++ ))
    done

    # --- Snapshot section (multi-line, word-wrapped) ---
    # Rendered separately so it can span multiple rows rather than truncating.
    if [[ "${TIMESHIFT_AVAILABLE:-false}" == "true" ]] && (( row < _MAIN_H )); then
        local _snap_full="${TIMESHIFT_LAST_SNAPSHOT:-No snapshots found}"

        # Reformat timestamp "YYYY-MM-DD_HH-MM-SS" → "DD Mon YYYY HH:MM AM/PM"
        local _snap_display
        if [[ "$_snap_full" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})(.*) ]]; then
            local _yr="${BASH_REMATCH[1]}" _mo="${BASH_REMATCH[2]}" _dy="${BASH_REMATCH[3]}"
            local _hr="${BASH_REMATCH[4]}" _mi="${BASH_REMATCH[5]}" _rest="${BASH_REMATCH[7]}"
            local -a _mn=(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
            local _ampm="AM" _h12=$(( 10#$_hr ))
            (( _h12 >= 12 )) && _ampm="PM"
            (( _h12 > 12 ))  && _h12=$(( _h12 - 12 ))
            (( _h12 == 0 ))  && _h12=12
            printf -v _h12 '%02d' "$_h12"
            _snap_display="${_dy} ${_mn[$(( 10#$_mo - 1 ))]} ${_yr} ${_h12}:${_mi} ${_ampm}${_rest}"
        else
            _snap_display="$_snap_full"
        fi

        # Label is " Snapshot" (9 chars); prefix with ": " = 11 chars before value.
        local _snap_lbl=" Snapshot"
        local _snap_val_w=$(( inner_w - ${#_snap_lbl} - 2 ))
        local _snap_indent
        printf -v _snap_indent '%*s' "$(( ${#_snap_lbl} + 2 ))" ''

        # Word-wrap _snap_display into _snap_val_w-wide chunks
        local -a _snap_words
        read -ra _snap_words <<< "$_snap_display"
        local _snap_cur="" _snap_first=true
        for _snapw in "${_snap_words[@]}"; do
            local _snap_test
            if [[ -z "$_snap_cur" ]]; then
                _snap_test="$_snapw"
            else
                _snap_test="${_snap_cur} ${_snapw}"
            fi
            if (( ${#_snap_test} <= _snap_val_w )); then
                _snap_cur="$_snap_test"
            else
                # Emit accumulated line
                if (( row < _MAIN_H )); then
                    local _snap_lt
                    if [[ "$_snap_first" == true ]]; then
                        _snap_lt="${BOLD}${CYAN}${_snap_lbl}${RESET}${DIM}:${RESET} ${_snap_cur}"
                        _snap_first=false
                    else
                        _snap_lt="${_snap_indent}${_snap_cur}"
                    fi
                    _pad_or_truncate "$_snap_lt" "$inner_w"
                    _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}")
                    (( row++ ))
                fi
                _snap_cur="$_snapw"
            fi
        done
        # Emit the final accumulated line
        if [[ -n "$_snap_cur" ]] && (( row < _MAIN_H )); then
            local _snap_lt
            if [[ "$_snap_first" == true ]]; then
                _snap_lt="${BOLD}${CYAN}${_snap_lbl}${RESET}${DIM}:${RESET} ${_snap_cur}"
            else
                _snap_lt="${_snap_indent}${_snap_cur}"
            fi
            _pad_or_truncate "$_snap_lt" "$inner_w"
            _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}")
            (( row++ ))
        fi
    fi

    # Fill any remaining rows with empty lines
    while (( row < _MAIN_H )); do
        _pad_or_truncate "" "$inner_w"
        _LEFT_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}")
        (( row++ ))
    done
}

# --- Right Panel (main_height lines) ---
# Content is padded to fill inner_w (= _RIGHT_W - 1), then the outer │ is appended.
# The left divider │ is provided by the left panel's trailing character.
declare -a _RIGHT_LINES=()
_render_right() {
    _RIGHT_LINES=()
    local inner_w=$(( _RIGHT_W - 1 ))  # content width; outer │ appended separately
    local eol=$'\033[K'
    local row=0

    local outer_bc="${CYAN}"  # outer frame always full color

    # --- Category label header (1 line) ---
    # Show "Category > Subcategory" breadcrumb when inside a subcategory.
    local active_subcat="${_TAB_SUBCAT[$_ACTIVE_TAB]:-}"
    local header_label
    if [[ -n "$active_subcat" ]]; then
        header_label=" ${_TAB_NAMES[$_ACTIVE_TAB]} > ${active_subcat} "
    else
        header_label=" ${_TAB_NAMES[$_ACTIVE_TAB]} "
    fi
    _hline $(( inner_w - ${#header_label} - 1 ))
    local items_hdr=" ${BOLD}${CYAN}${header_label}${RESET}${CYAN}${_HLINE_RESULT}${RESET}"
    _pad_or_truncate "$items_hdr" "$inner_w"
    _RIGHT_LINES+=("${_POT_RESULT}${outer_bc}${_BD_RJ}${RESET}")
    (( row++ ))

    # --- Items List ---
    local total_items=${#_SEARCH_FILTERED[@]}
    local scroll=${_TAB_SCROLL[$_ACTIVE_TAB]}
    # Available width for item content (2 spaces left padding)
    local item_w=$(( inner_w - 2 ))

    # Scroll indicators
    local show_up_arrow=false
    local show_down_arrow=false
    (( scroll > 0 )) && show_up_arrow=true
    (( scroll + _ITEMS_H < total_items )) && show_down_arrow=true

    for (( v=0; v<_ITEMS_H; v++ )); do
        local item_idx=$(( scroll + v ))
        local line_content=""
        local scroll_indicator=""

        # Scroll indicators on rightmost position
        if (( v == 0 )) && [[ "$show_up_arrow" == true ]]; then
            scroll_indicator="${DIM}▲${RESET}"
        elif (( v == _ITEMS_H - 1 )) && [[ "$show_down_arrow" == true ]]; then
            scroll_indicator="${DIM}▼${RESET}"
        fi

        if (( item_idx < total_items )); then
            local real_idx=${_SEARCH_FILTERED[$item_idx]}
            local entry_type="${_SEARCH_ITEM_TYPE[$item_idx]:-utility}"
            local is_cursor=false
            (( item_idx == _TAB_CURSOR[_ACTIVE_TAB] )) && is_cursor=true

            # Build prefix (2 chars visible)
            local prefix="  "
            if [[ "$is_cursor" == true && "$_FOCUS" == "items" ]]; then
                prefix="${BOLD}${CYAN}> ${RESET}"
            elif [[ "$is_cursor" == true ]]; then
                prefix="${DIM}> ${RESET}"
            fi

            if [[ "$entry_type" == "subcat" ]]; then
                # Subcategory folder entry: [D]  Name
                local sc_name="${_SEARCH_ITEM_LABEL[$item_idx]}"
                local dir_tag="${CYAN}[D]${RESET}"
                local name_avail=$(( item_w - 2 - 3 - 2 ))  # prefix(2) + "[D]"(3) + "  "(2)
                local display_sc="$sc_name"
                if (( ${#sc_name} > name_avail && name_avail > 3 )); then
                    display_sc="${sc_name:0:$((name_avail - 3))}..."
                fi
                line_content="${prefix}${dir_tag}  ${display_sc}"

            elif [[ "$entry_type" == "up" ]]; then
                # Go-up ".." entry
                local dir_tag="${CYAN}[D]${RESET}"
                line_content="${prefix}${dir_tag}  ${DIM}..${RESET}"

            else
                # Regular utility entry
                local name="${UTILITIES[$real_idx]}"

                # Build checkbox (3 chars visible)
                local checkbox="[ ]"
                if [[ ${UPDATE_SELECTED[$real_idx]} -eq 1 ]]; then
                    checkbox="${YELLOW}[U]${RESET}"
                elif [[ ${SELECTED[$real_idx]} -eq 1 ]]; then
                    checkbox="${GREEN}[✓]${RESET}"
                fi

                # Build status tag
                local status_tag=""
                local status_plain=""
                if [[ ${INSTALLED[$real_idx]} -eq 1 ]]; then
                    local ver="${INSTALLED_VERSIONS[$real_idx]:-}"
                    if [[ -n "$ver" ]]; then
                        if [[ "$ver" =~ ^[0-9] && ! "$ver" =~ \  ]]; then
                            status_tag="${MAGENTA}(v${ver})${RESET}"
                            status_plain="(v${ver})"
                        else
                            status_tag="${MAGENTA}(${ver})${RESET}"
                            status_plain="(${ver})"
                        fi
                    else
                        status_tag="${MAGENTA}(installed)${RESET}"
                        status_plain="(installed)"
                    fi
                else
                    # Show status info for non-installed items (e.g., pending update count)
                    local ver="${INSTALLED_VERSIONS[$real_idx]:-}"
                    if [[ -n "$ver" ]]; then
                        status_tag="${MAGENTA}(${ver})${RESET}"
                        status_plain="(${ver})"
                    fi
                fi

                # Calculate available width for name
                # Layout: prefix(2) + checkbox(3) + space(1) + name + gap + status
                local name_avail=$(( item_w - 2 - 3 - 1 - ${#status_plain} ))
                (( ${#status_plain} > 0 )) && name_avail=$(( name_avail - 1 ))  # space before status

                local display_name="${UTILITY_DISPLAY_NAME[$name]:-$name}"
                if (( ${#display_name} > name_avail && name_avail > 3 )); then
                    display_name="${name:0:$((name_avail - 3))}..."
                fi

                # Build the item line: prefix + checkbox are never underlined;
                # name + gap + status get the underline on the cursor row.
                local _ul=""
                if [[ "${is_cursor:-false}" == true && "$_FOCUS" == "items" ]]; then
                    _ul="${MAGENTA}${UNDERLINE}"
                fi

                if [[ -n "$status_plain" ]]; then
                    local name_pad=$(( name_avail - ${#display_name} ))
                    (( name_pad < 1 )) && name_pad=1
                    local gap=""
                    printf -v gap '%*s' "$name_pad" ''
                    # Re-apply underline after status_tag's embedded RESET
                    local _ul_status="${status_tag}"
                    [[ -n "$_ul" ]] && _ul_status="${status_tag//${RESET}/${RESET}${MAGENTA}${UNDERLINE}}"
                    line_content="${prefix}${checkbox} ${_ul}${display_name}${gap} ${_ul_status}${RESET}"
                else
                    # Pad name to fill available width so the underline extends fully
                    local name_pad=$(( item_w - 2 - 3 - 1 - ${#display_name} ))
                    (( name_pad < 0 )) && name_pad=0
                    local gap=""
                    printf -v gap '%*s' "$name_pad" ''
                    line_content="${prefix}${checkbox} ${_ul}${display_name}${gap}${RESET}"
                fi
            fi
        fi

        # Build full line: content padded to inner_w + outer border
        if [[ -n "$scroll_indicator" ]]; then
            _pad_or_truncate " ${line_content}" "$(( inner_w - 1 ))"
            _RIGHT_LINES+=("${_POT_RESULT}${scroll_indicator}${outer_bc}${_BD_V}${RESET}")
        else
            _pad_or_truncate " ${line_content}" "$inner_w"
            _RIGHT_LINES+=("${_POT_RESULT}${outer_bc}${_BD_V}${RESET}")
        fi
        (( row++ ))
    done

    # Fill empty rows between items and description separator
    local items_end=$(( 1 + _ITEMS_H ))  # header(1) + items
    while (( row < items_end )); do
        _pad_or_truncate "" "$inner_w"
        _RIGHT_LINES+=("${_POT_RESULT}${outer_bc}${_BD_V}${RESET}")
        (( row++ ))
    done

    # --- Description panel separator ---
    _hline "$inner_w"
    _RIGHT_LINES+=("${CYAN}${_HLINE_RESULT}${_BD_RJ}${RESET}")
    (( row++ ))

    # --- Description content ---
    local desc_content_h=$(( _DESC_H - 1 ))  # minus separator line
    local desc_text=""

    # When the profiles section is focused, show the selected profile's
    # description instead of the highlighted right-panel item description.
    if [[ "$_FOCUS" == "profiles" ]] && (( ${#PROFILES[@]} > 0 )); then
        desc_text="${PROFILE_DESC[$_PROFILES_CURSOR]:-}"
    fi

    # Determine what is currently highlighted
    local _cur_pos=${_TAB_CURSOR[$_ACTIVE_TAB]}
    if (( ${#_SEARCH_FILTERED[@]} > 0 && _cur_pos < ${#_SEARCH_FILTERED[@]} )); then
        local _cur_type="${_SEARCH_ITEM_TYPE[$_cur_pos]:-utility}"
        if [[ "$_cur_type" == "utility" ]]; then
            local _cur_idx=${_SEARCH_FILTERED[$_cur_pos]}
            local _cur_name="${UTILITIES[$_cur_idx]}"
            desc_text="${UTILITY_DESCRIPTION[$_cur_name]:-}"
        elif [[ "$_cur_type" == "subcat" ]]; then
            local _sc_name="${_SEARCH_ITEM_LABEL[$_cur_pos]}"
            # Count items in this subcategory
            local _sc_count=0 _sc_i _sc_total=${#UTILITIES[@]}
            local _sc_cat="${_TAB_NAMES[$_ACTIVE_TAB]:-}"
            for (( _sc_i=0; _sc_i<_sc_total; _sc_i++ )); do
                local _sc_uname="${UTILITIES[$_sc_i]}"
                local _sc_ucat=""
                if [[ "$_sc_cat" == "System Tasks" ]]; then
                    local _sc_st
                    for _sc_st in "${SYSTEM_TASKS[@]}"; do
                        [[ "$_sc_st" == "$_sc_uname" ]] && _sc_ucat="System Tasks" && break
                    done
                else
                    _sc_ucat="${UTILITY_CATEGORY[$_sc_uname]:-}"
                fi
                if [[ "$_sc_ucat" == "$_sc_cat" && "${UTILITY_SUBCATEGORY[$_sc_uname]:-}" == "$_sc_name" ]]; then
                    (( _sc_count++ ))
                fi
            done
            desc_text="Browse ${_sc_count} item(s) in the ${_sc_name} subcategory."
        elif [[ "$_cur_type" == "up" ]]; then
            desc_text="Return to the parent category."
        fi
    fi

    # Word-wrap description text into desc_content_h lines
    local desc_w=$(( inner_w - 3 ))  # 2 left padding + 1 right margin
    local -a _desc_lines=()
    if [[ -n "$desc_text" ]]; then
        local -a _dwords
        read -ra _dwords <<< "$desc_text"
        local _dcur=""
        for _dw in "${_dwords[@]}"; do
            local _dtest
            if [[ -z "$_dcur" ]]; then
                _dtest="$_dw"
            else
                _dtest="${_dcur} ${_dw}"
            fi
            if (( ${#_dtest} <= desc_w )); then
                _dcur="$_dtest"
            else
                _desc_lines+=("$_dcur")
                _dcur="$_dw"
            fi
        done
        [[ -n "$_dcur" ]] && _desc_lines+=("$_dcur")
    fi

    # Render description lines
    local _dl=0
    for (( _dl=0; _dl<desc_content_h; _dl++ )); do
        local _dline=""
        if (( _dl < ${#_desc_lines[@]} )); then
            _dline="  ${_desc_lines[$_dl]}"
        fi
        _pad_or_truncate "$_dline" "$inner_w"
        _RIGHT_LINES+=("${_POT_RESULT}${outer_bc}${_BD_V}${RESET}")
        (( row++ ))
    done

    # Fill any remaining rows (safety)
    while (( row < _MAIN_H )); do
        _pad_or_truncate "" "$inner_w"
        _RIGHT_LINES+=("${_POT_RESULT}${outer_bc}${_BD_V}${RESET}")
        (( row++ ))
    done
}

# --- Status Bar (4 lines) ---
declare -a _STATUS_LINES=()
_render_status() {
    _STATUS_LINES=()
    local w=$(( _TERM_COLS - 2 ))
    local eol=$'\033[K'

    # Count actions
    local install_count=0 uninstall_count=0 update_count=0
    local total=${#UTILITIES[@]}
    for ((i=0; i<total; i++)); do
        if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
            (( update_count++ ))
        elif [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                (( uninstall_count++ ))
            else
                (( install_count++ ))
            fi
        fi
    done

    # Line 1: separator with B-junction
    _hline $(( _LEFT_W - 2 ))
    local left_sep="$_HLINE_RESULT"
    _hline $(( _RIGHT_W - 1 ))
    local right_sep="$_HLINE_RESULT"
    _STATUS_LINES+=("${CYAN}${_BD_LJ}${left_sep}${_BD_BJ}${right_sep}${_BD_RJ}${RESET}${eol}")

    # Line 2: action counts
    local actions=" ${CYAN}Actions:${RESET} ${GREEN}Install: ${install_count}${RESET} ${DIM}|${RESET} ${RED}Uninstall: ${uninstall_count}${RESET} ${DIM}|${RESET} ${YELLOW}Update: ${update_count}${RESET}"
    _pad_or_truncate "$actions" "$w"
    _STATUS_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}${eol}")

    # Line 3: keybindings
    local keys=""
    if [[ "$_SEARCH_ACTIVE" == true ]]; then
        keys=" ${BOLD}[Esc]${RESET} Clear  ${BOLD}[↑↓]${RESET} Navigate  ${BOLD}[Enter]${RESET} Accept  ${BOLD}[BS]${RESET} Delete"
    elif [[ "$_FOCUS" == "profiles" ]]; then
        keys=" ${BOLD}[↑↓]${RESET} Select Profile  ${BOLD}[Enter/Space]${RESET} Apply Profile  ${BOLD}[Tab]${RESET} Switch Focus  ${BOLD}[Q]${RESET} Quit"
    else
        keys=" ${BOLD}[↑↓]${RESET} Navigate  ${BOLD}[Space]${RESET} Select  ${BOLD}[U]${RESET} Update  ${BOLD}[/]${RESET} Search  ${BOLD}[Enter]${RESET} Confirm  ${BOLD}[Tab]${RESET} Focus  ${BOLD}[Q]${RESET} Quit"
    fi
    _pad_or_truncate "$keys" "$w"
    _STATUS_LINES+=("${CYAN}${_BD_V}${RESET}${_POT_RESULT}${CYAN}${_BD_V}${RESET}${eol}")

    # Line 4: bottom border
    _hline "$w"
    _STATUS_LINES+=("${CYAN}${_BD_BL}${_HLINE_RESULT}${_BD_BR}${RESET}${eol}")
}

# ============================================================================
# FRAME COMPOSITOR
# ============================================================================

_compose_frame() {
    _calc_layout

    # Check minimum terminal size
    if (( _TERM_COLS < 60 || _TERM_ROWS < 20 )); then
        printf '\033[H\033[J'
        printf '%s\n' "${RED}Terminal too small (${_TERM_COLS}x${_TERM_ROWS}). Minimum: 60x20.${RESET}"
        printf '%s\n' "Please resize your terminal."
        return
    fi

    # Render all panels
    _render_title
    _render_left
    _render_right
    _render_status

    # Build final buffer
    local _buf=""
    local eol=$'\033[K'

    # Cursor home (overwrite in place for flicker-free rendering)
    _buf+=$'\033[H'

    # Title lines
    for line in "${_TITLE_LINES[@]}"; do
        _buf+="${line}"$'\n'
    done

    # Main area: merge left + right
    # \033[K (erase to end of line) after each row clears stale characters
    # that remain when the terminal is resized narrower.
    for (( r=0; r<_MAIN_H; r++ )); do
        _buf+="${_LEFT_LINES[$r]}${_RIGHT_LINES[$r]}"$'\033[K\n'
    done

    # Status lines — all but the last get \n; omit \n on last line to prevent terminal scroll
    local _sl
    for (( _sl=0; _sl<${#_STATUS_LINES[@]}-1; _sl++ )); do
        _buf+="${_STATUS_LINES[$_sl]}"$'\n'
    done
    _buf+="${_STATUS_LINES[-1]}"

    # Clear any leftover content below
    _buf+=$'\033[J'

    # Single write flush
    printf '%s' "$_buf"
}

# ============================================================================
# INPUT HANDLER
# ============================================================================

read_key() {
    local key
    IFS= read -rsn1 -t 0.15 key || return 0

    # Escape sequence handling (arrow keys, etc.)
    if [[ "$key" == "$ESC" ]]; then
        local seq
        IFS= read -rsn1 -t 0.5 seq
        case "$seq" in
            '[')
                IFS= read -rsn1 -t 0.5 seq
                case "$seq" in
                    A) echo "UP" ;;
                    B) echo "DOWN" ;;
                    C) echo "RIGHT" ;;
                    D) echo "LEFT" ;;
                    Z) echo "SHIFT_TAB" ;;
                    *) echo "OTHER" ;;
                esac
                ;;
            O)
                IFS= read -rsn1 -t 0.5 seq
                case "$seq" in
                    A) echo "UP" ;;
                    B) echo "DOWN" ;;
                    C) echo "RIGHT" ;;
                    D) echo "LEFT" ;;
                    *) echo "OTHER" ;;
                esac
                ;;
            '')
                # Bare ESC (no following sequence within timeout)
                echo "ESCAPE"
                ;;
            *)
                echo "OTHER"
                ;;
        esac
    elif [[ "$key" == "" ]]; then
        echo "ENTER"
    elif [[ "$key" == " " ]]; then
        echo "SPACE"
    elif [[ "$key" == $'\t' ]]; then
        echo "TAB"
    elif [[ "$key" == $'\x7f' || "$key" == $'\x08' ]]; then
        echo "BACKSPACE"
    elif [[ "$key" == "/" ]]; then
        echo "SLASH"
    elif [[ "$key" == "q" || "$key" == "Q" ]]; then
        echo "QUIT"
    elif [[ "$key" == "a" || "$key" == "A" ]]; then
        echo "SELECT_ALL"
    elif [[ "$key" == "d" || "$key" == "D" ]]; then
        echo "DESELECT_ALL"
    elif [[ "$key" == "u" || "$key" == "U" ]]; then
        echo "UPDATE"
    else
        # Return printable character for search mode
        echo "CHAR:${key}"
    fi
}

# ============================================================================
# TERMINAL CLEANUP
# ============================================================================

# Wrapper that restores cursor/echo when the menu was active, then calls the
# original cleanup_on_exit defined in logging.sh.
_menu_cleanup_on_exit() {
    if [[ "$_MENU_ACTIVE" == "true" ]]; then
        printf '\033[?1049l'  # leave alternate screen
        show_cursor
        stty echo 2>/dev/null
        _MENU_ACTIVE=false
    fi
    cleanup_on_exit
}

# ============================================================================
# MAIN SELECTION LOOP
# ============================================================================

run_selection_menu() {
    local total=${#UTILITIES[@]}

    # Check which utilities are already installed
    check_installed_utilities

    # Fetch commit info once
    CACHED_LOCAL_COMMIT=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    CACHED_LOCAL_BRANCH=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local _remote_full
    _remote_full=$(git -C "$SCRIPT_DIR" ls-remote origin "refs/heads/${CACHED_LOCAL_BRANCH}" 2>/dev/null | awk '{print $1}')
    if [[ -z "$_remote_full" ]]; then
        _remote_full=$(git -C "$SCRIPT_DIR" ls-remote origin HEAD 2>/dev/null | awk '{print $1}')
    fi
    if [[ -n "$_remote_full" ]]; then
        CACHED_REMOTE_COMMIT="${_remote_full:0:7}"
    else
        CACHED_REMOTE_COMMIT="unknown"
    fi

    # Gather system info once
    _gather_sysinfo

    # Initialize tab names from registered categories, then reset per-tab state
    _TAB_NAMES=("${CATEGORIES[@]}")
    _ACTIVE_TAB=0
    _FOCUS="items"
    _PROFILES_CURSOR=0
    _SEARCH_QUERY=""
    _SEARCH_ACTIVE=false
    _TAB_CURSOR=()
    _TAB_SCROLL=()
    _TAB_SUBCAT=()
    local _ti
    for (( _ti=0; _ti<${#_TAB_NAMES[@]}; _ti++ )); do
        _TAB_CURSOR[$_ti]=0
        _TAB_SCROLL[$_ti]=0
        _TAB_SUBCAT[$_ti]=""
    done
    _rebuild_filtered

    # Setup terminal — enter alternate screen buffer (separate from main screen,
    # no scrollback, so resize redraws never pollute terminal history)
    printf '\033[?1049h'
    hide_cursor
    stty -echo
    _MENU_ACTIVE=true

    # Cleanup on exit
    trap '_menu_cleanup_on_exit' EXIT
    trap 'printf "\033[?1049l"; echo ""; _MENU_ACTIVE=false; show_cursor; stty echo; exit 130' INT TERM

    # Redraw on terminal resize
    # Only set flags here — never call _compose_frame inside the signal handler,
    # as it races with the active read in read_key and renders at a transitional size.
    trap '_NEEDS_SIZE_REFRESH=true; _NEEDS_REDRAW=true' WINCH

    # Initial draw
    clear
    _calc_layout
    _compose_frame

    _NEEDS_REDRAW=false

    while true; do
        # Handle pending resize — redraw here instead of inside the WINCH handler
        if [[ "$_NEEDS_REDRAW" == "true" ]]; then
            _NEEDS_REDRAW=false
            printf '\033[2J'
            _compose_frame
        fi

        local key
        key=$(read_key)
        [[ -z "$key" ]] && continue

        # --- Search mode input handling ---
        if [[ "$_SEARCH_ACTIVE" == true ]]; then
            case "$key" in
                ESCAPE)
                    _SEARCH_ACTIVE=false
                    _SEARCH_QUERY=""
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                    continue
                    ;;
                BACKSPACE)
                    if [[ -n "$_SEARCH_QUERY" ]]; then
                        _SEARCH_QUERY="${_SEARCH_QUERY%?}"
                        _TAB_CURSOR[$_ACTIVE_TAB]=0
                        _TAB_SCROLL[$_ACTIVE_TAB]=0
                        _rebuild_filtered
                    fi
                    _compose_frame
                    continue
                    ;;
                ENTER)
                    _SEARCH_ACTIVE=false
                    _FOCUS="items"
                    _compose_frame
                    continue
                    ;;
                UP)
                    if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
                        local max=$(( ${#_SEARCH_FILTERED[@]} - 1 ))
                        _TAB_CURSOR[$_ACTIVE_TAB]=$(( (_TAB_CURSOR[_ACTIVE_TAB] - 1 + ${#_SEARCH_FILTERED[@]}) % ${#_SEARCH_FILTERED[@]} ))
                        local _np=${_TAB_CURSOR[$_ACTIVE_TAB]}
                        if [[ "${_SEARCH_ITEM_TYPE[$_np]:-utility}" == "utility" ]]; then
                            CURSOR=${_SEARCH_FILTERED[$_np]}
                        fi
                        _update_scroll
                    fi
                    _compose_frame
                    continue
                    ;;
                DOWN)
                    if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
                        _TAB_CURSOR[$_ACTIVE_TAB]=$(( (_TAB_CURSOR[_ACTIVE_TAB] + 1) % ${#_SEARCH_FILTERED[@]} ))
                        local _np=${_TAB_CURSOR[$_ACTIVE_TAB]}
                        if [[ "${_SEARCH_ITEM_TYPE[$_np]:-utility}" == "utility" ]]; then
                            CURSOR=${_SEARCH_FILTERED[$_np]}
                        fi
                        _update_scroll
                    fi
                    _compose_frame
                    continue
                    ;;
                SPACE)
                    # In search mode, append a space to the query
                    if [[ "$_SEARCH_ACTIVE" == true ]]; then
                        _SEARCH_QUERY+=" "
                        _rebuild_filtered
                        _compose_frame
                        continue
                    fi
                    # Allow selection while searching (only for real utility entries)
                    if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
                        local _cur_pos=${_TAB_CURSOR[$_ACTIVE_TAB]}
                        if [[ "${_SEARCH_ITEM_TYPE[$_cur_pos]:-utility}" == "utility" ]]; then
                            CURSOR=${_SEARCH_FILTERED[$_cur_pos]}
                            if [[ ${UPDATE_SELECTED[$CURSOR]} -eq 1 ]]; then
                                UPDATE_SELECTED[$CURSOR]=0
                                SELECTED[$CURSOR]=0
                            elif [[ ${SELECTED[$CURSOR]} -eq 1 ]]; then
                                SELECTED[$CURSOR]=0
                                if [[ ${INSTALLED[$CURSOR]} -eq 1 ]]; then
                                    UPDATE_SELECTED[$CURSOR]=1
                                fi
                            else
                                SELECTED[$CURSOR]=1
                            fi
                        fi
                    fi
                    _compose_frame
                    continue
                    ;;
                CHAR:*)
                    local ch="${key#CHAR:}"
                    _SEARCH_QUERY+="$ch"
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                    continue
                    ;;
                QUIT)
                    _SEARCH_QUERY+="q"
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                    continue
                    ;;
                SELECT_ALL)
                    _SEARCH_QUERY+="a"
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                    continue
                    ;;
                DESELECT_ALL)
                    _SEARCH_QUERY+="d"
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                    continue
                    ;;
                UPDATE)
                    _SEARCH_QUERY+="u"
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                    continue
                    ;;
                TAB)
                    _SEARCH_ACTIVE=false
                    _FOCUS="items"
                    _compose_frame
                    continue
                    ;;
                *)
                    # Ignore other keys in search mode
                    continue
                    ;;
            esac
        fi

        # --- Normal mode input handling ---
        case "$key" in
            ESCAPE)
                if [[ -n "$_SEARCH_QUERY" ]]; then
                    _SEARCH_QUERY=""
                    _TAB_CURSOR[$_ACTIVE_TAB]=0
                    _TAB_SCROLL[$_ACTIVE_TAB]=0
                    _rebuild_filtered
                    _compose_frame
                fi
                ;;
            TAB|SHIFT_TAB)
                # Cycle focus forward: tabs → profiles → items (TAB)
                # Cycle focus reverse: tabs → items → profiles  (SHIFT_TAB)
                if [[ "$key" == "TAB" ]]; then
                    case "$_FOCUS" in
                        tabs)     _FOCUS="profiles" ;;
                        profiles) _FOCUS="items" ;;
                        items)    _FOCUS="tabs" ;;
                    esac
                else
                    case "$_FOCUS" in
                        tabs)     _FOCUS="items" ;;
                        items)    _FOCUS="profiles" ;;
                        profiles) _FOCUS="tabs" ;;
                    esac
                fi
                _compose_frame
                ;;
            SLASH)
                _SEARCH_ACTIVE=true
                _FOCUS="items"
                _compose_frame
                ;;
            UP)
                if [[ "$_FOCUS" == "tabs" ]]; then
                    _ACTIVE_TAB=$(( (_ACTIVE_TAB - 1 + ${#_TAB_NAMES[@]}) % ${#_TAB_NAMES[@]} ))
                    _SEARCH_QUERY=""
                    _rebuild_filtered
                    _update_scroll
                elif [[ "$_FOCUS" == "profiles" ]] && (( ${#PROFILES[@]} > 0 )); then
                    _PROFILES_CURSOR=$(( (_PROFILES_CURSOR - 1 + ${#PROFILES[@]}) % ${#PROFILES[@]} ))
                else
                    if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
                        _TAB_CURSOR[$_ACTIVE_TAB]=$(( (_TAB_CURSOR[_ACTIVE_TAB] - 1 + ${#_SEARCH_FILTERED[@]}) % ${#_SEARCH_FILTERED[@]} ))
                        local _np=${_TAB_CURSOR[$_ACTIVE_TAB]}
                        if [[ "${_SEARCH_ITEM_TYPE[$_np]:-utility}" == "utility" ]]; then
                            CURSOR=${_SEARCH_FILTERED[$_np]}
                        fi
                        _update_scroll
                    fi
                fi
                _compose_frame
                ;;
            DOWN)
                if [[ "$_FOCUS" == "tabs" ]]; then
                    _ACTIVE_TAB=$(( (_ACTIVE_TAB + 1) % ${#_TAB_NAMES[@]} ))
                    _SEARCH_QUERY=""
                    _rebuild_filtered
                    _update_scroll
                elif [[ "$_FOCUS" == "profiles" ]] && (( ${#PROFILES[@]} > 0 )); then
                    _PROFILES_CURSOR=$(( (_PROFILES_CURSOR + 1) % ${#PROFILES[@]} ))
                else
                    if (( ${#_SEARCH_FILTERED[@]} > 0 )); then
                        _TAB_CURSOR[$_ACTIVE_TAB]=$(( (_TAB_CURSOR[_ACTIVE_TAB] + 1) % ${#_SEARCH_FILTERED[@]} ))
                        local _np=${_TAB_CURSOR[$_ACTIVE_TAB]}
                        if [[ "${_SEARCH_ITEM_TYPE[$_np]:-utility}" == "utility" ]]; then
                            CURSOR=${_SEARCH_FILTERED[$_np]}
                        fi
                        _update_scroll
                    fi
                fi
                _compose_frame
                ;;
            LEFT)
                if [[ "$_FOCUS" == "items" ]]; then
                    # If inside a subcategory, LEFT goes up to the parent level
                    if [[ -n "${_TAB_SUBCAT[$_ACTIVE_TAB]:-}" ]]; then
                        _TAB_SUBCAT[$_ACTIVE_TAB]=""
                        _TAB_CURSOR[$_ACTIVE_TAB]=0
                        _TAB_SCROLL[$_ACTIVE_TAB]=0
                        _rebuild_filtered
                    else
                        _FOCUS="tabs"
                    fi
                    _compose_frame
                elif [[ "$_FOCUS" == "profiles" ]]; then
                    _FOCUS="tabs"
                    _compose_frame
                fi
                ;;
            RIGHT)
                if [[ "$_FOCUS" == "tabs" ]]; then
                    _FOCUS="items"
                    _compose_frame
                fi
                ;;
            SPACE)
                # Apply the highlighted profile if the profiles section is focused
                if [[ "$_FOCUS" == "profiles" ]] && (( ${#PROFILES[@]} > 0 )); then
                    apply_profile "$_PROFILES_CURSOR"
                    _FOCUS="items"
                    _compose_frame
                    continue
                fi
                if [[ "$_FOCUS" == "items" && ${#_SEARCH_FILTERED[@]} -gt 0 ]]; then
                    local _cur_pos=${_TAB_CURSOR[$_ACTIVE_TAB]}
                    local _cur_type="${_SEARCH_ITEM_TYPE[$_cur_pos]:-utility}"
                    # [D] entries are not selectable
                    if [[ "$_cur_type" == "utility" ]]; then
                        CURSOR=${_SEARCH_FILTERED[$_cur_pos]}
                        # Cycle: [ ] -> [✓] -> [U] (if installed) -> [ ]
                        if [[ ${UPDATE_SELECTED[$CURSOR]} -eq 1 ]]; then
                            UPDATE_SELECTED[$CURSOR]=0
                            SELECTED[$CURSOR]=0
                        elif [[ ${SELECTED[$CURSOR]} -eq 1 ]]; then
                            SELECTED[$CURSOR]=0
                            if [[ ${INSTALLED[$CURSOR]} -eq 1 ]]; then
                                UPDATE_SELECTED[$CURSOR]=1
                            fi
                        else
                            SELECTED[$CURSOR]=1
                        fi
                        _compose_frame
                    fi
                fi
                ;;
            UPDATE)
                if [[ "$_FOCUS" == "items" && ${#_SEARCH_FILTERED[@]} -gt 0 ]]; then
                    local _cur_pos=${_TAB_CURSOR[$_ACTIVE_TAB]}
                    if [[ "${_SEARCH_ITEM_TYPE[$_cur_pos]:-utility}" == "utility" ]]; then
                        CURSOR=${_SEARCH_FILTERED[$_cur_pos]}
                        if [[ ${INSTALLED[$CURSOR]} -eq 1 ]]; then
                            SELECTED[$CURSOR]=0
                            if [[ ${UPDATE_SELECTED[$CURSOR]} -eq 0 ]]; then
                                UPDATE_SELECTED[$CURSOR]=1
                            else
                                UPDATE_SELECTED[$CURSOR]=0
                            fi
                            _compose_frame
                        fi
                    fi
                fi
                ;;
            SELECT_ALL)
                # Select all utilities in current filtered view (skip [D] entries)
                for (( _sa_i=0; _sa_i<${#_SEARCH_FILTERED[@]}; _sa_i++ )); do
                    [[ "${_SEARCH_ITEM_TYPE[$_sa_i]:-utility}" != "utility" ]] && continue
                    local _sa_idx=${_SEARCH_FILTERED[$_sa_i]}
                    SELECTED[$_sa_idx]=1
                    UPDATE_SELECTED[$_sa_idx]=0
                done
                _compose_frame
                ;;
            DESELECT_ALL)
                # Deselect all utilities in current filtered view (skip [D] entries)
                for (( _da_i=0; _da_i<${#_SEARCH_FILTERED[@]}; _da_i++ )); do
                    [[ "${_SEARCH_ITEM_TYPE[$_da_i]:-utility}" != "utility" ]] && continue
                    local _da_idx=${_SEARCH_FILTERED[$_da_i]}
                    SELECTED[$_da_idx]=0
                    UPDATE_SELECTED[$_da_idx]=0
                done
                _compose_frame
                ;;
            ENTER)
                # Apply the highlighted profile if the profiles section is focused
                if [[ "$_FOCUS" == "profiles" ]] && (( ${#PROFILES[@]} > 0 )); then
                    apply_profile "$_PROFILES_CURSOR"
                    _FOCUS="items"
                    _compose_frame
                    continue
                fi
                # If focused on a [D] entry, navigate into/out of subcategory
                if [[ "$_FOCUS" == "items" && ${#_SEARCH_FILTERED[@]} -gt 0 ]]; then
                    local _cur_pos=${_TAB_CURSOR[$_ACTIVE_TAB]}
                    local _cur_type="${_SEARCH_ITEM_TYPE[$_cur_pos]:-utility}"
                    if [[ "$_cur_type" == "subcat" ]]; then
                        _TAB_SUBCAT[$_ACTIVE_TAB]="${_SEARCH_ITEM_LABEL[$_cur_pos]}"
                        _TAB_CURSOR[$_ACTIVE_TAB]=0
                        _TAB_SCROLL[$_ACTIVE_TAB]=0
                        _rebuild_filtered
                        _compose_frame
                        continue
                    elif [[ "$_cur_type" == "up" ]]; then
                        _TAB_SUBCAT[$_ACTIVE_TAB]=""
                        _TAB_CURSOR[$_ACTIVE_TAB]=0
                        _TAB_SCROLL[$_ACTIVE_TAB]=0
                        _rebuild_filtered
                        _compose_frame
                        continue
                    fi
                fi

                # Ignore ENTER when no actions are selected.
                local _has_selection=0
                local _sel_i
                for (( _sel_i=0; _sel_i<${#UTILITIES[@]}; _sel_i++ )); do
                    if [[ ${SELECTED[$_sel_i]} -eq 1 || ${UPDATE_SELECTED[$_sel_i]} -eq 1 ]]; then
                        _has_selection=1
                        break
                    fi
                done
                if (( _has_selection == 0 )); then
                    _compose_frame
                    continue
                fi

                # Otherwise confirm selections and exit menu
                printf '\033[?1049l'  # leave alternate screen
                show_cursor
                stty echo
                _MENU_ACTIVE=false
                trap - WINCH INT TERM
                trap cleanup_on_exit EXIT
                return 0
                ;;
            QUIT)
                printf '\033[?1049l'  # leave alternate screen
                show_cursor
                stty echo
                _MENU_ACTIVE=false
                trap - WINCH INT TERM
                trap cleanup_on_exit EXIT
                echo ""
                echo "${YELLOW}Operation cancelled.${RESET}"
                exit 0
                ;;
        esac
    done
}
