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
    echo "  clean [days]                  Remove logs older than N days (default: 30)"
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
            local size=$(du -h "$log" | cut -f1)
            local date=$(stat -c %y "$log" | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo "  $(basename "$log") - ${size} - ${date}"
        done
        echo ""
    fi
    
    if [[ ${#error_logs[@]} -gt 0 ]]; then
        echo "${BOLD}${RED}Error Logs:${RESET}"
        for log in "${error_logs[@]}"; do
            local size=$(du -h "$log" | cut -f1)
            local date=$(stat -c %y "$log" | cut -d'.' -f1)
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
            local matches=$(grep -i "$pattern" "$log" 2>/dev/null)
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
    
    local total_logs=$(find "$LOG_DIR" -name "*.log" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
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
        local successes=$(grep -c "\[SUCCESS\]" "${LOG_DIR}/success_latest.log" 2>/dev/null || echo 0)
        local errors=$(grep -c "\[ERROR\]" "${LOG_DIR}/error_latest.log" 2>/dev/null || echo 0)
        local warnings=$(grep -c "\[WARNING\]" "${LOG_DIR}/error_latest.log" 2>/dev/null || echo 0)
        
        echo "Latest run statistics:"
        echo "  ${GREEN}✓ Successes: ${successes}${RESET}"
        echo "  ${RED}✗ Errors: ${errors}${RESET}"
        echo "  ${YELLOW}⚠ Warnings: ${warnings}${RESET}"
    fi
}

clean_logs() {
    local days="${1:-30}"
    
    echo "${BOLD}${YELLOW}Removing logs older than ${days} days...${RESET}"
    
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "${RED}Log directory not found.${RESET}"
        return 1
    fi
    
    local count=$(find "$LOG_DIR" -name "*.log" -type f -mtime +${days} 2>/dev/null | wc -l)
    
    if [[ $count -eq 0 ]]; then
        echo "${GREEN}No old logs to clean.${RESET}"
        return 0
    fi
    
    echo "Found ${count} log file(s) to remove."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find "$LOG_DIR" -name "*.log" -type f -mtime +${days} -delete
        echo "${GREEN}✓ Old logs removed.${RESET}"
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
        clean_logs "$2"
        ;;
    compress)
        compress_logs
        ;;
    help|*)
        show_usage
        ;;
esac
