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
    # Remove any registered temp files/dirs
    for _f in "${CLEANUP_FILES[@]}"; do
        rm -rf "$_f" 2>/dev/null || true
    done
}

# Trap errors and log them (skip intentional failures in conditionals)
_err_handler() {
    local _exit_code=$?
    # Suppress logging for common intentional-failure patterns
    case "$BASH_COMMAND" in
        *"command -v"*|*"grep -q"*|*"2>/dev/null"*|*"&>/dev/null"*|*"|| true"*|*"|| return"*|*"|| warn"*|*"|| echo"*)
            return 0 ;;
    esac
    # check_* functions return 1 to indicate "not installed", not an error
    if [[ "${FUNCNAME[1]:-}" == check_* ]]; then
        return 0
    fi
    log_error "Unexpected error at line ${BASH_LINENO[0]:-$LINENO}: Command \"$BASH_COMMAND\" failed (exit $_exit_code)"
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [SUCCESS] ${message}" >> "$SUCCESS_LOG"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    init_error_log
    echo "[${timestamp}] [ERROR] ${message}" | tee -a "$ERROR_LOG" >&2
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    init_error_log
    echo "[${timestamp}] [WARNING] ${message}" | tee -a "$ERROR_LOG"
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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
