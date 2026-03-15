#!/bin/bash

# ============================================================================
# Linux Utilities - Utilities Registry Module
# Provides utility registration and resolution functions
# ============================================================================

# Utility registry (initialized in main script)
declare -a UTILITIES
declare -A INSTALL_FUNCS
declare -A CHECK_FUNCS
declare -A UNINSTALL_FUNCS
declare -A UPDATE_FUNCS
declare -A VERSION_FUNCS

# Registration helper — reduces boilerplate when adding new utilities.
# Usage: register_utility "Name" install_fn check_fn uninstall_fn update_fn [version_fn]
register_utility() {
    local name="$1" install_fn="$2" check_fn="$3" uninstall_fn="$4" update_fn="$5"
    local version_fn="${6:-}"
    UTILITIES+=("$name")
    INSTALL_FUNCS["$name"]="$install_fn"
    CHECK_FUNCS["$name"]="$check_fn"
    UNINSTALL_FUNCS["$name"]="$uninstall_fn"
    UPDATE_FUNCS["$name"]="$update_fn"
    [[ -n "$version_fn" ]] && VERSION_FUNCS["$name"]="$version_fn" || true
}

# Resolve a utility name (case-insensitive, partial match support).
# Sets _RESOLVED to the canonical name if found, returns 0; otherwise returns 1.
resolve_utility_name() {
    local input="$1"
    local input_lower=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    # First try exact match (case-insensitive)
    for util in "${UTILITIES[@]}"; do
        if [[ "$(echo "$util" | tr '[:upper:]' '[:lower:]')" == "$input_lower" ]]; then
            _RESOLVED="$util"
            return 0
        fi
    done

    # Then try partial match
    for util in "${UTILITIES[@]}"; do
        if [[ "$(echo "$util" | tr '[:upper:]' '[:lower:]')" == *"$input_lower"* ]]; then
            _RESOLVED="$util"
            return 0
        fi
    done

    echo "Error: Utility '$input' not found."
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
