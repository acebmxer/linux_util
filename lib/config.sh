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

# Where the config lives, overridable so a caller can point the loader and the
# migration at a file of its own. This exists because the repository IS a
# working install: linux_util.conf sits in the checkout, so a test suite that
# runs the real script from the repo root migrates the developer's own config
# and leaves backup files in their working tree. Tests set this to a temp copy.
: "${LINUX_UTIL_CONFIG_FILE:=}"

# The config path a caller gets when it does not name one.
_cfg_default_file() {
    if [[ -n "${LINUX_UTIL_CONFIG_FILE:-}" ]]; then
        echo "$LINUX_UTIL_CONFIG_FILE"
    else
        echo "${SCRIPT_DIR}/linux_util.conf"
    fi
}

# Set by migrate_config so the caller can tell the user what changed. ADDED is
# filled with "key=value" strings for the keys this run appended; UPDATED with
# the names of existing keys whose comment text was refreshed from the example.
CONFIG_MIGRATION_ADDED=()
CONFIG_MIGRATION_UPDATED=()
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
    local config_file="${1:-$(_cfg_default_file)}"

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
# block above it so it arrives documented.
#
# It also refreshes documentation. A key that already exists keeps the value the
# user set, but if the example has since reworded the comment above it, that new
# text replaces the old. Otherwise a config written a few releases ago keeps
# describing behaviour the program no longer has -- which is worse than a
# missing comment, because the user has no reason to doubt it.
#
# Values, key ordering, and keys not present in the example are never touched.
#
# THIS EDITS A FILE THE USER MAINTAINS. It reports every key it added and every
# comment it rewrote, and it keeps a timestamped backup beside the config
# first.

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
        # A "# --- Section ---" banner heads a group of keys, it does not
        # document the one that happens to follow it. Treating it as part of
        # the block would copy the banner along with the key and leave the
        # config with a second "# --- Installation ---" halfway down. Start the
        # block after it instead.
        /^[[:space:]]*#[[:space:]]*---.*---[[:space:]]*$/ { block = ""; next }
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

# The comment block a key carries in the user's own config file. Same shape as
# _cfg_example_comment_for, deliberately a separate call rather than a second
# implementation: both go through the same awk so the two blocks are extracted
# by identical rules and can be compared directly. Do not add a third.
_cfg_config_comment_for() {
    _cfg_example_comment_for "$@"
}

# Replace the comment block above a key in the config file with the example's
# current block, leaving the key's own line -- and therefore the user's value --
# untouched. Used when documentation for an existing setting has been reworded
# in the example: without this, a config written before the rewording keeps
# describing behaviour the program no longer has.
#
# The whole preceding comment block is replaced, so a comment the user wrote
# directly above a documented key is lost. That is the trade: a per-line merge
# cannot tell an edited stock comment from a hand-written one, and leaving both
# in place is how a config ends up documenting the same key two contradictory
# ways. The timestamped backup taken before any migration write is the recovery
# path, and the notice names every key whose text was replaced.
_cfg_replace_comment_for() {
    local file="$1" key="$2" new_block="$3"

    # A block that does not end in a newline would be printed straight onto the
    # key's own line, commenting the setting out. Normalise before writing.
    [[ -z "$new_block" || "$new_block" == *$'\n' ]] || new_block+=$'\n'

    local tmp block_file
    tmp="$(mktemp "${file}.migrate.XXXXXX")" || return 1
    block_file="$(mktemp "${file}.block.XXXXXX")" || { rm -f "$tmp"; return 1; }
    printf '%s' "$new_block" > "$block_file" || {
        rm -f "$tmp" "$block_file"; return 1
    }

    # The replacement text is handed over in a file rather than through awk -v:
    # -v applies escape-sequence processing to its value, so a backslash in a
    # comment would be silently rewritten on its way into the config.
    awk -v want="$key" -v blockfile="$block_file" '
        function flush_block() { printf "%s", block; block = "" }
        function emit_new(  line) {
            while ((getline line < blockfile) > 0) print line
            close(blockfile)
        }
        # Section banners are not part of any key block -- see
        # _cfg_example_comment_for. Print them straight through so replacing a
        # key comment never swallows the heading above it.
        /^[[:space:]]*#[[:space:]]*---.*---[[:space:]]*$/ {
            flush_block(); print; next
        }
        /^[[:space:]]*#/ { block = block $0 "\n"; next }
        /^[[:space:]]*$/ { flush_block(); print; next }
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            split(line, parts, "=")
            gsub(/[[:space:]]/, "", parts[1])
            if (parts[1] == want && !done) {
                emit_new()
                block = ""
                done = 1
                print
                next
            }
            flush_block()
            print
            next
        }
        END { flush_block() }
    ' "$file" > "$tmp" 2>/dev/null || {
        rm -f "$tmp" "$block_file"; return 1
    }
    rm -f "$block_file"

    # Never install an empty or truncated result over a file the user maintains.
    [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
    _cfg_has_key "$key" "$tmp" || { rm -f "$tmp"; return 1; }

    cat "$tmp" > "$file" 2>/dev/null || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    return 0
}

# Top up the user's config with keys added to the example since it was written.
# Returns 0 whether or not anything changed; a failure to write is a warning,
# not a fatal error, since the run can proceed on defaults.
migrate_config() {
    local config_file="${1:-$(_cfg_default_file)}"
    local example_file="${config_file}.example"

    CONFIG_MIGRATION_ADDED=()
    CONFIG_MIGRATION_UPDATED=()
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
    # Two passes over the same key list: keys absent from the config are
    # appended, keys present but carrying outdated documentation have their
    # comment block refreshed. config_version is excluded from both -- it is
    # stamped by _cfg_stamp_version, which owns both its value and its comment.
    local key missing=() restale=()
    local example_comment config_comment
    while IFS= read -r key; do
        [[ "$key" == "config_version" ]] && continue
        if ! _cfg_has_key "$key" "$config_file"; then
            missing+=("$key")
            continue
        fi
        example_comment="$(_cfg_example_comment_for "$example_file" "$key")"
        config_comment="$(_cfg_config_comment_for "$config_file" "$key")"
        # An example that documents a key the config leaves bare still counts as
        # stale: the user is missing text, not merely holding an older version
        # of it. The reverse -- the example dropping a comment the config has --
        # deliberately does not, so a hand-written note is never silently
        # deleted just because the example says nothing about that key.
        if [[ -n "$example_comment" && "$example_comment" != "$config_comment" ]]; then
            restale+=("$key")
        fi
    done < <(_cfg_example_keys "$example_file")

    # The stamp's own comment can go stale without the version number moving --
    # a reworded explanation on an unchanged schema. Check it directly rather
    # than letting a version bump be the only thing that refreshes it.
    local stamp_stale=false
    example_comment="$(_cfg_example_comment_for "$example_file" config_version)"
    config_comment="$(_cfg_config_comment_for "$config_file" config_version)"
    if [[ -n "$example_comment" && "$example_comment" != "$config_comment" ]] \
        && _cfg_has_key config_version "$config_file"; then
        stamp_stale=true
    fi

    # Nothing missing and nothing stale: stamp the version if it is behind, but
    # write nothing else and leave no backup -- the common case is a config that
    # is already current.
    if [[ ${#missing[@]} -eq 0 && ${#restale[@]} -eq 0 && "$stamp_stale" == false ]]; then
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

    # Refresh outdated comments first, in place, so the appended block below
    # lands at the end of a file whose existing text is already current.
    local comment default_line
    for key in "${restale[@]}"; do
        comment="$(_cfg_example_comment_for "$example_file" "$key")"
        if _cfg_replace_comment_for "$config_file" "$key" "$comment"; then
            CONFIG_MIGRATION_UPDATED+=("$key")
        else
            echo "[WARN] Could not refresh the comment for '${key}' in ${config_file}." >&2
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        {
            echo ""
            echo "# --- Added by linux_util config migration on $(date '+%Y-%m-%d %H:%M') ---"
            echo "# These settings were added to linux_util.conf.example after this file"
            echo "# was created. The values below are the defaults; edit them as needed."
        } >> "$config_file" 2>/dev/null || {
            echo "[WARN] Could not write to ${config_file}; leaving it unchanged." >&2
            return 0
        }

        for key in "${missing[@]}"; do
            comment="$(_cfg_example_comment_for "$example_file" "$key")"
            default_line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$example_file" | head -1)"
            {
                echo ""
                # printf %s, not echo: the block already ends in a newline, and a
                # second one would separate the comment from its key. But a block
                # that somehow lacks one would glue the comment and key together
                # and comment the key out, so normalise it.
                if [[ -n "$comment" ]]; then
                    printf '%s' "$comment"
                    [[ "$comment" == *$'\n' ]] || echo ""
                fi
                echo "$default_line"
            } >> "$config_file"
            CONFIG_MIGRATION_ADDED+=("$default_line")
        done
    fi

    _cfg_stamp_version "$config_file" "$latest_ver"
    [[ "$stamp_stale" == true ]] && CONFIG_MIGRATION_UPDATED+=("config_version")
    CONFIG_MIGRATION_FROM="$current_ver"
    CFG_CONFIG_VERSION="$latest_ver"

    # Re-read so the new keys take effect on this run rather than the next one.
    load_config "$config_file"
    return 0
}

# Record the schema version in the config file, replacing any existing stamp.
#
# The comment above the stamp comes from the example file rather than being
# written out here, so there is one authority on how this key is documented.
# config_version is excluded from the ordinary comment-refresh pass precisely
# because this function owns it; hardcoding different text here is how the
# config ended up describing the key one way and the example another.
_cfg_stamp_version() {
    local config_file="$1" version="${2:-$LATEST_CONFIG_VERSION}"
    local example_file="${config_file}.example"
    local comment=""
    [[ -f "$example_file" ]] && \
        comment="$(_cfg_example_comment_for "$example_file" config_version)"
    [[ -n "$comment" ]] || comment="# Config schema version - written by linux_util, do not edit"$'\n'

    if grep -qE '^[[:space:]]*config_version[[:space:]]*=' "$config_file" 2>/dev/null; then
        sed -i "s/^[[:space:]]*config_version[[:space:]]*=.*/config_version=${version}/" \
            "$config_file" 2>/dev/null || return 1
        # Bring the stamp's own comment up to date too. A failure here leaves the
        # value correctly stamped with older wording above it, which is worth a
        # warning but not worth failing the migration over.
        _cfg_replace_comment_for "$config_file" config_version "$comment" || return 0
    else
        {
            echo ""
            printf '%s' "$comment"
            [[ "$comment" == *$'\n' ]] || echo ""
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
    [[ ${#CONFIG_MIGRATION_ADDED[@]} -gt 0 || ${#CONFIG_MIGRATION_UPDATED[@]} -gt 0 ]] \
        || return 0

    echo ""
    echo "${YELLOW:-}┌─ Configuration updated ─────────────────────────────────────┐${RESET:-}"
    echo ""
    local entry
    if [[ ${#CONFIG_MIGRATION_ADDED[@]} -gt 0 ]]; then
        echo "  Your linux_util.conf was missing settings added in newer"
        echo "  releases. They have been appended with their default values:"
        echo ""
        for entry in "${CONFIG_MIGRATION_ADDED[@]}"; do
            echo "    ${GREEN:-}+${RESET:-} ${entry}"
        done
        echo ""
    fi
    if [[ ${#CONFIG_MIGRATION_UPDATED[@]} -gt 0 ]]; then
        echo "  These settings had comments describing older behaviour. The"
        echo "  explanatory text above them was replaced; the values you set"
        echo "  were not touched:"
        echo ""
        for entry in "${CONFIG_MIGRATION_UPDATED[@]}"; do
            echo "    ${GREEN:-}~${RESET:-} ${entry}"
        done
        echo ""
    fi
    echo "  No setting values were changed. A backup of the previous"
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
