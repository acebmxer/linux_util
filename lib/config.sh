#!/bin/bash

# ============================================================================
# Linux Utilities - Configuration Module
# Provides configuration file parsing, verbose/debug output helpers
# ============================================================================

# --- Default Configuration Values ---
# These are overridden by linux_util.conf if present.
CFG_LOG_RETENTION_DAYS=30
CFG_MAX_LOG_SIZE_MB=50
CFG_MAX_LOGS_PER_DAY=15
CFG_COMPRESS_OLD_LOGS=true
CFG_LOG_LEVEL="INFO"      # DEBUG, INFO, WARNING, ERROR

CFG_AUTO_CONFIRM=false
CFG_RETRY_FAILED=true
CFG_RETRY_ATTEMPTS=3

CFG_DNS_CHECK_ENABLED=true
CFG_DNS_TIMEOUT_SECONDS=10
CFG_DNS_CHECK_HOST="1.1.1.1"  # Host used for connectivity check; override for corporate/restricted networks
CFG_DISK_MIN_MB=1024       # Minimum free disk space in MB

CFG_UPDATE_CHANNEL="main"  # main | dev | a release tag (e.g. v1.3.1) to pin

CFG_AUTO_CLEANUP=true

# --- Verbose / Debug Mode ---
VERBOSE=false
DEBUG=false

verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        printf '%s[VERBOSE]%s %s\n' "${CYAN:-}" "${RESET:-}" "$*"
    fi
}

debug() {
    if [[ "$DEBUG" == "true" ]]; then
        printf '%s[DEBUG]%s %s\n' "${MAGENTA:-}" "${RESET:-}" "$*" >&2
    fi
}

# --- Validation Helpers ---
# Verify that a config value is a positive integer. Returns 0 if valid, 1 if not.
# On failure, prints a warning and leaves the variable at its previous (default) value.
_cfg_require_int() {
    local key="$1" value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "[WARN] Invalid value for ${key}: '${value}' (expected a positive integer, keeping default)" >&2
        return 1
    fi
    return 0
}

# Verify that a config value is a boolean (true/false). Returns 0 if valid, 1 if not.
# On failure, prints a warning and leaves the variable at its previous (default) value.
_cfg_require_bool() {
    local key="$1" value="$2"
    if [[ "$value" != "true" && "$value" != "false" ]]; then
        echo "[WARN] Invalid value for ${key}: '${value}' (expected 'true' or 'false', keeping default)" >&2
        return 1
    fi
    return 0
}

# Verify that update_channel is a branch name we track or a release tag to pin
# to. Tags are validated by shape only (v1.2.3), not by existence -- the tag may
# legitimately not be fetched yet, and self_update reports that at update time.
_cfg_require_channel() {
    local key="$1" value="$2"
    if [[ "$value" == "main" || "$value" == "dev" ]]; then
        return 0
    fi
    if [[ "$value" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    echo "[WARN] Invalid value for ${key}: '${value}' (expected 'main', 'dev', or a release tag like v1.3.1, keeping default)" >&2
    return 1
}

# --- Configuration File Parser ---
# Reads key=value pairs from a config file, ignoring comments and blank lines.
# Only sets variables that match known CFG_* keys (whitelist approach).
load_config() {
    local config_file="${1:-${SCRIPT_DIR}/linux_util.conf}"

    if [[ ! -f "$config_file" ]]; then
        local example_file="${config_file}.example"
        if [[ -f "$example_file" ]]; then
            cp "$example_file" "$config_file"
            echo "[INFO] Created default configuration: ${config_file}"
            echo "[INFO] Edit it to customize behaviour, or re-run to use defaults."
        else
            debug "No config file found at ${config_file}, using defaults."
            return 0
        fi
    fi

    debug "Loading configuration from ${config_file}"

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Skip INI section headers like [Logging]
        [[ "$line" =~ ^[[:space:]]*\[.*\] ]] && continue

        # Strip a trailing carriage return so CRLF config files (e.g. edited
        # on Windows) parse correctly. $'\r' is bash ANSI-C quoting.
        line="${line%$'\r'}"

        # Extract key=value
        key="${line%%=*}"
        value="${line#*=}"

        # Trim whitespace (spaces and tabs)
        key="${key//[[:space:]]/}"
        value="${value#"${value%%[! 	]*}"}"   # ltrim (space + tab in bracket)
        value="${value%"${value##*[! 	]}"}"   # rtrim (space + tab in bracket)

        # Map config keys to CFG_ variables (whitelist)
        case "$key" in
            log_retention_days)     _cfg_require_int "$key" "$value" && CFG_LOG_RETENTION_DAYS="$value" ;;
            max_log_size_mb)        _cfg_require_int "$key" "$value" && CFG_MAX_LOG_SIZE_MB="$value" ;;
            max_logs_per_day)       _cfg_require_int "$key" "$value" && CFG_MAX_LOGS_PER_DAY="$value" ;;
            compress_old_logs)      _cfg_require_bool "$key" "$value" && CFG_COMPRESS_OLD_LOGS="$value" ;;
            log_level)              CFG_LOG_LEVEL="$value" ;;
            auto_confirm)           _cfg_require_bool "$key" "$value" && CFG_AUTO_CONFIRM="$value" ;;
            retry_failed)           _cfg_require_bool "$key" "$value" && CFG_RETRY_FAILED="$value" ;;
            retry_attempts)         _cfg_require_int "$key" "$value" && CFG_RETRY_ATTEMPTS="$value" ;;
            dns_check_enabled)      _cfg_require_bool "$key" "$value" && CFG_DNS_CHECK_ENABLED="$value" ;;
            dns_timeout_seconds)    _cfg_require_int "$key" "$value" && CFG_DNS_TIMEOUT_SECONDS="$value" ;;
            dns_check_host)         CFG_DNS_CHECK_HOST="$value" ;;
            disk_min_mb)            _cfg_require_int "$key" "$value" && CFG_DISK_MIN_MB="$value" ;;
            update_channel)         _cfg_require_channel "$key" "$value" && CFG_UPDATE_CHANNEL="$value" ;;
            auto_cleanup)           _cfg_require_bool "$key" "$value" && CFG_AUTO_CLEANUP="$value" ;;
            verbose)                _cfg_require_bool "$key" "$value" && VERBOSE="$value" ;;
            debug)                  _cfg_require_bool "$key" "$value" && DEBUG="$value" ;;
            *)
                debug "Unknown config key: ${key}"
                ;;
        esac
    done < "$config_file"

    verbose "Configuration loaded from ${config_file}"
    return 0
}
