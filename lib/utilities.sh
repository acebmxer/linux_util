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
declare -A UTILITY_DISPLAY_NAME # maps utility name → display label override (optional)
declare -a CATEGORIES=()        # ordered list of category tab names (populated by installers.sh)
declare -A SUBCATEGORY_ORDER    # maps category name → pipe-separated ordered subcategory list
declare -A SUBCATEGORY_INTERLEAVED  # if set for a category, subcategory folders are emitted in registration order (interleaved with plain items)
declare -A UTILITY_AUR_ONLY_ARCH    # utility name → 1 if its only Arch install path is the AUR (no repo/Flatpak fallback)
declare -A UTILITY_ARCH_PKG         # utility name → Arch package name, probed against the configured repos
declare -A UTILITY_UPSTREAM_BINARY   # utility name → path that exists only when installed from upstream's own binary
declare -A UTILITY_FULL_UPGRADE      # utility name → 1 if its own run performs a full system upgrade

# Mark one or more utilities whose only Arch install path is the AUR (no
# official-repo or Flatpak fallback in their installer). Used to hide them
# from the "available to install" listing while AUR_ENABLED=false and they
# are not already installed — see _utility_hidden_aur_only below.
#
# Accepts either a bare name or "Name=pkg". The package form is strongly
# preferred: "AUR-only" holds for upstream Arch, but derivatives like CachyOS
# ship a lot of these in their own repos, and a name registered with its package
# stays visible (and installs with plain pacman) wherever the repo carries it.
mark_aur_only_arch() {
    local entry name
    for entry in "$@"; do
        name="${entry%%=*}"
        UTILITY_AUR_ONLY_ARCH["$name"]=1
        [[ "$entry" == *=* ]] && UTILITY_ARCH_PKG["$name"]="${entry#*=}"
    done
}

# Register a utility that can land outside every package manager, together with
# the path that exists only in that case (a tarball tree, an AppImage, a payload
# unpacked from a .deb). Such a copy is invisible to pacman, apt, Flatpak and to
# Arch's cachy-update/arch-update, so nothing in a normal system update refreshes
# it -- the app's own updater then advertises a version the system update run
# reports as unavailable. setup_system_updates walks this map and calls each
# entry's registered update function; see _system_updates_upstream_binaries.
#
# Usage: mark_upstream_binary "Name=/path/that/only/exists/upstream" ...
mark_upstream_binary() {
    local entry
    for entry in "$@"; do
        [[ "$entry" == *=* ]] || continue
        UTILITY_UPSTREAM_BINARY["${entry%%=*}"]="${entry#*=}"
    done
}

# Mark a utility whose own run performs a complete system upgrade (System
# Updates, and anything else that ends up calling a full -Syu / full-upgrade).
# The pre-flight package refresh consults this: on Arch it has no metadata-only
# sync it can safely do in general, so it runs -Syu -- which for these utilities
# applied the whole update before the selected run even started, leaving that run
# to report "No update available" while 24 packages had just been upgraded a few
# lines above. Marked utilities get a bare -Sy instead, so the upgrade happens
# inside the run the user selected, as it already did on apt and dnf.
mark_full_upgrade() {
    local name
    for name in "$@"; do
        UTILITY_FULL_UPGRADE["$name"]=1
    done
}

# True when the named utility performs its own full system upgrade.
utility_performs_full_upgrade() {
    [[ -n "${UTILITY_FULL_UPGRADE[$1]:-}" ]]
}

# True when the named utility is currently installed from upstream's own binary
# rather than from a package. The marker path is the whole test: every installer
# that can take this route removes the path when a packaged copy replaces it.
utility_is_upstream_binary() {
    local path="${UTILITY_UPSTREAM_BINARY[$1]:-}"
    [[ -n "$path" && -e "$path" ]]
}

# Latest version published upstream for a utility installed from an upstream
# binary, or "" when it cannot be determined (offline, API rate limit, vendor
# change). Each installer registers a function here that performs ONE cheap
# network lookup and prints a bare version string.
declare -A UPSTREAM_LATEST_FUNCS   # utility name → function printing the latest upstream version

# Usage: mark_upstream_latest "Name=fn_name" ...
mark_upstream_latest() {
    local entry
    for entry in "$@"; do
        [[ "$entry" == *=* ]] || continue
        UPSTREAM_LATEST_FUNCS["${entry%%=*}"]="${entry#*=}"
    done
}

# Where cached upstream version lookups live, and how long a cached answer is
# reused. The menu redraws often and these are network calls, so an uncached
# lookup would put a vendor request behind every repaint. Same default age as
# the package-manager metadata cache.
_UPSTREAM_VER_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/linux_util/upstream-versions"

# Print the latest upstream version for $1, or "" if unknown. Cached; set
# UPSTREAM_VER_REFRESH=1 to bypass the cache for one call.
upstream_latest_version() {
    local util="$1"
    local fn="${UPSTREAM_LATEST_FUNCS[$util]:-}"
    [[ -n "$fn" ]] && declare -F "$fn" >/dev/null || return 1

    local cache="${_UPSTREAM_VER_CACHE_DIR}/$(printf '%s' "$util" | tr -c '[:alnum:]' '_')"
    if [[ "${UPSTREAM_VER_REFRESH:-0}" != "1" && -s "$cache" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        if (( age < ${PKG_CACHE_MAX_AGE_SECS:-3600} )); then
            head -1 "$cache"
            return 0
        fi
    fi

    local v
    v=$("$fn" 2>/dev/null | head -1)
    # Only a successful lookup is cached: caching "" would pin the unknown state
    # for the whole cache window and hide a real update after a brief outage.
    if [[ -n "$v" ]]; then
        mkdir -p "$_UPSTREAM_VER_CACHE_DIR" 2>/dev/null && printf '%s\n' "$v" > "$cache" 2>/dev/null
    fi
    printf '%s\n' "$v"
}

# Names of upstream-binary utilities that are installed AND have a newer version
# published, one per line. Used for the pending-update count in the menu and by
# the System Updates run.
upstream_binaries_with_updates() {
    local util
    for util in "${!UTILITY_UPSTREAM_BINARY[@]}"; do
        utility_is_upstream_binary "$util" || continue
        upstream_update_available "$util" && printf '%s\n' "$util"
    done | sort
}

# Print the version currently installed for $1, or "" if unknown.
upstream_installed_version() {
    local fn="${VERSION_FUNCS[$1]:-}"
    [[ -n "$fn" ]] && declare -F "$fn" >/dev/null || return 1
    "$fn" 2>/dev/null | head -1
}

# Is an upstream-binary utility out of date? Returns 0 only when BOTH versions
# are known AND they differ -- an unknown version is never treated as "up to
# date" by callers that skip work, and never counted as a pending update by
# callers that report one. Deliberately a string comparison: these are vendor
# build strings, not semver to be ordered, and any difference means the tree on
# disk is not the one upstream publishes.
upstream_update_available() {
    local installed latest
    installed=$(upstream_installed_version "$1") || return 2
    latest=$(upstream_latest_version "$1")       || return 2
    [[ -z "$installed" || -z "$latest" ]] && return 2
    [[ "$installed" != "$latest" ]]
}

# Should the utility at index $1 be hidden from the install listing because
# its only Arch install path is the AUR, AUR support is currently disabled,
# and it isn't already installed? Uninstalling an already-installed copy is
# never affected — see aur_remove in lib/aur.sh.
_utility_hidden_aur_only() {
    local idx="$1"
    [[ "${DISTRO_FAMILY:-}" == "arch" ]] || return 1
    local name="${UTILITIES[$idx]}"
    [[ "${UTILITY_AUR_ONLY_ARCH[$name]:-}" == "1" ]] || return 1
    [[ "${AUR_ENABLED:-false}" == "true" ]] && return 1
    [[ "${INSTALLED[$idx]:-0}" == "1" ]] && return 1
    # Not AUR-only on THIS system if the configured repos carry the package —
    # pacman installs it without touching the AUR, so there is nothing to hide.
    local pkg="${UTILITY_ARCH_PKG[$name]:-}"
    [[ -n "$pkg" ]] && arch_repo_has "$pkg" && return 1
    return 0
}

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
                # Run-action tasks use check_always_false so they're never offered
                # for uninstall/update, but may still expose status info via their
                # version function (e.g. System Updates shows the pending update
                # count, Switch Bootloader shows the currently active bootloader).
                if [[ "${CHECK_FUNCS[$util]:-}" == "check_always_false" ]]; then
                    local ver_func="${VERSION_FUNCS[$util]:-}"
                    if [[ -n "$ver_func" ]] && declare -f "$ver_func" &>/dev/null; then
                        INSTALLED_VERSIONS[$i]=$($ver_func 2>/dev/null)
                    fi
                fi
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
    DEPS_MAP["Brave Origin"]="curl:curl gpg:gnupg"
    DEPS_MAP["Firefox"]="curl:curl gpg:gnupg"
    DEPS_MAP["Visual Studio Code"]="curl:curl gpg:gnupg wget:wget"
    DEPS_MAP["VSCodium"]="curl:curl gpg:gnupg wget:wget"
    DEPS_MAP["Syncthing"]="curl:curl"
    DEPS_MAP["PIA VPN"]="curl:curl wget:wget"
    DEPS_MAP["Bitwarden Client"]="wget:wget"
    DEPS_MAP["Devolutions RDM"]="curl:curl gpg:gnupg"
    DEPS_MAP["Steam App"]="wget:wget"
    DEPS_MAP["LibreOffice"]="wget:wget"
    DEPS_MAP["Termius SSH Client"]="wget:wget"
    DEPS_MAP["Zen Browser"]="wget:wget"
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
# Verifies that a utility was installed correctly and is functional by
# re-running its registered check_*() function after an install/update.
# ============================================================================

# Run a health check for a utility after install/update.
# Usage: health_check "Utility Name"
# Returns 0 on pass, 1 on fail. Logs result.
health_check() {
    local util_name="$1"

    # Refresh shell command hash table so newly installed binaries are found
    hash -r 2>/dev/null

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
}
