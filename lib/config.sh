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

# --- Config schema migration ---
# The user's linux_util.conf is topped up with keys added to
# linux_util.conf.example, so a hand-maintained config does not silently miss
# settings introduced after it was written.
#
# LATEST_CONFIG_VERSION is a fallback only. The real value is read from the
# example file at migration time, so the file that defines the keys also
# defines the version and the two cannot drift apart. Nothing here gates
# whether the migration scans -- see migrate_config.
LATEST_CONFIG_VERSION=1
CFG_CONFIG_VERSION=0

# Set by migrate_config so the caller can tell the user what changed. Filled
# with "key=value" strings for the keys this run appended.
CONFIG_MIGRATION_ADDED=()
CONFIG_MIGRATION_FROM=""

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
            config_version)         _cfg_require_int "$key" "$value" && CFG_CONFIG_VERSION="$value" ;;
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

# ============================================================================
# Config schema migration
# ============================================================================
#
# A user's linux_util.conf is written once (copied from the example) and then
# maintained by hand. Keys added to the example afterwards never reach it, so a
# config written a few releases ago silently misses newer settings and the user
# gets defaults they never chose and cannot see.
#
# migrate_config tops that file up: any key present in linux_util.conf.example
# but absent from linux_util.conf is appended, with the example's own comment
# block above it so it arrives documented. Existing keys are never touched --
# values the user set, their ordering, and their own comments are left exactly
# as they are. Nothing is ever removed or rewritten in place.
#
# THIS EDITS A FILE THE USER MAINTAINS. It appends only, it reports every key it
# added, and it keeps a timestamped backup beside the config first.

# Names of keys the example file defines, in the order it defines them.
_cfg_example_keys() {
    local file="$1" line key
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*\[.*\] ]] && continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        key="${key//[[:space:]]/}"
        [[ -n "$key" ]] && echo "$key"
    done < "$file"
}

# True when the config file already defines this key (commented-out lines do
# not count -- the parser ignores them, so the setting is not actually present).
_cfg_has_key() {
    grep -qE "^[[:space:]]*$1[[:space:]]*=" "$2" 2>/dev/null
}

# Print the comment block immediately preceding a key in the example file, so
# an appended key arrives with the documentation the example gives it.
_cfg_example_comment_for() {
    local file="$1" key="$2"
    awk -v want="$key" '
        /^[[:space:]]*#/ { block = block $0 "\n"; next }
        /^[[:space:]]*$/ { block = ""; next }
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            split(line, parts, "=")
            gsub(/[[:space:]]/, "", parts[1])
            if (parts[1] == want) { printf "%s", block; exit }
            block = ""
        }
    ' "$file"
}

# Top up the user's config with keys added to the example since it was written.
# Returns 0 whether or not anything changed; a failure to write is a warning,
# not a fatal error, since the run can proceed on defaults.
migrate_config() {
    local config_file="${1:-${SCRIPT_DIR}/linux_util.conf}"
    local example_file="${config_file}.example"

    CONFIG_MIGRATION_ADDED=()
    CONFIG_MIGRATION_FROM=""

    [[ -f "$config_file" && -f "$example_file" ]] || return 0

    local current_ver="${CFG_CONFIG_VERSION:-0}"

    # The example ships its own config_version, so the version travels with the
    # keys it describes rather than living in a constant somebody has to
    # remember to bump alongside it.
    local latest_ver
    latest_ver=$(grep -E '^[[:space:]]*config_version[[:space:]]*=' "$example_file" 2>/dev/null \
        | head -1 | cut -d= -f2 | tr -d '[:space:]')
    [[ "$latest_ver" =~ ^[0-9]+$ ]] || latest_ver="$LATEST_CONFIG_VERSION"

    # The example file is the authority on which keys exist, so the scan below
    # always runs and compares against it directly. There is deliberately no
    # "already at the latest version, skip" shortcut: that would make correctness
    # depend on remembering to bump a hand-maintained constant every time a key
    # is added to the example. Forgetting it would leave every existing config
    # stamped current, skipping the scan forever, and quietly never receiving the
    # new key -- while fresh installs got it, so the bug would be invisible to
    # whoever shipped it. The scan is a grep per key over two small files, run
    # once at startup; the version stamp records what happened, and never gates
    # whether it happens.
    local key missing=()
    while IFS= read -r key; do
        [[ "$key" == "config_version" ]] && continue
        _cfg_has_key "$key" "$config_file" || missing+=("$key")
    done < <(_cfg_example_keys "$example_file")

    # Nothing missing: stamp the version if it is behind, but write nothing else
    # and leave no backup -- the common case is a config that is already current.
    if [[ ${#missing[@]} -eq 0 ]]; then
        if [[ "$current_ver" -lt "$latest_ver" ]]; then
            _cfg_stamp_version "$config_file" "$latest_ver" || return 0
            CFG_CONFIG_VERSION="$latest_ver"
        fi
        return 0
    fi

    # Back up before touching a file the user maintains.
    local backup="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    if ! cp "$config_file" "$backup" 2>/dev/null; then
        echo "[WARN] Could not back up ${config_file}; leaving it unchanged." >&2
        return 0
    fi

    {
        echo ""
        echo "# --- Added by linux_util config migration on $(date '+%Y-%m-%d %H:%M') ---"
        echo "# These settings were added to linux_util.conf.example after this file"
        echo "# was created. The values below are the defaults; edit them as needed."
    } >> "$config_file" 2>/dev/null || {
        echo "[WARN] Could not write to ${config_file}; leaving it unchanged." >&2
        return 0
    }

    local comment default_line
    for key in "${missing[@]}"; do
        comment="$(_cfg_example_comment_for "$example_file" "$key")"
        default_line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$example_file" | head -1)"
        {
            echo ""
            # printf %s, not echo: the block already ends in a newline, and a
            # second one would separate the comment from its key. But a block
            # that somehow lacks one would glue the comment and key together and
            # comment the key out, so normalise it.
            if [[ -n "$comment" ]]; then
                printf '%s' "$comment"
                [[ "$comment" == *$'\n' ]] || echo ""
            fi
            echo "$default_line"
        } >> "$config_file"
        CONFIG_MIGRATION_ADDED+=("$default_line")
    done

    _cfg_stamp_version "$config_file" "$latest_ver"
    CONFIG_MIGRATION_FROM="$current_ver"
    CFG_CONFIG_VERSION="$latest_ver"

    # Re-read so the new keys take effect on this run rather than the next one.
    load_config "$config_file"
    return 0
}

# Record the schema version in the config file, replacing any existing stamp.
_cfg_stamp_version() {
    local config_file="$1" version="${2:-$LATEST_CONFIG_VERSION}"
    if grep -qE '^[[:space:]]*config_version[[:space:]]*=' "$config_file" 2>/dev/null; then
        sed -i "s/^[[:space:]]*config_version[[:space:]]*=.*/config_version=${version}/" \
            "$config_file" 2>/dev/null || return 1
    else
        {
            echo ""
            echo "# Config schema version - written by linux_util, do not edit"
            echo "config_version=${version}"
        } >> "$config_file" 2>/dev/null || return 1
    fi
    return 0
}

# Tell the user their config was changed, and what was added, before the menu
# takes over the screen. Silent when nothing was migrated.
#
# This is shown rather than logged because the file it edited is one the user
# maintains by hand: finding new lines later with no idea where they came from
# is exactly the surprise this notice exists to prevent.
show_config_migration_notice() {
    [[ ${#CONFIG_MIGRATION_ADDED[@]} -gt 0 ]] || return 0

    echo ""
    echo "${YELLOW:-}┌─ Configuration updated ─────────────────────────────────────┐${RESET:-}"
    echo ""
    echo "  Your linux_util.conf was missing settings added in newer"
    echo "  releases. They have been appended with their default values:"
    echo ""
    local entry
    for entry in "${CONFIG_MIGRATION_ADDED[@]}"; do
        echo "    ${GREEN:-}+${RESET:-} ${entry}"
    done
    echo ""
    echo "  Existing settings were not changed. A backup of the previous"
    echo "  file is saved beside it as linux_util.conf.bak.<timestamp>."
    echo ""
    echo "  Review the new settings before continuing if you want to"
    echo "  change any of them from their defaults."
    echo ""
    echo "${YELLOW:-}└─────────────────────────────────────────────────────────────┘${RESET:-}"
    echo ""

    # An unattended run has nobody to read this, so it must not block there.
    if [[ -t 0 ]] && { : < /dev/tty; } 2>/dev/null; then
        read -rp "Press ENTER to continue..." < /dev/tty
    fi
}
