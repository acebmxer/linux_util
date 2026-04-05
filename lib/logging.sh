#!/bin/bash

# ============================================================================
# Linux Utilities - Logging Module
# Provides logging functions, error handling, and cleanup utilities
# ============================================================================

# --- Global temp-file cleanup ---
# Functions that create temp files should append paths to this array.
# On exit (normal or interrupted), all registered files are removed.
declare -a CLEANUP_FILES=()
SUDO_KEEPALIVE_PID=""

cleanup_on_exit() {
    # Kill sudo keep-alive background process
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    # Remove sudo PID file
    rm -f "${LOCK_FILE}.pid" 2>/dev/null || true
    # Remove any registered temp files/dirs
    for _f in "${CLEANUP_FILES[@]}"; do
        rm -rf "$_f" 2>/dev/null || true
    done
}

# Function to initialize error log on first error
init_error_log() {
    if [[ "$ERROR_LOG_INITIALIZED" == "false" ]]; then
        {
            echo "════════════════════════════════════════════════════════════════"
            echo "Linux Utilities Installer - Error Log"
            echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "User: $USER"
            echo "Hostname: $(hostname)"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
        } > "$ERROR_LOG"
        ERROR_LOG_INITIALIZED=true
        # Create/update latest error log symlink
        ln -sf "$(basename "$ERROR_LOG")" "$LATEST_ERROR_LOG" 2>/dev/null || cp "$ERROR_LOG" "$LATEST_ERROR_LOG"
    fi
}

# Logging functions
log_success() {
    local message="$1"
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [SUCCESS] ${message}" >> "$SUCCESS_LOG"
}

log_error() {
    local message="$1"
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    init_error_log
    echo "[${timestamp}] [ERROR] ${message}" | tee -a "$ERROR_LOG" >&2
}

log_warning() {
    local message="$1"
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    init_error_log
    echo "[${timestamp}] [WARNING] ${message}" | tee -a "$ERROR_LOG"
}

log_info() {
    local message="$1"
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [INFO] ${message}" >> "$SUCCESS_LOG"
}

# Function to log command execution with error capture
log_command() {
    local description="$1"
    shift
    local cmd="$*"

    log_info "Executing: ${description}"
    log_info "Command: ${cmd}"

    local output
    local exit_code

    output=$("$@" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "${description} completed successfully"
        if [[ -n "$output" ]]; then
            echo "[OUTPUT] ${output}" >> "$SUCCESS_LOG"
        fi
    else
        log_error "${description} failed with exit code ${exit_code}"
        log_error "Command: ${cmd}"
        if [[ -n "$output" ]]; then
            init_error_log
            echo "[ERROR OUTPUT] ${output}" >> "$ERROR_LOG"
        fi
    fi

    return $exit_code
}

# ============================================================================
# Spinner
# Runs a command in the background while showing an animated spinner.
# Usage: run_with_spinner "Label" command [args...]
# On success: prints ✓ label and appends captured output to the success log.
# On failure: prints ✗ label and dumps captured output to the terminal.
# ============================================================================

run_with_spinner() {
    local label="$1"
    shift

    # Non-interactive fallback: run directly with a plain status line
    if [[ ! -t 1 ]]; then
        echo "  ${label}..."
        "$@"
        return $?
    fi

    local _tmp _fifo _fd
    _tmp=$(mktemp) || { error "Failed to create temp file"; return 1; }
    CLEANUP_FILES+=("$_tmp")

    # Open a FIFO for reliable 0.1s frame-rate timing.
    # read -rt 0.1 <>/dev/null returns immediately because /dev/null gives EOF
    # instantly — it does not honor the timeout. A FIFO with both ends held open
    # has no EOF, so read blocks for exactly the timeout duration on every system
    # and terminal, regardless of speed. The path is unlinked immediately after
    # open; the fd keeps the pipe alive until we close it.
    _fifo=$(mktemp -u /tmp/.spin_XXXXXX)
    mkfifo "$_fifo" 2>/dev/null
    exec {_fd}<>"$_fifo"
    rm -f "$_fifo"

    # Run command in background, capturing all output
    "$@" >"$_tmp" 2>&1 &
    local _pid=$!

    # Animate spinner until the command completes.
    # Print the first frame before the loop so a fast-completing command still
    # shows one frame rather than no spinner at all (race-condition guard).
    local _frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local _i=0
    printf "\r  ${CYAN}%s${RESET}  %s" "${_frames[0]}" "$label"
    (( _i++ )) || true
    while kill -0 "$_pid" 2>/dev/null; do
        read -rt 0.1 <&"$_fd" || true
        printf "\r  ${CYAN}%s${RESET}  %s" "${_frames[$(( _i % 10 ))]}" "$label"
        (( _i++ )) || true
    done

    exec {_fd}>&-

    wait "$_pid"
    local _rc=$?

    # Clear the spinner line
    printf "\r\033[K"

    if [[ $_rc -eq 0 ]]; then
        printf "  ${GREEN}✓${RESET}  %s\n" "$label"
        [[ -s "$_tmp" ]] && cat "$_tmp" >> "$SUCCESS_LOG"
    else
        printf "  ${RED}✗${RESET}  %s\n" "$label"
        [[ -s "$_tmp" ]] && cat "$_tmp"
    fi

    rm -f "$_tmp"
    return $_rc
}

# ============================================================================
# Direct Runner (Interactive)
# Runs a command directly in the foreground with full stdin/stdout/stderr.
# Use this instead of run_with_spinner when the command may prompt the user
# (e.g., dpkg config file conflicts, needrestart dialogs).
# Usage: run_direct "Label" command [args...]
# ============================================================================

run_direct() {
    local label="$1"
    shift

    printf "  %s ...\n" "$label"

    "$@"
    local _rc=$?

    if [[ $_rc -eq 0 ]]; then
        printf "  ${GREEN}✓${RESET}  %s\n" "$label"
    else
        printf "  ${RED}✗${RESET}  %s\n" "$label"
    fi

    return $_rc
}

# ============================================================================
# Performance Metrics
# Tracks per-operation timing and saves to a persistent metrics log.
# ============================================================================

# Script-level start time (epoch seconds)
SCRIPT_START_TIME=""

# Metrics log file (append-only, one line per operation)
METRICS_LOG=""

# Initialize the metrics system. Call once at script start.
metrics_init() {
    SCRIPT_START_TIME=$(date +%s)
    METRICS_LOG="${LOG_DIR}/metrics.log"

    # Write header if file is new
    if [[ ! -f "$METRICS_LOG" ]]; then
        echo "# linux_util performance metrics" > "$METRICS_LOG"
        echo "# Format: timestamp | operation | utility | duration_seconds | status" >> "$METRICS_LOG"
    fi
}

# Record a single operation's metrics.
# Usage: metrics_record "install" "Docker" 42 "success"
metrics_record() {
    local operation="$1"
    local utility="$2"
    local duration="$3"
    local status="$4"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    [[ -z "$METRICS_LOG" ]] && return 0

    echo "${timestamp} | ${operation} | ${utility} | ${duration}s | ${status}" >> "$METRICS_LOG"
}

# Print a metrics summary for the current run.
# Shows total execution time and per-operation stats.
metrics_summary() {
    [[ -z "$SCRIPT_START_TIME" ]] && return 0

    local end_time
    end_time=$(date +%s)
    local total_duration=$(( end_time - SCRIPT_START_TIME ))
    local minutes=$(( total_duration / 60 ))
    local seconds=$(( total_duration % 60 ))

    echo ""
    echo "Total execution time: ${minutes}m ${seconds}s"
    log_info "Total execution time: ${minutes}m ${seconds}s"
    metrics_record "session" "total" "$total_duration" "complete"
}

# ============================================================================
# Log Pruning
# Silently removes old log files at startup based on two independent limits:
#   - Age:         files older than CFG_LOG_RETENTION_DAYS days are deleted.
#   - Per-day cap: for each log type (success, error) and each calendar day,
#                  oldest files beyond CFG_MAX_LOGS_PER_DAY are deleted.
#                  Days within the retention window are unaffected unless they
#                  exceed the per-day cap.
# Symlinks (*_latest.log) and metrics.log are always preserved.
# ============================================================================
prune_logs() {
    local log_dir="${LOG_DIR}"
    local max_age_days="${CFG_LOG_RETENTION_DAYS:-30}"
    local max_per_day="${CFG_MAX_LOGS_PER_DAY:-0}"

    [[ -d "$log_dir" ]] || return 0

    # Age-based: remove timestamped logs older than max_age_days
    if [[ "$max_age_days" -gt 0 ]]; then
        find "$log_dir" -maxdepth 1 -name "*.log" -type f \
            ! -name "*_latest.log" ! -name "metrics.log" \
            -mtime +"${max_age_days}" -delete 2>/dev/null || true
    fi

    # Per-day cap: for each log type, for each calendar day, keep only the
    # newest max_per_day files from that day, leaving all other days untouched.
    if [[ "$max_per_day" -gt 0 ]]; then
        local prefix
        for prefix in success error; do
            # Collect the unique YYYYMMDD dates present in log filenames
            local -a dates=()
            mapfile -t dates < <(
                find "$log_dir" -maxdepth 1 \
                    -name "${prefix}_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*.log" \
                    -type f ! -name "*_latest.log" -printf '%f\n' 2>/dev/null \
                    | sed "s/^${prefix}_//" | cut -c1-8 | sort -u
            )
            local date
            for date in "${dates[@]}"; do
                local -a day_logs=()
                mapfile -t day_logs < <(
                    find "$log_dir" -maxdepth 1 \
                        -name "${prefix}_${date}_*.log" \
                        -type f ! -name "*_latest.log" \
                        -printf '%T@ %p\n' 2>/dev/null \
                        | sort -rn | awk '{print $2}'
                )
                local day_count=${#day_logs[@]}
                if [[ $day_count -gt $max_per_day ]]; then
                    local i
                    for (( i = max_per_day; i < day_count; i++ )); do
                        rm -f "${day_logs[$i]}" 2>/dev/null || true
                    done
                fi
            done
        done
    fi
}
