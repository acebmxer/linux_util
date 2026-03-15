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
    DEPS_MAP["Visual Studio Code"]="curl:curl gpg:gnupg wget:wget"
    DEPS_MAP["Syncthing"]="curl:curl"
    DEPS_MAP["PIA VPN"]="curl:curl wget:wget"
    DEPS_MAP["Bitwarden Client"]="wget:wget"
    DEPS_MAP["Devolutions RDM"]="curl:curl gpg:gnupg"
    DEPS_MAP["Steam App"]="wget:wget"
    DEPS_MAP["LibreOffice"]="wget:wget"
    DEPS_MAP["Termius SSH Client"]="wget:wget"
    DEPS_MAP["NVIDIA Drivers"]="curl:curl gpg:gnupg"
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
    HEALTH_CHECK_CMDS["Docker"]="docker --version"
    HEALTH_CHECK_CMDS["Brave Browser"]="brave-browser --version"
    HEALTH_CHECK_CMDS["Visual Studio Code"]="code --version"
    HEALTH_CHECK_CMDS["Syncthing"]="syncthing --version"
    HEALTH_CHECK_CMDS["PIA VPN"]="piactl --version"
    HEALTH_CHECK_CMDS["Bitwarden Client"]="command -v bitwarden"
    HEALTH_CHECK_CMDS["QBittorrent"]="command -v qbittorrent"
    HEALTH_CHECK_CMDS["OpenSSH Server"]="systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null"
    HEALTH_CHECK_CMDS["Timeshift"]="timeshift --version"
    HEALTH_CHECK_CMDS["LibreOffice"]="libreoffice --version"
    HEALTH_CHECK_CMDS["Termius SSH Client"]="command -v termius || command -v termius-app"
    HEALTH_CHECK_CMDS["NVIDIA Drivers"]="nvidia-smi"
    HEALTH_CHECK_CMDS["KDE Desktop"]="command -v plasmashell"
    HEALTH_CHECK_CMDS["XEN Guest Utilities"]="command -v xe-daemon || systemctl is-active xe-linux-distribution 2>/dev/null"
}

# Run a health check for a utility after install/update.
# Usage: health_check "Utility Name"
# Returns 0 on pass, 1 on fail. Logs result.
health_check() {
    local util_name="$1"
    local check_cmd="${HEALTH_CHECK_CMDS[$util_name]:-}"

    if [[ -z "$check_cmd" ]]; then
        # No health check registered; use the utility's own check function
        local check_func="${CHECK_FUNCS[$util_name]:-}"
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

    if eval "$check_cmd" &>/dev/null; then
        verbose "Health check passed for ${util_name}"
        log_success "Health check passed: ${util_name}"
        return 0
    else
        warn "Health check failed for ${util_name}"
        log_warning "Health check failed: ${util_name}"
        return 1
    fi
}
