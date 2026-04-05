#!/bin/bash

# ============================================================================
# Linux Utilities - Utilities Registry Module
# Provides utility registration and resolution functions
# ============================================================================

# Utility registry (initialized in main script)
declare -a UTILITIES
declare -a SYSTEM_TASKS
declare -A INSTALL_FUNCS
declare -A CHECK_FUNCS
declare -A UNINSTALL_FUNCS
declare -A UPDATE_FUNCS
declare -A VERSION_FUNCS
declare -A NO_RETRY
declare -A UTILITY_CATEGORY     # maps utility name → category tab label
declare -A UTILITY_SUBCATEGORY  # maps utility name → subcategory name (optional)
declare -A UTILITY_DESCRIPTION  # maps utility name → short description for the info panel
declare -a CATEGORIES=()        # ordered list of category tab names (populated by installers.sh)

# Internal helper — shared registration logic for both system tasks and utilities.
_register_entry() {
    local name="$1" install_fn="$2" check_fn="$3" uninstall_fn="$4" update_fn="$5"
    local version_fn="${6:-}"
    UTILITIES+=("$name")
    INSTALL_FUNCS["$name"]="$install_fn"
    CHECK_FUNCS["$name"]="$check_fn"
    UNINSTALL_FUNCS["$name"]="$uninstall_fn"
    UPDATE_FUNCS["$name"]="$update_fn"
    [[ -n "$version_fn" ]] && VERSION_FUNCS["$name"]="$version_fn" || true
}

# Register a system task (appears in the System Tasks section of the menu).
# Must be called BEFORE any register_utility calls.
# Usage: register_system_task "Name" install_fn check_fn uninstall_fn update_fn [version_fn]
register_system_task() {
    SYSTEM_TASKS+=("$1")
    _register_entry "$@"
}

# Register a utility (appears in the Utilities section of the menu).
# Usage: register_utility "Name" install_fn check_fn uninstall_fn update_fn [version_fn]
register_utility() {
    _register_entry "$@"
}

# Resolve a utility name (case-insensitive, partial match support).
# Prints the canonical name to stdout if found and returns 0; otherwise prints
# an error to stderr and returns 1.
resolve_utility_name() {
    local input="$1"
    local input_lower="${input,,}"

    # First try exact match (case-insensitive)
    for util in "${UTILITIES[@]}"; do
        if [[ "${util,,}" == "$input_lower" ]]; then
            echo "$util"
            return 0
        fi
    done

    # Then try partial match — collect all matches to detect ambiguity
    local -a matches=()
    for util in "${UTILITIES[@]}"; do
        if [[ "${util,,}" == *"$input_lower"* ]]; then
            matches+=("$util")
        fi
    done

    if [[ ${#matches[@]} -eq 1 ]]; then
        echo "${matches[0]}"
        return 0
    elif [[ ${#matches[@]} -gt 1 ]]; then
        echo "Error: Ambiguous utility name '$input'. Matches:" >&2
        for m in "${matches[@]}"; do
            echo "  - $m" >&2
        done
        return 1
    fi

    echo "Error: Utility '$input' not found." >&2
    return 1
}

# Check which utilities are already installed (populates INSTALLED[] and INSTALLED_VERSIONS[])
check_installed_utilities() {
    echo "Checking installed utilities..."
    local total=${#UTILITIES[@]}
    for ((i=0; i<total; i++)); do
        local util="${UTILITIES[$i]}"
        local check_func="${CHECK_FUNCS[$util]:-}"

        if [[ -n "$check_func" ]] && declare -f "$check_func" &>/dev/null; then
            if $check_func 2>/dev/null; then
                INSTALLED[$i]=1
                # Retrieve version if a version function is registered
                local ver_func="${VERSION_FUNCS[$util]:-}"
                if [[ -n "$ver_func" ]] && declare -f "$ver_func" > /dev/null; then
                    INSTALLED_VERSIONS[$i]=$($ver_func 2>/dev/null)
                else
                    INSTALLED_VERSIONS[$i]=""
                fi
            else
                INSTALLED[$i]=0
                INSTALLED_VERSIONS[$i]=""
            fi
        else
            INSTALLED[$i]=0
            INSTALLED_VERSIONS[$i]=""
        fi

        # Keep all options unselected by default; selection determines action
        SELECTED[$i]=0
    done
}

# ============================================================================
# Dependency Resolution
# Maps utilities to required system commands/packages and installs missing ones.
# ============================================================================
declare -A DEPS_MAP

# Register dependencies for utilities that need specific tools pre-installed.
# Format: DEPS_MAP["Utility Name"]="cmd1:pkg1 cmd2:pkg2"
#   cmd = command to check (via command -v)
#   pkg = package to install if cmd is missing
_init_deps_map() {
    DEPS_MAP["Docker"]="curl:curl ca-certificates:ca-certificates"
    DEPS_MAP["Brave Browser"]="curl:curl gpg:gnupg"
    DEPS_MAP["Firefox"]="curl:curl gpg:gnupg"
    DEPS_MAP["Visual Studio Code"]="curl:curl gpg:gnupg wget:wget"
    DEPS_MAP["Syncthing"]="curl:curl"
    DEPS_MAP["PIA VPN"]="curl:curl wget:wget"
    DEPS_MAP["Bitwarden Client"]="wget:wget"
    DEPS_MAP["Devolutions RDM"]="curl:curl gpg:gnupg"
    DEPS_MAP["Steam App"]="wget:wget"
    DEPS_MAP["LibreOffice"]="wget:wget"
    DEPS_MAP["Termius SSH Client"]="wget:wget"
    DEPS_MAP["NVIDIA Drivers"]="curl:curl gpg:gnupg"
    DEPS_MAP["Timeshift"]="rsync:rsync"
    DEPS_MAP["Restore Snapshot"]="rsync:rsync"
}

# Check and install missing dependencies for a utility.
# Usage: resolve_dependencies "Utility Name"
resolve_dependencies() {
    local util_name="$1"
    local deps="${DEPS_MAP[$util_name]:-}"

    [[ -z "$deps" ]] && return 0

    local missing=()
    for dep_entry in $deps; do
        local cmd="${dep_entry%%:*}"
        local pkg="${dep_entry##*:}"
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$pkg")
            verbose "Dependency missing for ${util_name}: ${cmd} (package: ${pkg})"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        # Deduplicate
        local -A seen
        local -a unique_pkgs=()
        for pkg in "${missing[@]}"; do
            if [[ -z "${seen[$pkg]:-}" ]]; then
                seen["$pkg"]=1
                unique_pkgs+=("$pkg")
            fi
        done

        info "Installing dependencies for ${util_name}: ${unique_pkgs[*]}"
        log_info "Installing dependencies for ${util_name}: ${unique_pkgs[*]}"
        pkg_install "${unique_pkgs[@]}" || {
            warn "Failed to install some dependencies for ${util_name}"
            return 1
        }
    fi

    return 0
}

# ============================================================================
# Health Checks — Post-Installation Verification
# Verifies that a utility was installed correctly and is functional.
# ============================================================================
declare -A HEALTH_CHECK_CMDS

# Register health check commands for utilities.
# Format: HEALTH_CHECK_CMDS["Utility Name"]="command_to_verify"
_init_health_checks() {
    # All utilities fall through to their check_*() functions, which are
    # more robust (cover multiple package names, install methods, and paths).
    # Only register an explicit command here when a utility has no check_*()
    # function or the check function is insufficient.
    :
}

# Run a health check for a utility after install/update.
# Usage: health_check "Utility Name"
# Returns 0 on pass, 1 on fail. Logs result.
health_check() {
    local util_name="$1"
    local check_cmd="${HEALTH_CHECK_CMDS[$util_name]:-}"

    # Refresh shell command hash table so newly installed binaries are found
    hash -r 2>/dev/null

    if [[ -z "$check_cmd" ]]; then
        # No health check registered; use the utility's own check function
        local check_func="${CHECK_FUNCS[$util_name]:-}"
        # Skip health check for tasks with no meaningful installed state
        if [[ "$check_func" == "check_always_false" ]]; then
            verbose "Skipping health check for ${util_name} (always-run task)"
            return 0
        fi
        if [[ -n "$check_func" ]] && declare -f "$check_func" &>/dev/null; then
            if $check_func 2>/dev/null; then
                verbose "Health check passed for ${util_name} (via check function)"
                log_success "Health check passed: ${util_name}"
                return 0
            else
                warn "Health check failed for ${util_name}"
                log_warning "Health check failed: ${util_name}"
                return 1
            fi
        fi
        verbose "No health check available for ${util_name}"
        return 0
    fi

    if bash -c "$check_cmd" &>/dev/null; then
        verbose "Health check passed for ${util_name}"
        log_success "Health check passed: ${util_name}"
        return 0
    else
        warn "Health check failed for ${util_name}"
        log_warning "Health check failed: ${util_name}"
        return 1
    fi
}
