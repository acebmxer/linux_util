#!/bin/bash
set -o pipefail

# ============================================================================
# Log Management Utility for linux_util.sh
# View, search, and manage log files
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

# Colors (unified with linux_util.sh)
ESC=$'\e'
CSI="${ESC}["
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
BLUE="${CSI}34m"
CYAN="${CSI}36m"
BOLD="${CSI}1m"
RESET="${CSI}0m"

# Respect the NO_COLOR standard (https://no-color.org/) and non-interactive terminals.
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" RESET=""
fi

show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all log files"
    echo "  view [success|error|latest]   View log file"
    echo "  tail [success|error]          Tail log file (follow mode)"
    echo "  search <pattern>              Search in all logs"
    echo "  stats                         Show log statistics"
    echo "  clean [days] [--count-per-day N]  Remove logs older than N days and/or keep at most N per day per type"
    echo "  compress                      Compress old logs"
    echo "  help                          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 view latest"
    echo "  $0 search 'Docker'"
    echo "  $0 clean 7"
}

list_logs() {
    echo "${BOLD}${CYAN}Log files in ${LOG_DIR}:${RESET}"
    echo ""
    
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "${RED}Log directory not found: ${LOG_DIR}${RESET}"
        return 1
    fi
    
    local -a success_logs=()
    mapfile -t success_logs < <(ls -t "$LOG_DIR"/success_*.log 2>/dev/null)
    local -a error_logs=()
    mapfile -t error_logs < <(ls -t "$LOG_DIR"/error_*.log 2>/dev/null)
    
    if [[ ${#success_logs[@]} -eq 0 ]] && [[ ${#error_logs[@]} -eq 0 ]]; then
        echo "${YELLOW}No log files found.${RESET}"
        return 0
    fi
    
    if [[ ${#success_logs[@]} -gt 0 ]]; then
        echo "${BOLD}${GREEN}Success Logs:${RESET}"
        for log in "${success_logs[@]}"; do
            local size; size=$(du -h "$log" | cut -f1)
            local date; date=$(stat -c %y "$log" | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo "  $(basename "$log") - ${size} - ${date}"
        done
        echo ""
    fi

    if [[ ${#error_logs[@]} -gt 0 ]]; then
        echo "${BOLD}${RED}Error Logs:${RESET}"
        for log in "${error_logs[@]}"; do
            local size; size=$(du -h "$log" | cut -f1)
            local date; date=$(stat -c %y "$log" | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo "  $(basename "$log") - ${size} - ${date}"
        done
    fi
}

view_log() {
    local type="$1"
    local log_file=""
    
    case "$type" in
        success)
            log_file="${LOG_DIR}/success_latest.log"
            ;;
        error)
            log_file="${LOG_DIR}/error_latest.log"
            ;;
        latest)
            echo "${BOLD}${GREEN}=== Success Log ===${RESET}"
            view_log success
            echo ""
            echo "${BOLD}${RED}=== Error Log ===${RESET}"
            view_log error
            return
            ;;
        *)
            echo "${RED}Invalid log type. Use: success, error, or latest${RESET}"
            return 1
            ;;
    esac
    
    if [[ ! -f "$log_file" ]]; then
        echo "${YELLOW}Log file not found: $log_file${RESET}"
        return 1
    fi
    
    if command -v less &>/dev/null; then
        less -R "$log_file"
    else
        cat "$log_file"
    fi
}

tail_log() {
    local type="$1"
    local log_file=""
    
    case "$type" in
        success)
            log_file="${LOG_DIR}/success_latest.log"
            ;;
        error)
            log_file="${LOG_DIR}/error_latest.log"
            ;;
        *)
            echo "${RED}Invalid log type. Use: success or error${RESET}"
            return 1
            ;;
    esac
    
    if [[ ! -f "$log_file" ]]; then
        echo "${YELLOW}Log file not found: $log_file${RESET}"
        return 1
    fi
    
    echo "${BOLD}Tailing ${type} log (Ctrl+C to stop)...${RESET}"
    tail -f "$log_file"
}

search_logs() {
    local pattern="$1"
    
    if [[ -z "$pattern" ]]; then
        echo "${RED}Error: Search pattern required${RESET}"
        return 1
    fi
    
    echo "${BOLD}${CYAN}Searching for: ${pattern}${RESET}"
    echo ""
    
    local found=0
    
    # Search in all log files
    for log in "$LOG_DIR"/*.log; do
        if [[ -f "$log" ]]; then
            local matches; matches=$(grep -i "$pattern" "$log" 2>/dev/null) || true
            if [[ -n "$matches" ]]; then
                echo "${BOLD}${GREEN}=== $(basename "$log") ===${RESET}"
                echo "$matches"
                echo ""
                ((found++))
            fi
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo "${YELLOW}No matches found.${RESET}"
    else
        echo "${GREEN}Found matches in ${found} file(s).${RESET}"
    fi
}

show_stats() {
    echo "${BOLD}${CYAN}Log Statistics:${RESET}"
    echo ""
    
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "${RED}Log directory not found.${RESET}"
        return 1
    fi
    
    local total_logs; total_logs=$(find "$LOG_DIR" -name "*.log" 2>/dev/null | wc -l)
    local total_size; total_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
    local -a _s_logs=("$LOG_DIR"/success_*.log)
    [[ -e "${_s_logs[0]}" ]] || _s_logs=()
    local success_count=${#_s_logs[@]}
    local -a _e_logs=("$LOG_DIR"/error_*.log)
    [[ -e "${_e_logs[0]}" ]] || _e_logs=()
    local error_count=${#_e_logs[@]}
    
    echo "Total log files: ${total_logs}"
    echo "Total size: ${total_size}"
    echo "Success logs: ${success_count}"
    echo "Error logs: ${error_count}"
    echo ""
    
    # Recent executions
    if [[ -f "${LOG_DIR}/success_latest.log" ]]; then
        echo "${BOLD}Last execution:${RESET}"
        head -n 5 "${LOG_DIR}/success_latest.log" | tail -n 3
        echo ""
        
        # Count successes and errors
        local successes; successes=$(grep -c "\[SUCCESS\]" "${LOG_DIR}/success_latest.log" 2>/dev/null || echo 0)
        local errors; errors=$(grep -c "\[ERROR\]" "${LOG_DIR}/error_latest.log" 2>/dev/null || echo 0)
        local warnings; warnings=$(grep -c "\[WARNING\]" "${LOG_DIR}/error_latest.log" 2>/dev/null || echo 0)
        
        echo "Latest run statistics:"
        echo "  ${GREEN}✓ Successes: ${successes}${RESET}"
        echo "  ${RED}✗ Errors: ${errors}${RESET}"
        echo "  ${YELLOW}⚠ Warnings: ${warnings}${RESET}"
    fi
}

clean_logs() {
    local days=""
    local max_per_day=0

    # Parse arguments: any order of [days] and [--count-per-day N]
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count-per-day)
                shift
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    max_per_day="$1"
                else
                    echo "${RED}Error: --count-per-day requires a positive integer${RESET}"
                    return 1
                fi
                ;;
            [0-9]*)
                days="$1"
                ;;
            *)
                echo "${RED}Error: Unknown argument: $1${RESET}"
                return 1
                ;;
        esac
        shift
    done

    days="${days:-30}"

    if [[ ! -d "$LOG_DIR" ]]; then
        echo "${RED}Log directory not found.${RESET}"
        return 1
    fi

    # Collect files to remove
    local -a age_files=() excess_files=()

    # Age-based: logs older than $days days (skip symlinks, metrics)
    mapfile -t age_files < <(
        find "$LOG_DIR" -maxdepth 1 -name "*.log" -type f \
            ! -name "*_latest.log" ! -name "metrics.log" \
            -mtime +"${days}" 2>/dev/null
    )

    # Per-day cap: for each type, for each calendar day, collect files beyond the limit
    if [[ $max_per_day -gt 0 ]]; then
        local prefix
        for prefix in success error; do
            local -a dates=()
            mapfile -t dates < <(
                find "$LOG_DIR" -maxdepth 1 \
                    -name "${prefix}_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*.log" \
                    -type f ! -name "*_latest.log" -printf '%f\n' 2>/dev/null \
                    | sed "s/^${prefix}_//" | cut -c1-8 | sort -u
            )
            local date
            for date in "${dates[@]}"; do
                local -a day_logs=()
                mapfile -t day_logs < <(
                    find "$LOG_DIR" -maxdepth 1 \
                        -name "${prefix}_${date}_*.log" \
                        -type f ! -name "*_latest.log" \
                        -printf '%T@ %p\n' 2>/dev/null \
                        | sort -rn | awk '{print $2}'
                )
                local day_count=${#day_logs[@]}
                if [[ $day_count -gt $max_per_day ]]; then
                    excess_files+=("${day_logs[@]:$max_per_day}")
                fi
            done
        done
    fi

    if [[ ${#age_files[@]} -eq 0 && ${#excess_files[@]} -eq 0 ]]; then
        echo "${GREEN}No logs to clean.${RESET}"
        return 0
    fi

    [[ ${#age_files[@]} -gt 0 ]] && \
        echo "${BOLD}${YELLOW}Found ${#age_files[@]} log(s) older than ${days} days.${RESET}"
    [[ ${#excess_files[@]} -gt 0 ]] && \
        echo "${BOLD}${YELLOW}Found ${#excess_files[@]} log(s) exceeding ${max_per_day} per day.${RESET}"

    read -p "Are you sure? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        [[ ${#age_files[@]} -gt 0 ]] && rm -f "${age_files[@]}"
        [[ ${#excess_files[@]} -gt 0 ]] && rm -f "${excess_files[@]}"
        echo "${GREEN}✓ Logs cleaned.${RESET}"
    else
        echo "Cancelled."
    fi
}

compress_logs() {
    echo "${BOLD}${CYAN}Compressing old logs (older than 7 days)...${RESET}"
    
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "${RED}Log directory not found.${RESET}"
        return 1
    fi
    
    local compressed=0
    
    while IFS= read -r -d '' log; do
        if [[ "$log" != *.gz ]] && [[ "$log" != *latest.log ]]; then
            echo "Compressing $(basename "$log")..."
            gzip "$log"
            ((compressed++))
        fi
    done < <(find "$LOG_DIR" -name "*.log" -type f -mtime +7 -print0 2>/dev/null)
    
    if [[ $compressed -eq 0 ]]; then
        echo "${YELLOW}No logs to compress.${RESET}"
    else
        echo "${GREEN}✓ Compressed ${compressed} log file(s).${RESET}"
    fi
}

# Main
case "${1:-help}" in
    list)
        list_logs
        ;;
    view)
        view_log "${2:-latest}"
        ;;
    tail)
        tail_log "${2:-success}"
        ;;
    search)
        search_logs "$2"
        ;;
    stats)
        show_stats
        ;;
    clean)
        clean_logs "${@:2}"
        ;;
    compress)
        compress_logs
        ;;
    help|*)
        show_usage
        ;;
esac
