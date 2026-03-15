#!/bin/bash

# ============================================================================
# Linux Utilities - Configuration Module
# Provides configuration file parsing, verbose/debug output helpers
# ============================================================================

# --- Default Configuration Values ---
# These are overridden by linux_util.conf if present.
CFG_LOG_RETENTION_DAYS=30
CFG_MAX_LOG_SIZE_MB=50
CFG_COMPRESS_OLD_LOGS=true
CFG_LOG_LEVEL="INFO"      # DEBUG, INFO, WARNING, ERROR

CFG_AUTO_CONFIRM=false
CFG_PARALLEL_INSTALLS=false
CFG_MAX_PARALLEL=3
CFG_RETRY_FAILED=true
CFG_RETRY_ATTEMPTS=3

CFG_DNS_CHECK_ENABLED=true
CFG_DNS_TIMEOUT_SECONDS=10
CFG_DISK_MIN_MB=1024       # Minimum free disk space in MB

CFG_AUTO_CLEANUP=true
CFG_CREATE_BACKUPS=true
CFG_BACKUP_DIR="${SCRIPT_DIR}/backups"

# --- Verbose / Debug Mode ---
VERBOSE=false
DEBUG=false

verbose() {
    [[ "$VERBOSE" == "true" ]] && printf '\e[36m[VERBOSE]\e[0m %s\n' "$*"
}

debug() {
    [[ "$DEBUG" == "true" ]] && printf '\e[35m[DEBUG]\e[0m %s\n' "$*" >&2
}

# --- Configuration File Parser ---
# Reads key=value pairs from a config file, ignoring comments and blank lines.
# Only sets variables that match known CFG_* keys (whitelist approach).
load_config() {
    local config_file="${1:-${SCRIPT_DIR}/linux_util.conf}"

    if [[ ! -f "$config_file" ]]; then
        debug "No config file found at ${config_file}, using defaults."
        return 0
    fi

    debug "Loading configuration from ${config_file}"

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Skip INI section headers like [Logging]
        [[ "$line" =~ ^[[:space:]]*\[.*\] ]] && continue

        # Extract key=value
        key="${line%%=*}"
        value="${line#*=}"

        # Trim whitespace
        key="$(echo "$key" | tr -d '[:space:]')"
        value="$(echo "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        # Map config keys to CFG_ variables (whitelist)
        case "$key" in
            log_retention_days)     CFG_LOG_RETENTION_DAYS="$value" ;;
            max_log_size_mb)        CFG_MAX_LOG_SIZE_MB="$value" ;;
            compress_old_logs)      CFG_COMPRESS_OLD_LOGS="$value" ;;
            log_level)              CFG_LOG_LEVEL="$value" ;;
            auto_confirm)           CFG_AUTO_CONFIRM="$value" ;;
            parallel_installs)      CFG_PARALLEL_INSTALLS="$value" ;;
            max_parallel)           CFG_MAX_PARALLEL="$value" ;;
            retry_failed)           CFG_RETRY_FAILED="$value" ;;
            retry_attempts)         CFG_RETRY_ATTEMPTS="$value" ;;
            dns_check_enabled)      CFG_DNS_CHECK_ENABLED="$value" ;;
            dns_timeout_seconds)    CFG_DNS_TIMEOUT_SECONDS="$value" ;;
            disk_min_mb)            CFG_DISK_MIN_MB="$value" ;;
            auto_cleanup)           CFG_AUTO_CLEANUP="$value" ;;
            create_backups)         CFG_CREATE_BACKUPS="$value" ;;
            backup_dir)             CFG_BACKUP_DIR="$value" ;;
            verbose)                VERBOSE="$value" ;;
            debug)                  DEBUG="$value" ;;
            *)
                debug "Unknown config key: ${key}"
                ;;
        esac
    done < "$config_file"

    verbose "Configuration loaded from ${config_file}"
    return 0
}
