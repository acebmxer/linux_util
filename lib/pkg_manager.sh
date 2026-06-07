#!/bin/bash

# ============================================================================
# Linux Utilities - Package Manager Module
# Provides distro detection and package manager abstraction layer
# ============================================================================

# Detect the distro and set package manager variables
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
        DISTRO_VERSION_ID="${VERSION_ID:-}"
        DISTRO_VERSION_CODENAME="${VERSION_CODENAME:-}"
        DISTRO_NAME="${NAME}"

        # Kubuntu ships ID=ubuntu and NAME="Ubuntu" in os-release;
        # detect it via the kubuntu-desktop metapackage so downstream
        # DISTRO_ID checks (e.g. "kubuntu") work correctly.
        if [[ "$DISTRO_ID" == "ubuntu" ]] && dpkg -l kubuntu-desktop 2>/dev/null | grep -q '^ii'; then
            DISTRO_ID="kubuntu"
            DISTRO_NAME="Kubuntu"
        fi
    else
        echo "Error: Cannot detect Linux distribution (/etc/os-release not found)."
        exit 1
    fi

    # Get full point-release version for select Debian-family distros
    # (e.g. 24.04 → 24.04.4 for Ubuntu/Kubuntu/Neon, 12 → 12.5 for Debian)
    case "$DISTRO_ID" in
        ubuntu|kubuntu|neon)
            # Extract point release from base-files package version.
            # Format: <N>ubuntu<M>[.<point>]+...  e.g. 13ubuntu10.4+p24.04+...
            local _bf_ver
            _bf_ver=$(dpkg-query -W -f '${Version}' base-files 2>/dev/null || true)
            if [[ "$_bf_ver" =~ ubuntu([0-9]+)(\.([0-9]+))? ]]; then
                DISTRO_VERSION_ID="${DISTRO_VERSION_ID}.${BASH_REMATCH[3]:-0}"
            fi
            ;;
        debian)
            # /etc/debian_version has the full point release (e.g. "12.5")
            if [[ -f /etc/debian_version ]]; then
                local _deb_ver
                _deb_ver=$(<"/etc/debian_version")
                if [[ "$_deb_ver" =~ ^([0-9]+\.[0-9]+) ]]; then
                    DISTRO_VERSION_ID="${BASH_REMATCH[1]}"
                fi
            fi
            ;;
    esac

    # Determine distro family
    case "$DISTRO_ID" in
        ubuntu|kubuntu|debian|linuxmint|pop|elementary|zorin|kali|neon)
            DISTRO_FAMILY="debian"
            PKG_MGR="apt"
            ;;
        fedora)
            DISTRO_FAMILY="fedora"
            PKG_MGR="dnf"
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            DISTRO_FAMILY="rhel"
            PKG_MGR="dnf"
            command -v dnf &>/dev/null || PKG_MGR="yum"
            ;;
        arch|manjaro|endeavouros|garuda|artix|cachyos)
            DISTRO_FAMILY="arch"
            PKG_MGR="pacman"
            ;;
        opensuse-leap|opensuse-tumbleweed|sles|opensuse-microos|opensuse)
            DISTRO_FAMILY="suse"
            PKG_MGR="zypper"
            ;;
        *)
            # Try ID_LIKE for derivatives
            case "$DISTRO_ID_LIKE" in
                *debian*|*ubuntu*)
                    DISTRO_FAMILY="debian"; PKG_MGR="apt" ;;
                *fedora*|*rhel*)
                    DISTRO_FAMILY="fedora"; PKG_MGR="dnf"
                    command -v dnf &>/dev/null || PKG_MGR="yum"
                    ;;
                *arch*)
                    DISTRO_FAMILY="arch"; PKG_MGR="pacman" ;;
                *suse*)
                    DISTRO_FAMILY="suse"; PKG_MGR="zypper" ;;
                *)
                    echo "Warning: Unrecognized distribution '${DISTRO_NAME}' (${DISTRO_ID})."
                    echo "Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE"
                    # Auto-detect by available package manager
                    if command -v apt &>/dev/null; then
                        DISTRO_FAMILY="debian"; PKG_MGR="apt"
                    elif command -v dnf &>/dev/null; then
                        DISTRO_FAMILY="fedora"; PKG_MGR="dnf"
                    elif command -v yum &>/dev/null; then
                        DISTRO_FAMILY="rhel"; PKG_MGR="yum"
                    elif command -v pacman &>/dev/null; then
                        DISTRO_FAMILY="arch"; PKG_MGR="pacman"
                    elif command -v zypper &>/dev/null; then
                        DISTRO_FAMILY="suse"; PKG_MGR="zypper"
                    else
                        echo "Error: No supported package manager found."
                        exit 1
                    fi
                    echo "Auto-detected package manager: $PKG_MGR"
                    ;;
            esac
            ;;
    esac

    echo "Detected: ${DISTRO_NAME} (family: ${DISTRO_FAMILY}, package manager: ${PKG_MGR})" >&2
    log_info "System detected: ${DISTRO_NAME} (family: ${DISTRO_FAMILY}, package manager: ${PKG_MGR})"
}

# --- Package Manager Wrappers ---

# How old (seconds) the apt/dnf/zypper cache may be before we re-fetch it.
# Override via env: PKG_CACHE_MAX_AGE_SECS=0 forces a refresh every time.
PKG_CACHE_MAX_AGE_SECS="${PKG_CACHE_MAX_AGE_SECS:-3600}"

# Seconds to wait for the package manager network call before giving up.
PKG_REFRESH_TIMEOUT_SECS="${PKG_REFRESH_TIMEOUT_SECS:-120}"

_pkg_cache_is_fresh() {
    local cache_path="$1"
    [[ -e "$cache_path" ]] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$cache_path") ))
    (( age < PKG_CACHE_MAX_AGE_SECS ))
}

pkg_refresh() {
    local mode="${1:-spinner}"
    local _run; [[ "$mode" == "direct" ]] && _run=run_direct || _run=run_with_spinner
    local _nc;  [[ "$mode" != "direct" ]] && _nc="--noconfirm" || _nc=""
    [[ "${_PKG_REFRESHED:-}" == "true" ]] && return 0

    # NOTE: On Arch, -Sy without -u risks partial upgrades. We use -Syu
    # here so that any subsequent pkg_install calls have a consistent DB+system.
    # $_nc is intentionally unquoted so an empty value passes no extra argument.
    # shellcheck disable=SC2086
    case "$PKG_MGR" in
        apt)
            if _pkg_cache_is_fresh /var/lib/apt/lists; then
                log_info "Package cache is fresh (< ${PKG_CACHE_MAX_AGE_SECS}s old), skipping apt update"
            else
                "$_run" "Refreshing package cache" \
                    timeout "$PKG_REFRESH_TIMEOUT_SECS" sudo apt update \
                        -o Acquire::http::Timeout=15 \
                        -o Acquire::https::Timeout=15 \
                        -o Acquire::Retries=1
            fi
            ;;
        dnf|yum)
            if _pkg_cache_is_fresh /var/cache/${PKG_MGR}/metadata/repomd.xml 2>/dev/null \
               || _pkg_cache_is_fresh /var/cache/${PKG_MGR}/.check 2>/dev/null; then
                log_info "Package cache is fresh, skipping ${PKG_MGR} makecache"
            else
                "$_run" "Refreshing package cache" \
                    timeout "$PKG_REFRESH_TIMEOUT_SECS" sudo "$PKG_MGR" makecache
            fi
            ;;
        pacman)
            # pacman -Syu always runs — skipping a partial sync risks DB mismatch.
            "$_run" "Refreshing package cache & upgrading" sudo pacman -Syu $_nc ;;
        zypper)
            "$_run" "Refreshing package cache" \
                timeout "$PKG_REFRESH_TIMEOUT_SECS" sudo zypper refresh ;;
    esac
    _PKG_REFRESHED=true
}

pkg_install() {
    local _label="Installing: $*"
    case "$PKG_MGR" in
        apt)     run_with_spinner "$_label" sudo apt install -y "$@" ;;
        dnf|yum) run_with_spinner "$_label" sudo "$PKG_MGR" install -y "$@" ;;
        pacman)  run_with_spinner "$_label" sudo pacman -S --noconfirm "$@" ;;
        zypper)  run_with_spinner "$_label" sudo zypper install -y "$@" ;;
    esac
}

pkg_remove() {
    local _label="Removing: $*"
    case "$PKG_MGR" in
        apt)     run_with_spinner "$_label" sudo apt purge --autoremove -y "$@" &&
                 run_with_spinner "Cleaning apt cache" sudo apt autoclean ;;
        dnf|yum) run_with_spinner "$_label" sudo "$PKG_MGR" remove -y "$@" ;;
        pacman)  run_with_spinner "$_label" sudo pacman -Rs --noconfirm "$@" ;;
        zypper)  run_with_spinner "$_label" sudo zypper remove -y "$@" ;;
    esac
}

pkg_upgrade() {
    local _label="Upgrading: $*"
    case "$PKG_MGR" in
        apt)     run_with_spinner "Refreshing package cache" sudo apt update &&
                 run_with_spinner "$_label" sudo apt install -y --only-upgrade "$@" ;;
        dnf|yum) run_with_spinner "$_label" sudo "$PKG_MGR" upgrade -y "$@" ;;
        pacman)  run_with_spinner "$_label" sudo pacman -S --noconfirm "$@" ;;
        zypper)  run_with_spinner "$_label" sudo zypper update -y "$@" ;;
    esac
}

pkg_check_installed() {
    case "$PKG_MGR" in
        apt)     dpkg -l "$1" 2>/dev/null | grep -q "^ii" ;;
        dnf|yum) rpm -q "$1" &>/dev/null ;;
        pacman)  pacman -Q "$1" &>/dev/null ;;
        zypper)  rpm -q "$1" &>/dev/null ;;
    esac
}

pkg_install_local() {
    local _label="Installing local package: $(basename "$1")"
    case "$PKG_MGR" in
        apt)     run_with_spinner "$_label" sudo apt install -y "$1" ;;
        dnf|yum) run_with_spinner "$_label" sudo "$PKG_MGR" install -y "$1" ;;
        pacman)  run_with_spinner "$_label" sudo pacman -U --noconfirm "$1" ;;
        zypper)  run_with_spinner "$_label" sudo zypper install -y --allow-unsigned-rpm "$1" ;;
    esac
}

pkg_autoremove() {
    local mode="${1:-spinner}"
    local _run _y _nc
    if [[ "$mode" == "direct" ]]; then
        _run=run_direct;       _y="";   _nc=""
    else
        _run=run_with_spinner; _y="-y"; _nc="--noconfirm"
    fi
    case "$PKG_MGR" in
        apt)
            # Capture dry-run output first to avoid SIGPIPE+pipefail false negative.
            # grep -q exits on first match, sending SIGPIPE to apt-get; with pipefail
            # that non-zero exit makes the pipeline condition false even when matches exist.
            local _apt_dry_run
            _apt_dry_run=$(sudo apt-get --dry-run autoremove 2>/dev/null) || true
            if grep -qE "^(Remv|Purg) " <<< "$_apt_dry_run"; then
                # shellcheck disable=SC2086
                "$_run" "Removing orphaned packages" sudo apt autoremove $_y
            else
                info "No orphaned packages to remove."
            fi
            ;;
        dnf|yum)
            if "$PKG_MGR" autoremove --assumeno 2>/dev/null | grep -qE "^Remove "; then
                # shellcheck disable=SC2086
                "$_run" "Removing orphaned packages" sudo "$PKG_MGR" autoremove $_y
            else
                info "No orphaned packages to remove."
            fi
            ;;
        pacman) "$_run" "Removing orphaned packages" \
                    bash -c "pkgs=\$(pacman -Qdtq 2>/dev/null); [[ -n \"\$pkgs\" ]] && sudo pacman -Rs $_nc \$pkgs || true" ;;
        zypper) true ;;
    esac
}

pkg_full_upgrade() {
    local mode="${1:-spinner}"
    local _run _y _nc
    if [[ "$mode" == "direct" ]]; then
        _run=run_direct;       _y="";   _nc=""
    else
        _run=run_with_spinner; _y="-y"; _nc="--noconfirm"
    fi
    # shellcheck disable=SC2086
    case "$PKG_MGR" in
        apt)     # Fix broken dependencies before upgrading (e.g. half-installed kernels)
                 "$_run" "Fixing broken packages" sudo apt --fix-broken install $_y || true
                 if [[ "$mode" == "direct" ]]; then
                     # Interactive (no -y): tee output so we can detect "Abort." (user typed N).
                     # Exit code 2 signals "Cancelled" to the runner, suppressing retries.
                     local _apt_out
                     _apt_out=$(mktemp)
                     printf "  Running full system upgrade ...\n"
                     sudo apt full-upgrade 2>&1 | tee "$_apt_out"
                     local _apt_rc=${PIPESTATUS[0]}
                     if grep -q "^Abort\.$" "$_apt_out"; then
                         printf "  ${RED}✗${RESET}  Running full system upgrade\n"
                         rm -f "$_apt_out"
                         return 2
                     fi
                     [[ $_apt_rc -eq 0 ]] \
                         && printf "  ${GREEN}✓${RESET}  Running full system upgrade\n" \
                         || printf "  ${RED}✗${RESET}  Running full system upgrade\n"
                     rm -f "$_apt_out"
                     return $_apt_rc
                 else
                     "$_run" "Running full system upgrade" sudo apt full-upgrade $_y
                 fi ;;
        dnf|yum) "$_run" "Running full system upgrade" sudo "$PKG_MGR" upgrade $_y ;;
        pacman)  if command -v yay &>/dev/null; then
                     "$_run" "Running full system upgrade (yay)"  yay  -Syu $_nc
                 elif command -v paru &>/dev/null; then
                     "$_run" "Running full system upgrade (paru)" paru -Syu $_nc
                 else
                     warn "No AUR helper (yay/paru) found. AUR packages will NOT be updated."
                     warn "To enable AUR updates, install yay: https://github.com/Jguer/yay#installation"
                     warn "  or paru: https://github.com/morganamilo/paru#installation"
                     "$_run" "Running full system upgrade (pacman only)" sudo pacman -Syu $_nc
                 fi ;;
        zypper)  "$_run" "Running full system upgrade" sudo zypper update $_y ;;
    esac
}

pkg_clean() {
    local mode="${1:-spinner}"
    local _run; [[ "$mode" == "direct" ]] && _run=run_direct || _run=run_with_spinner
    local _nc;  [[ "$mode" != "direct" ]] && _nc="--noconfirm" || _nc=""
    # $_nc is intentionally unquoted so an empty value passes no extra argument.
    # shellcheck disable=SC2086
    case "$PKG_MGR" in
        apt)     "$_run" "Cleaning package cache" sudo apt clean
                 "$_run" "Running apt autoclean"  sudo apt autoclean ;;
        dnf|yum) "$_run" "Cleaning package cache" sudo "$PKG_MGR" clean all ;;
        pacman)  "$_run" "Cleaning package cache" \
                     bash -c "sudo find /var/cache/pacman/pkg -maxdepth 1 -name 'download-*' -delete 2>/dev/null; sudo pacman -Sc $_nc" ;;
        zypper)  "$_run" "Cleaning package cache" sudo zypper clean -a ;;
    esac
}

# ============================================================================
# Interactive variants
# These run commands in the foreground with full terminal access so that
# dpkg config-file prompts, needrestart dialogs, and any other interactive
# questions are presented to the user unmodified.
# Used exclusively by full_update.sh and system_updates.sh.
# ============================================================================

pkg_refresh_interactive()     { pkg_refresh     direct; }
pkg_full_upgrade_interactive() { pkg_full_upgrade direct; }
pkg_autoremove_interactive()   { pkg_autoremove   direct; }
pkg_clean_interactive()        { pkg_clean        direct; }

# Detect and clean up packages left from a previous RHEL major version
# (common after leapp/ELevate upgrades). Runs distro-sync --allowerasing
# for only the stale packages to align them with the current release.
# Safe to call multiple times — no-ops if no stale packages are found.
_pkg_cleanup_stale_releases() {
    local mode="${1:-spinner}"
    [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]] || return 0

    local current_el
    current_el=$(rpm -E '%{rhel}' 2>/dev/null) || return 0
    [[ "$current_el" =~ ^[0-9]+$ ]] || return 0
    (( current_el > 7 )) || return 0

    local prev_el="el$(( current_el - 1 ))"
    local _run
    [[ "$mode" == "direct" ]] && _run=run_direct || _run=run_with_spinner

    local stale_pkgs
    stale_pkgs=$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
        | grep "\.${prev_el}" | grep -v "^gpg-pubkey-" || true)

    if [[ -n "$stale_pkgs" ]]; then
        local stale_count
        stale_count=$(echo "$stale_pkgs" | wc -l)
        warn "Found ${stale_count} package(s) from previous OS version (${prev_el})."
        warn "These may block updates. Running distro-sync to align with current release..."

        # Extract just the package names for a targeted distro-sync
        local stale_names
        stale_names=$(echo "$stale_pkgs" | sed 's/-[^-]*-[^-]*$//' | sort -u)

        # Split into packages that exist in repos (syncable) vs orphans (removable)
        local syncable="" orphan=""
        for pkg in $stale_names; do
            if dnf repoquery "$pkg" --quiet 2>/dev/null | grep -q .; then
                syncable+=" $pkg"
            else
                orphan+=" $pkg"
            fi
        done

        # Distro-sync packages that have a current-release equivalent
        if [[ -n "${syncable// /}" ]]; then
            # shellcheck disable=SC2086
            "$_run" "Syncing stale packages to current release" \
                sudo dnf distro-sync -y --allowerasing $syncable || {
                warn "distro-sync had errors. You may need to manually resolve package conflicts."
                warn "Try: sudo dnf distro-sync --allowerasing"
            }
        fi

        # Remove orphan packages that have no equivalent in current repos
        # --disableexcludes=all bypasses repo exclude filters (e.g. ELevate excludes leapp packages)
        if [[ -n "${orphan// /}" ]]; then
            info "Removing ${prev_el} packages with no current-release equivalent:${orphan}"
            # shellcheck disable=SC2086
            "$_run" "Removing orphaned ${prev_el} packages" \
                sudo dnf remove -y --disableexcludes=all $orphan || {
                warn "Some orphaned packages could not be removed automatically."
            }
        fi
    fi

    # Clean up ELevate repo after a successful major version upgrade
    if rpm -q elevate-release &>/dev/null; then
        info "Removing ELevate repository (no longer needed post-upgrade)."
        "$_run" "Removing ELevate repository" \
            sudo dnf remove -y elevate-release || true
    fi
}

# Shared implementation for thorough cleanup.
# Accepts a "mode" argument: "spinner" (non-interactive) or "direct" (interactive).
_pkg_cleanup_thorough_impl() {
    local mode="${1:-spinner}"
    local _runner _confirm_flag
    if [[ "$mode" == "direct" ]]; then
        _runner="run_direct"
        _confirm_flag=""
    else
        _runner="run_with_spinner"
        _confirm_flag="-y"
    fi

    info "Running thorough system cleanup..."

    # Step 1: Remove orphaned dependencies
    pkg_autoremove "$mode"

    # Step 2: Remove old kernels (keep current + one previous)
    local current_kernel
    current_kernel=$(uname -r)
    info "Current kernel: ${current_kernel} (will be preserved)"

    case "$PKG_MGR" in
        apt)
            local kernels_to_remove=""
            local installed_kernels
            installed_kernels=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii.*linux-image-[0-9]/ {print $2}' | sort -V)
            if [[ -n "$installed_kernels" ]]; then
                local keep_count=2
                local total
                total=$(echo "$installed_kernels" | wc -l)
                if (( total > keep_count )); then
                    kernels_to_remove=$(echo "$installed_kernels" | head -n -${keep_count} | grep -Fv "$current_kernel" || true)
                fi
            fi
            if [[ -n "$kernels_to_remove" ]]; then
                info "Removing old kernels: $(echo "$kernels_to_remove" | tr '\n' ' ')"
                local headers_to_remove=""
                for kern in $kernels_to_remove; do
                    local ver
                    ver=$(echo "$kern" | sed 's/linux-image-\(unsigned-\)\?//')
                    if dpkg -l "linux-headers-${ver}" 2>/dev/null | grep -q "^ii"; then
                        headers_to_remove+="linux-headers-${ver} "
                    fi
                done
                # shellcheck disable=SC2086
                "$_runner" "Removing old kernels" sudo apt-get purge ${_confirm_flag} $kernels_to_remove $headers_to_remove || true
            else
                info "No old kernels to remove."
            fi
            ;;
        dnf|yum)
            "$_runner" "Removing old kernels" sudo "$PKG_MGR" remove -y --oldinstallonly --setopt installonly_limit=2 || true
            ;;
        pacman)
            # Arch doesn't accumulate old kernels the same way; skip
            ;;
        zypper)
            "$_runner" "Removing old kernels" sudo zypper purge-kernels --keep 2 || true
            ;;
    esac

    # Step 3: Purge removed package configs (Debian family only)
    if [[ "$PKG_MGR" == "apt" ]]; then
        local rc_packages
        rc_packages=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')
        if [[ -n "$rc_packages" ]]; then
            # shellcheck disable=SC2086
            "$_runner" "Purging removed package configs" sudo dpkg --purge $rc_packages || true
        fi
    fi

    # Step 4: Remove stale packages from previous RHEL major version (post-upgrade cleanup)
    _pkg_cleanup_stale_releases "$mode"

    # Step 5: Clean package cache
    pkg_clean "$mode"

    # Step 6: Clean apt lists partial files (Debian family only)
    if [[ "$PKG_MGR" == "apt" ]]; then
        sudo rm -f /var/lib/apt/lists/partial/* 2>/dev/null || true
    fi

    info "System cleanup completed."
}

pkg_cleanup_thorough_interactive() {
    _pkg_cleanup_thorough_impl "direct"
}

# Thorough cleanup: autoremove, old kernels, purge configs, clean cache
pkg_cleanup_thorough() {
    _pkg_cleanup_thorough_impl "spinner"
}

# Shared helper for Debian-family distro upgrades via codename swap.
# Backs up sources, swaps old codename for new in official repos,
# runs apt update + full-upgrade, restores on failure.
# Arguments: $1 = old codename, $2 = new codename
# Optional:  $3 = space-separated list of official mirror URL patterns to scope
#            replacements (defaults to common Debian/Ubuntu patterns).
# Returns 0 on success, 1 on failure (with sources restored).
_apt_codename_upgrade() {
    local old_codename="$1"
    local new_codename="$2"
    # Default official mirror patterns — caller can override for derivatives
    local mirror_patterns="${3:-deb.debian.org archive.ubuntu.com security.debian.org security.ubuntu.com}"

    if [[ -z "$old_codename" || -z "$new_codename" ]]; then
        error "_apt_codename_upgrade: old and new codename arguments are required."
        return 1
    fi

    # Step 1: Install all pending updates for the current release first.
    # Use dist-upgrade so new kernel packages etc. are included.
    info "Installing all pending updates before codename upgrade..."
    if ! sudo apt-get dist-upgrade -y; then
        error "Failed to install pending updates. Cannot proceed with codename upgrade."
        return 1
    fi

    # A reboot may be required after kernel updates before proceeding
    if [[ -f /var/run/reboot-required ]]; then
        warn "A reboot is required before the codename upgrade can proceed."
        warn "Please reboot the system and re-run this script to continue the upgrade."
        return 1
    fi

    # Step 2: Create persistent backup directory
    local backup_dir="/var/backups/linux_util/sources_backup_$(date +%Y%m%d_%H%M%S)"
    sudo mkdir -p "$backup_dir"

    info "Backing up sources to ${backup_dir}..."
    if [[ -f /etc/apt/sources.list ]]; then
        sudo cp /etc/apt/sources.list "$backup_dir/"
    fi
    if ls /etc/apt/sources.list.d/*.list &>/dev/null; then
        sudo cp /etc/apt/sources.list.d/*.list "$backup_dir/"
    fi
    if ls /etc/apt/sources.list.d/*.sources &>/dev/null; then
        sudo cp /etc/apt/sources.list.d/*.sources "$backup_dir/"
    fi

    # Step 3: Check for held packages
    local held_packages
    held_packages=$(apt-mark showhold 2>/dev/null)
    if [[ -n "$held_packages" ]]; then
        warn "The following packages are held and may block the upgrade:"
        echo "$held_packages"
        echo ""
        local hold_confirm=""
        while true; do
            read -rp "Continue with held packages? (y/N): " hold_confirm
            case "${hold_confirm,,}" in
                y|yes) break ;;
                n|no|'')
                    info "Upgrade aborted due to held packages."
                    sudo rm -rf "$backup_dir"
                    return 1
                    ;;
                *) echo "  Please enter Y or N." ;;
            esac
        done
    fi

    # Step 4: Build a grep pattern to match official mirror URLs
    local mirror_grep_pattern=""
    local pattern
    for pattern in $mirror_patterns; do
        if [[ -n "$mirror_grep_pattern" ]]; then
            mirror_grep_pattern="${mirror_grep_pattern}|${pattern}"
        else
            mirror_grep_pattern="$pattern"
        fi
    done

    # Build escaped mirror pattern for sed (pipe-delimited -> backslash-escaped)
    local mirror_sed_pattern="${mirror_grep_pattern//|/\\|}"

    # Step 5: Preview all source file changes and confirm before applying.
    # Collect files to modify, generate a diff for each, show it to the user,
    # then ask for confirmation before any sed -i runs.
    local sources_file
    local skipped_repos=false
    local files_to_update=()
    local sed_cmds=()

    if [[ -f /etc/apt/sources.list ]]; then
        files_to_update+=("/etc/apt/sources.list")
        sed_cmds+=("/^[[:space:]]*deb\(-src\)\?[[:space:]].*\(${mirror_sed_pattern}\)/s/\b${old_codename}\b/${new_codename}/g")
    fi
    for sources_file in /etc/apt/sources.list.d/*.list; do
        [[ -f "$sources_file" ]] || continue
        if grep -qE "(${mirror_grep_pattern})" "$sources_file" 2>/dev/null; then
            files_to_update+=("$sources_file")
            sed_cmds+=("/^[[:space:]]*deb\(-src\)\?[[:space:]].*\(${mirror_sed_pattern}\)/s/\b${old_codename}\b/${new_codename}/g")
        else
            verbose "Skipping third-party repo: $(basename "$sources_file")"
            skipped_repos=true
        fi
    done

    # Step 6: Collect DEB822 .sources files (Suites: lines only)
    # DEB822 files group URIs and Suites in the same stanza, so we check
    # if the file contains an official mirror and only then swap Suites.
    for sources_file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$sources_file" ]] || continue
        if grep -qE "(${mirror_grep_pattern})" "$sources_file" 2>/dev/null; then
            files_to_update+=("$sources_file")
            sed_cmds+=("/^Suites:/s/\b${old_codename}\b/${new_codename}/g")
        else
            verbose "Skipping third-party repo: $(basename "$sources_file")"
            skipped_repos=true
        fi
    done

    if [[ "$skipped_repos" == "true" ]]; then
        warn "Third-party repositories were not modified. They may need manual updating for the new release."
    fi

    if [[ ${#files_to_update[@]} -eq 0 ]]; then
        warn "No official mirror source files found to update. The codename swap may have nothing to do."
        return 1
    fi

    # Show a diff of every file that will be changed so the user can review
    # before any destructive write happens.
    echo ""
    info "The following changes will be made to your APT source files:"
    echo "  (${old_codename} -> ${new_codename})"
    echo ""
    local i
    for (( i = 0; i < ${#files_to_update[@]}; i++ )); do
        local f="${files_to_update[$i]}"
        local cmd="${sed_cmds[$i]}"
        local tmp_preview
        tmp_preview=$(mktemp)
        CLEANUP_FILES+=("$tmp_preview")
        sudo sed "${cmd}" "$f" > "$tmp_preview" 2>/dev/null
        if ! diff -u "$f" "$tmp_preview" > /dev/null 2>&1; then
            echo "  --- $(basename "$f") ---"
            diff -u "$f" "$tmp_preview" | grep -E '^[+-]' | grep -v '^[+-]{3}' | head -20 || true
            echo ""
        fi
    done

    local sources_confirm=""
    while true; do
        read -rp "Apply these source file changes and proceed with the upgrade? (y/N): " sources_confirm
        case "${sources_confirm,,}" in
            y|yes) break ;;
            n|no|'')
                info "Upgrade aborted. No source files were modified."
                sudo rm -rf "$backup_dir"
                return 1
                ;;
            *) echo "  Please enter Y or N." ;;
        esac
    done

    # Apply the changes now that the user has confirmed
    for (( i = 0; i < ${#files_to_update[@]}; i++ )); do
        local f="${files_to_update[$i]}"
        local cmd="${sed_cmds[$i]}"
        info "Updating codename in $(basename "$f")..."
        sudo sed -i "${cmd}" "$f"
    done

    # Step 7: Run apt-get update (apt-get is more stable for scripted use)
    info "Refreshing package lists for ${new_codename}..."
    if ! sudo apt-get update; then
        error "apt-get update failed after codename swap. Restoring sources..."
        _apt_codename_upgrade_restore "$backup_dir"
        return 1
    fi

    # Step 8: Run apt-get dist-upgrade (standard for major version upgrades)
    # Note: cleanup (autoremove, etc.) is the caller's responsibility
    info "Running full upgrade to ${new_codename}..."
    if ! sudo apt-get dist-upgrade -y; then
        error "apt-get dist-upgrade failed. Restoring sources..."
        _apt_codename_upgrade_restore "$backup_dir"
        # Re-sync package database to old release
        warn "Re-syncing package database to previous release..."
        sudo apt-get update || true
        warn "Some packages may have been partially upgraded. Manual intervention may be needed."
        return 1
    fi

    info "Codename upgrade from ${old_codename} to ${new_codename} completed successfully."
    info "Source backup preserved at: ${backup_dir}"
    return 0
}

# Restore sources from backup directory.
# Argument: $1 = backup directory path
_apt_codename_upgrade_restore() {
    local backup_dir="$1"
    if [[ ! -d "$backup_dir" ]]; then
        error "Backup directory not found: ${backup_dir}"
        return 1
    fi

    if [[ -f "$backup_dir/sources.list" ]]; then
        sudo cp "$backup_dir/sources.list" /etc/apt/sources.list
    fi
    if ls "$backup_dir"/*.list &>/dev/null; then
        sudo cp "$backup_dir"/*.list /etc/apt/sources.list.d/
    fi
    if ls "$backup_dir"/*.sources &>/dev/null; then
        sudo cp "$backup_dir"/*.sources /etc/apt/sources.list.d/
    fi
    info "Sources restored from backup: ${backup_dir}"
}

# Install leapp and ELevate packages for RHEL-family distro upgrades.
# For community RHEL derivatives (AlmaLinux, Rocky, CentOS, Oracle Linux),
# leapp comes from AlmaLinux's ELevate project which requires its own repo.
# RHEL proper ships leapp in its standard repos.
_install_leapp_packages() {
    # For community distros, install the ELevate repo first.
    # Trust model: we install a noarch RPM directly from repo.almalinux.org.
    # DNF verifies the RPM's built-in GPG signature on install, so the package
    # itself is authenticated. This RPM then adds the ELevate repo with its GPG
    # key, after which all subsequent ELevate packages are signature-verified.
    # This is the standard bootstrapping pattern for third-party RHEL repos.
    if [[ "$DISTRO_ID" != "rhel" ]]; then
        if ! rpm -q elevate-release &>/dev/null; then
            info "Installing ELevate repo for upgrade support..."
            local el_ver
            el_ver=$(rpm --eval '%{rhel}')
            sudo "$PKG_MGR" install -y \
                "http://repo.almalinux.org/elevate/elevate-release-latest-el${el_ver}.noarch.rpm" || {
                error "Could not install ELevate repo. Cannot check for upgrades."
                return 1
            }
        fi
    fi

    # Determine the correct leapp data package for this distro
    local leapp_data_pkg=""
    case "$DISTRO_ID" in
        almalinux|alma)  leapp_data_pkg="leapp-data-almalinux" ;;
        rocky)           leapp_data_pkg="leapp-data-rocky" ;;
        centos)          leapp_data_pkg="leapp-data-centos" ;;
        ol)              leapp_data_pkg="leapp-data-oraclelinux" ;;
        # RHEL uses its own data bundled with leapp-upgrade
    esac

    info "Installing leapp upgrade packages..."
    local install_pkgs=(leapp-upgrade)
    [[ -n "$leapp_data_pkg" ]] && install_pkgs+=("$leapp_data_pkg")

    sudo "$PKG_MGR" install -y "${install_pkgs[@]}" || {
        error "Failed to install leapp packages. Cannot proceed with upgrade."
        return 1
    }
}

# Fix common leapp inhibitors before running preupgrade analysis.
# Checks for known issues that can be auto-remediated and offers fixes.
_leapp_pre_remediate() {
    local target_major="$1"
    local fixes_applied=0

    info "Checking for common upgrade blockers..."

    # 1. Legacy ifcfg network configuration (EL9 → EL10)
    #    RHEL 10 / AlmaLinux 10 drops support for ifcfg-style configs.
    if (( target_major >= 10 )); then
        local ifcfg_count=0
        ifcfg_count=$(find /etc/sysconfig/network-scripts/ -maxdepth 1 -name 'ifcfg-*' \
            ! -name 'ifcfg-lo' 2>/dev/null | wc -l)
        if (( ifcfg_count > 0 )); then
            warn "Found ${ifcfg_count} legacy ifcfg network config file(s)."
            warn "RHEL 10+ requires NetworkManager keyfile format."
            echo ""
            local migrate_confirm=""
            while true; do
                read -rp "  Migrate network configs to keyfile format now? (Y/n): " migrate_confirm < /dev/tty
                case "${migrate_confirm,,}" in
                    y|yes|'')
                        if sudo nmcli connection migrate 2>&1; then
                            info "Network configuration migrated to keyfile format."
                            (( fixes_applied++ ))
                        else
                            warn "Network migration failed. You may need to migrate manually: sudo nmcli connection migrate"
                        fi
                        break
                        ;;
                    n|no)
                        warn "Skipped. This will likely cause a leapp inhibitor."
                        break
                        ;;
                    *) echo "  Please enter Y or N." ;;
                esac
            done
        fi
    fi

    # 2. AllowZoneDrifting in firewalld (EL8 → EL9)
    if (( target_major == 9 )) && [[ -f /etc/firewalld/firewalld.conf ]]; then
        if grep -q '^AllowZoneDrifting=yes' /etc/firewalld/firewalld.conf 2>/dev/null; then
            warn "firewalld AllowZoneDrifting=yes is deprecated and blocks EL9 upgrades."
            echo ""
            local fwd_confirm=""
            while true; do
                read -rp "  Set AllowZoneDrifting=no now? (Y/n): " fwd_confirm < /dev/tty
                case "${fwd_confirm,,}" in
                    y|yes|'')
                        sudo sed -i 's/^AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf
                        info "AllowZoneDrifting set to no."
                        (( fixes_applied++ ))
                        break
                        ;;
                    n|no)
                        warn "Skipped. This will likely cause a leapp inhibitor."
                        break
                        ;;
                    *) echo "  Please enter Y or N." ;;
                esac
            done
        fi
    fi

    # 3. /etc/resolv.conf is a symlink (causes DNS failures in leapp container)
    if [[ -L /etc/resolv.conf ]]; then
        warn "/etc/resolv.conf is a symlink, which can cause DNS failures during the upgrade."
        echo ""
        local resolv_confirm=""
        while true; do
            read -rp "  Convert to a regular file now? (Y/n): " resolv_confirm < /dev/tty
            case "${resolv_confirm,,}" in
                y|yes|'')
                    local resolv_target
                    resolv_target=$(readlink -f /etc/resolv.conf)
                    if [[ -f "$resolv_target" ]]; then
                        sudo cp --remove-destination "$resolv_target" /etc/resolv.conf
                        info "/etc/resolv.conf converted to a regular file."
                        (( fixes_applied++ ))
                    else
                        warn "Symlink target not found. Skipping."
                    fi
                    break
                    ;;
                n|no)
                    warn "Skipped. This may cause DNS resolution failures during upgrade."
                    break
                    ;;
                *) echo "  Please enter Y or N." ;;
            esac
        done
    fi

    if (( fixes_applied > 0 )); then
        info "Applied ${fixes_applied} pre-upgrade fix(es)."
    else
        info "No common blockers found."
    fi
}

# Check if a distribution version upgrade is available.
# Returns 0 if available (outputs target version to stdout), 1 if not.
# Dispatches on DISTRO_ID since upgrade paths are distro-specific.
pkg_check_upgrade_available() {
    case "$DISTRO_ID" in
        ubuntu|kubuntu|pop|neon)
            # Ensure do-release-upgrade is available
            if ! command -v do-release-upgrade &>/dev/null; then
                info "Installing update-manager-core for upgrade checks..." >&2
                sudo apt-get install -y update-manager-core >&2 2>&1 || {
                    warn "Could not install update-manager-core"
                    return 1
                }
            fi
            # Check for available upgrade
            local check_output
            check_output=$(do-release-upgrade -c 2>&1) || true
            if echo "$check_output" | grep -qi "new release"; then
                # Extract target version from output like "New release '24.04 LTS' available."
                local target
                target=$(echo "$check_output" | grep -oP "New release '\K[^']+")
                if [[ -n "$target" ]]; then
                    echo "$target"
                    return 0
                fi
            fi

            # Fallback: query meta-release directly.
            # do-release-upgrade -c may miss upgrades when the Prompt is set to
            # "lts" and no new LTS exists yet, but a non-LTS release is available.
            # Also handles cases where intermediate releases have reached EOL.
            local release_config="/etc/update-manager/release-upgrades"
            local prompt="lts"
            if [[ -f "$release_config" ]]; then
                prompt=$(grep -oP '^Prompt=\K.*' "$release_config" 2>/dev/null || echo "lts")
            fi

            # Always check both channels so the user can be offered
            # the LTS-vs-normal track choice in pkg_distro_upgrade()
            local meta_urls=(
                "http://changelogs.ubuntu.com/meta-release-lts"
                "http://changelogs.ubuntu.com/meta-release"
            )

            for meta_url in "${meta_urls[@]}"; do
                local meta_content
                meta_content=$(curl -sf --max-time 10 "$meta_url" 2>/dev/null | tr -d '\r') || continue

                # Parse meta-release blocks for the latest supported version
                # newer than the current one
                local latest_supported="" block_version="" block_supported=""
                while IFS= read -r line; do
                    case "$line" in
                        Version:\ *)
                            block_version="${line#Version: }"
                            ;;
                        Supported:\ *)
                            block_supported="${line#Supported: }"
                            if [[ "$block_supported" == "1" && -n "$block_version" ]]; then
                                if dpkg --compare-versions "$block_version" gt "$DISTRO_VERSION_ID" 2>/dev/null; then
                                    latest_supported="$block_version"
                                fi
                            fi
                            block_version=""
                            block_supported=""
                            ;;
                    esac
                done <<< "$meta_content"

                if [[ -n "$latest_supported" ]]; then
                    echo "$latest_supported"
                    return 0
                fi
            done

            return 1
            ;;
        fedora)
            # Try next release version — use repoquery to check if the next version's repos exist
            # without downloading any packages
            local next_ver=$(( DISTRO_VERSION_ID + 1 ))
            if sudo dnf --releasever="$next_ver" --repo=fedora repoquery --latest-limit=1 fedora-release &>/dev/null; then
                echo "$next_ver"
                return 0
            fi
            return 1
            ;;
        opensuse-leap)
            # Check for newer Leap version by querying product info
            local current_ver="$DISTRO_VERSION_ID"
            # Try incrementing minor version first (e.g., 15.5 -> 15.6), then major
            local major minor next_minor next_major
            major=$(echo "$current_ver" | cut -d. -f1)
            minor=$(echo "$current_ver" | cut -d. -f2)
            next_minor="${major}.$(( minor + 1 ))"
            next_major="$(( major + 1 )).0"

            # Check if next minor version repos exist
            if curl -sf --head "https://download.opensuse.org/distribution/leap/${next_minor}/repo/oss/" &>/dev/null; then
                echo "$next_minor"
                return 0
            elif curl -sf --head "https://download.opensuse.org/distribution/leap/${next_major}/repo/oss/" &>/dev/null; then
                echo "$next_major"
                return 0
            fi
            return 1
            ;;
        opensuse-tumbleweed|arch|manjaro|endeavouros|garuda|artix|kali)
            # Rolling release — no discrete version upgrades.
            # Return 2 (not 1) so callers can distinguish "rolling/no upgrade path"
            # from "check failed" (1) and "upgrade available" (0).
            return 2
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            # CentOS Stream is rolling — no discrete version upgrades
            if [[ -f /etc/centos-release ]] && grep -qi "stream" /etc/centos-release 2>/dev/null; then
                info "CentOS Stream is a rolling release and does not support discrete version upgrades via this tool."
                return 2
            fi

            # Install leapp if not present
            if ! command -v leapp &>/dev/null; then
                # Redirect to stderr so install output doesn't pollute
                # the version string captured by command substitution
                _install_leapp_packages >&2 || return 1
            fi

            # Target is next major version
            local current_major
            current_major=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
            local target_major=$(( current_major + 1 ))

            # Lightweight check only — full preupgrade is deferred to
            # pkg_distro_upgrade since it takes 10-30 minutes.
            # Just verify leapp is installed and the target is a reasonable version.
            # NOTE: This is an optimistic check. We confirm leapp is present and the
            # target version is within the supported range (RHEL 8-11), but we do NOT
            # run "leapp preupgrade" here. The real inhibitor analysis happens during
            # pkg_distro_upgrade(). A return 0 here means "upgrade is likely possible",
            # not "upgrade is guaranteed to succeed".
            if command -v leapp &>/dev/null && (( target_major >= 8 && target_major <= 11 )); then
                echo "${target_major}.0"
                return 0
            fi
            return 1
            ;;
        debian)
            # Query Debian's stable release codename and compare with current
            local stable_release_info
            stable_release_info=$(curl -sf --max-time 10 "https://deb.debian.org/debian/dists/stable/Release" 2>/dev/null) || {
                warn "Could not fetch Debian stable release info"
                return 1
            }
            local stable_codename
            stable_codename=$(echo "$stable_release_info" | grep -oP '^Codename:\s*\K\S+')
            if [[ -z "$stable_codename" ]]; then
                warn "Could not parse Debian stable codename"
                return 1
            fi
            if [[ "$stable_codename" != "$DISTRO_VERSION_CODENAME" ]]; then
                echo "$stable_codename"
                return 0
            fi
            return 1
            ;;
        linuxmint)
            # Install mintupgrade if not present
            if ! command -v mintupgrade &>/dev/null; then
                info "Installing mintupgrade for upgrade checks..." >&2
                sudo apt-get install -y mintupgrade >&2 2>&1 || {
                    warn "Could not install mintupgrade"
                    return 1
                }
            fi
            # Check for available upgrade
            local mint_check_output
            mint_check_output=$(mintupgrade check 2>&1) || true
            if echo "$mint_check_output" | grep -qi "new version\|upgrade available\|ready to upgrade"; then
                local mint_target
                mint_target=$(echo "$mint_check_output" | grep -oP 'Linux Mint \K[0-9.]+' | tail -1)
                if [[ -n "$mint_target" ]]; then
                    echo "$mint_target"
                    return 0
                fi
            fi
            return 1
            ;;
        elementary)
            # Elementary is based on Ubuntu LTS. Check UBUNTU_CODENAME from os-release
            # and query the Elementary repo for a newer release.
            local elem_ubuntu_codename=""
            if [[ -f /etc/os-release ]]; then
                elem_ubuntu_codename=$(grep -oP '^UBUNTU_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)
            fi

            # Check Elementary's repo for dists newer than current
            local elem_current_ver="$DISTRO_VERSION_ID"
            local elem_major
            elem_major=$(echo "$elem_current_ver" | cut -d. -f1)
            local elem_next_major=$(( elem_major + 1 ))

            # Query packages.elementary.io for next major version
            if curl -sf --max-time 10 --head "https://packages.elementary.io/appcenter/${elem_next_major}/dists/" &>/dev/null || \
               curl -sf --max-time 10 --head "https://packages.elementary.io/stable/${elem_next_major}/dists/" &>/dev/null; then
                echo "$elem_next_major"
                return 0
            fi

            # Fallback: check if underlying Ubuntu has a newer LTS
            if [[ -n "$elem_ubuntu_codename" ]]; then
                local ubuntu_stable_info
                ubuntu_stable_info=$(curl -sf --max-time 10 "http://changelogs.ubuntu.com/meta-release-lts" 2>/dev/null) || true
                if [[ -n "$ubuntu_stable_info" ]]; then
                    local latest_lts_codename
                    latest_lts_codename=$(echo "$ubuntu_stable_info" | grep -oP '^Dist: \K\S+' | tail -1)
                    if [[ -n "$latest_lts_codename" && "$latest_lts_codename" != "$elem_ubuntu_codename" ]]; then
                        echo "$elem_next_major"
                        return 0
                    fi
                fi
            fi
            return 1
            ;;
        zorin)
            # Zorin is based on Ubuntu LTS. Check UBUNTU_CODENAME from os-release.
            local zorin_ubuntu_codename=""
            if [[ -f /etc/os-release ]]; then
                zorin_ubuntu_codename=$(grep -oP '^UBUNTU_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)
            fi

            # Check if underlying Ubuntu has a newer LTS
            local zorin_current_major
            zorin_current_major=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
            local zorin_next_major=$(( zorin_current_major + 1 ))

            if [[ -n "$zorin_ubuntu_codename" ]]; then
                local zorin_ubuntu_meta
                zorin_ubuntu_meta=$(curl -sf --max-time 10 "http://changelogs.ubuntu.com/meta-release-lts" 2>/dev/null) || true
                if [[ -n "$zorin_ubuntu_meta" ]]; then
                    local zorin_latest_lts
                    zorin_latest_lts=$(echo "$zorin_ubuntu_meta" | grep -oP '^Dist: \K\S+' | tail -1)
                    if [[ -n "$zorin_latest_lts" && "$zorin_latest_lts" != "$zorin_ubuntu_codename" ]]; then
                        echo "$zorin_next_major"
                        return 0
                    fi
                fi
            fi
            return 1
            ;;
        *)
            # Unknown distro — no upgrade path
            return 1
            ;;
    esac
}

# Perform a distribution version upgrade.
# Argument: $1 = target version (from pkg_check_upgrade_available output)
# Returns 0 on success, 1 on failure.
pkg_distro_upgrade() {
    local target_version="$1"

    # I-3: Validate target_version argument
    if [[ -z "$target_version" ]]; then
        error "pkg_distro_upgrade: target_version argument is required."
        return 1
    fi

    case "$DISTRO_ID" in
        ubuntu|kubuntu|pop|neon)
            # LTS awareness: check if current release is LTS
            local release_config="/etc/update-manager/release-upgrades"
            local original_prompt=""

            if [[ -f "$release_config" ]]; then
                original_prompt=$(grep -oP '^Prompt=\K.*' "$release_config" 2>/dev/null || echo "")

                # Check if current version is LTS (Ubuntu LTS versions: XX.04 where XX is even)
                # Check for ubuntu and kubuntu — both follow the same LTS release scheme
                local is_lts=false
                if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" ]]; then
                    local year month
                    year=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
                    month=$(echo "$DISTRO_VERSION_ID" | cut -d. -f2)
                    if (( month == 4 && year % 2 == 0 )); then
                        is_lts=true
                    fi
                fi

                # Determine if the detected target is LTS or non-LTS
                local tgt_ver="${target_version%% *}"
                local tgt_y tgt_m tgt_is_lts=false
                tgt_y=$(echo "$tgt_ver" | cut -d. -f1)
                tgt_m=$(echo "$tgt_ver" | cut -d. -f2)
                if [[ -n "$tgt_y" && -n "$tgt_m" ]] && (( tgt_m == 4 && tgt_y % 2 == 0 )); then
                    tgt_is_lts=true
                fi

                # Helper: probe whether an LTS upgrade exists
                _probe_lts_target() {
                    sudo sed -i "s/^Prompt=.*/Prompt=lts/" "$release_config"
                    local _check _tgt
                    _check=$(do-release-upgrade -c 2>&1) || true
                    if echo "$_check" | grep -qi "new release"; then
                        _tgt=$(echo "$_check" | grep -oP "New release '\K[^']+" || true)
                        [[ -n "$_tgt" ]] && echo "$_tgt" && return 0
                    fi
                    return 1
                }

                # Helper: probe whether a non-LTS upgrade exists
                _probe_normal_target() {
                    sudo sed -i "s/^Prompt=.*/Prompt=normal/" "$release_config"
                    local _check _tgt
                    _check=$(do-release-upgrade -c 2>&1) || true
                    if echo "$_check" | grep -qi "new release"; then
                        _tgt=$(echo "$_check" | grep -oP "New release '\K[^']+" || true)
                        [[ -n "$_tgt" ]] && echo "$_tgt" && return 0
                    fi
                    return 1
                }

                if [[ "$is_lts" == "true" ]]; then
                    # Currently on LTS — offer to stay LTS or switch to non-LTS
                    echo ""
                    echo "You are currently on an LTS release (${DISTRO_NAME} ${DISTRO_VERSION_ID})."
                    echo ""
                    echo "  1) Stay on LTS track (upgrade only to next LTS release)"
                    echo "  2) Switch to latest release track (including non-LTS)"
                    echo ""
                    local track_choice=""
                    while [[ "$track_choice" != "1" && "$track_choice" != "2" ]]; do
                        read -rp "Choose [1/2]: " track_choice < /dev/tty
                    done

                    if [[ "$track_choice" == "1" ]]; then
                        # User wants LTS — verify an LTS target exists
                        if [[ "$tgt_is_lts" == "true" ]]; then
                            sudo sed -i "s/^Prompt=.*/Prompt=lts/" "$release_config"
                        else
                            local lts_target
                            lts_target=$(_probe_lts_target) || true
                            if [[ -n "$lts_target" ]]; then
                                target_version="$lts_target"
                                info "LTS upgrade target: ${target_version}"
                            else
                                info "No next LTS release is available yet. Your system is up to date on the LTS track."
                                sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
                                return 2
                            fi
                        fi
                    else
                        sudo sed -i "s/^Prompt=.*/Prompt=normal/" "$release_config"
                        # If detected target was LTS, check for a newer non-LTS
                        if [[ "$tgt_is_lts" == "true" ]]; then
                            local normal_target
                            normal_target=$(_probe_normal_target) || true
                            if [[ -n "$normal_target" ]]; then
                                target_version="$normal_target"
                                info "Non-LTS upgrade target: ${target_version}"
                            fi
                        fi
                    fi
                else
                    # Currently on non-LTS — offer to switch to LTS or stay on non-LTS
                    # Only prompt if an LTS release is actually available
                    local lts_target
                    lts_target=$(_probe_lts_target) || true
                    # Restore prompt to normal while we decide
                    sudo sed -i "s/^Prompt=.*/Prompt=normal/" "$release_config"

                    if [[ -n "$lts_target" ]]; then
                        echo ""
                        echo "You are currently on a non-LTS release (${DISTRO_NAME} ${DISTRO_VERSION_ID})."
                        echo ""
                        echo "  1) Switch to LTS track (upgrade to ${lts_target})"
                        echo "  2) Stay on latest release track (upgrade to ${target_version})"
                        echo ""
                        local track_choice=""
                        while [[ "$track_choice" != "1" && "$track_choice" != "2" ]]; do
                            read -rp "Choose [1/2]: " track_choice < /dev/tty
                        done

                        if [[ "$track_choice" == "1" ]]; then
                            sudo sed -i "s/^Prompt=.*/Prompt=lts/" "$release_config"
                            target_version="$lts_target"
                            info "LTS upgrade target: ${target_version}"
                        else
                            sudo sed -i "s/^Prompt=.*/Prompt=normal/" "$release_config"
                        fi
                    fi
                fi

                unset -f _probe_lts_target _probe_normal_target
            fi

            # do-release-upgrade requires all pending updates to be installed first
            # Use dist-upgrade (not upgrade) so new kernel packages etc. are included
            info "Installing all pending updates before distribution upgrade..."
            sudo apt-get dist-upgrade -y || {
                error "Failed to install pending updates. Cannot proceed with distribution upgrade."
                # Restore prompt setting before returning
                if [[ -n "$original_prompt" && -f "$release_config" ]]; then
                    sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
                fi
                return 1
            }

            # do-release-upgrade also requires a reboot if the kernel was updated
            if [[ -f /var/run/reboot-required ]]; then
                warn "A reboot is required before the distribution upgrade can proceed."
                warn "Please reboot the system and re-run this script to continue the upgrade to ${target_version}."
                # Restore prompt setting before returning
                if [[ -n "$original_prompt" && -f "$release_config" ]]; then
                    sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
                fi
                return 1
            fi

            # I-4: Run upgrade and always restore prompt setting afterward
            info "Starting distribution upgrade to ${target_version}..."
            local rc=0
            sudo do-release-upgrade || rc=$?

            # Always restore original prompt setting
            if [[ -n "$original_prompt" && -f "$release_config" ]]; then
                sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
            fi

            if (( rc == 0 )); then
                # Report the actual version the system was upgraded to
                local actual_version=""
                if [[ -f /etc/os-release ]]; then
                    actual_version=$(. /etc/os-release && echo "$VERSION_ID")
                fi
                info "Distribution upgrade to ${actual_version:-${target_version}} completed successfully."
                return 0
            else
                error "Distribution upgrade to ${target_version} failed."
                return 1
            fi
            ;;
        fedora)
            # Install all pending updates first — required before system-upgrade
            info "Installing all pending updates before Fedora upgrade..."
            sudo dnf upgrade --refresh -y || {
                error "Failed to install pending updates. Cannot proceed with Fedora upgrade."
                return 1
            }

            # Check if a reboot is needed before proceeding
            if command -v needs-restarting &>/dev/null && ! needs-restarting -r &>/dev/null; then
                warn "A reboot is required before the Fedora upgrade can proceed."
                warn "Please reboot the system and re-run this script to continue the upgrade to Fedora ${target_version}."
                return 1
            fi

            info "Downloading upgrade packages for Fedora ${target_version}..."
            if sudo dnf system-upgrade download --releasever="$target_version" -y; then
                info "Upgrade packages downloaded for Fedora ${target_version}."
                warn "A reboot is required to apply the upgrade. The system will prompt for reboot after cleanup."
                return 0
            else
                error "Failed to download upgrade packages for Fedora ${target_version}."
                return 1
            fi
            ;;
        opensuse-leap)
            info "Upgrading openSUSE Leap to ${target_version}..."
            # I-1: Escape dots in version for sed regex and scope to baseurl/mirrorlist lines
            # I-2: Back up repo files for rollback on failure
            local current_ver="$DISTRO_VERSION_ID"
            local escaped_current
            escaped_current=$(printf '%s\n' "$current_ver" | sed 's/[.]/\\./g')

            local repo_backup
            repo_backup=$(mktemp -d)
            cp /etc/zypp/repos.d/*.repo "$repo_backup/" 2>/dev/null

            sudo sed -i "/^\(baseurl\|mirrorlist\)/s/${escaped_current}/${target_version}/g" /etc/zypp/repos.d/*.repo 2>/dev/null || {
                error "Failed to update repository URLs."
                rm -rf "$repo_backup"
                return 1
            }
            sudo zypper ref || {
                error "Failed to refresh repositories after URL update. Restoring repo files."
                sudo cp "$repo_backup"/*.repo /etc/zypp/repos.d/
                rm -rf "$repo_backup"
                return 1
            }
            if sudo zypper dup --allow-vendor-change -y; then
                info "openSUSE Leap upgrade to ${target_version} completed."
                rm -rf "$repo_backup"
                return 0
            else
                error "openSUSE Leap upgrade to ${target_version} failed. Restoring repository files."
                sudo cp "$repo_backup"/*.repo /etc/zypp/repos.d/
                rm -rf "$repo_backup"
                warn "Repository files have been restored to the pre-upgrade state."
                warn "However, some packages may have already been upgraded to ${target_version} versions."
                warn "Your system may be in a mixed-version state. Recommended steps:"
                warn "  1. Run: sudo zypper ps   (check for processes using deleted files)"
                warn "  2. Run: sudo zypper dup  (retry the upgrade once the issue is resolved)"
                warn "  3. If the issue persists, consult the openSUSE upgrade guide:"
                warn "     https://en.opensuse.org/SDB:System_upgrade"
                return 1
            fi
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            # Install all pending updates first — leapp requires a fully updated system
            info "Installing all pending updates before RHEL-family upgrade..."
            sudo "$PKG_MGR" upgrade -y || {
                error "Failed to install pending updates. Cannot proceed with upgrade."
                return 1
            }

            # Check if a reboot is needed before proceeding
            if command -v needs-restarting &>/dev/null && ! needs-restarting -r &>/dev/null; then
                warn "A reboot is required before the RHEL-family upgrade can proceed."
                warn "Please reboot the system and re-run this script to continue the upgrade to version ${target_version}."
                return 1
            fi

            # Install leapp if not present
            if ! command -v leapp &>/dev/null; then
                _install_leapp_packages || return 1
            fi

            # Fix common leapp inhibitors before the expensive preupgrade analysis
            local target_major
            target_major=$(echo "$target_version" | cut -d. -f1)
            _leapp_pre_remediate "$target_major"

            # Run full preupgrade analysis (this is the expensive check, done once)
            info "Running leapp preupgrade analysis for version ${target_version}..."
            info "This may take 10-30 minutes..."
            local preupgrade_rc=0
            sudo leapp preupgrade --target "$target_version" || preupgrade_rc=$?

            if (( preupgrade_rc != 0 )); then
                error "Leapp preupgrade found issue(s) that block the upgrade."
                error "Review the report above and resolve all inhibitors."
                error "Full report: /var/log/leapp/leapp-report.txt"
                return 1
            fi

            # Run the actual upgrade
            info "Starting distribution upgrade to version ${target_version}..."
            if sudo leapp upgrade --target "$target_version"; then
                info "Leapp upgrade to version ${target_version} completed."
                warn "The upgrade will finalize on the next reboot."
                warn "The system will reboot into a special upgrade environment."
                return 0
            else
                error "Leapp upgrade to version ${target_version} failed."
                error "Check /var/log/leapp/leapp-report.txt for details."
                return 1
            fi
            ;;
        debian)
            info "Upgrading Debian to ${target_version}..."
            _apt_codename_upgrade "$DISTRO_VERSION_CODENAME" "$target_version" \
                "deb.debian.org security.debian.org" || return 1
            return 0
            ;;
        linuxmint)
            # Install mintupgrade if not present
            if ! command -v mintupgrade &>/dev/null; then
                info "Installing mintupgrade..."
                sudo apt-get install -y mintupgrade 2>/dev/null || {
                    error "Failed to install mintupgrade."
                    return 1
                }
            fi

            info "Starting Linux Mint upgrade to ${target_version} via mintupgrade..."
            if sudo mintupgrade upgrade; then
                info "Linux Mint upgrade to ${target_version} completed."
                return 0
            else
                error "Linux Mint upgrade to ${target_version} failed."
                return 1
            fi
            ;;
        elementary)
            # Read underlying Ubuntu codename
            local elem_old_ubuntu_codename=""
            if [[ -f /etc/os-release ]]; then
                elem_old_ubuntu_codename=$(grep -oP '^UBUNTU_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)
            fi
            if [[ -z "$elem_old_ubuntu_codename" ]]; then
                error "Could not determine underlying Ubuntu codename for Elementary OS."
                return 1
            fi

            # Read Elementary's own codename (VERSION_CODENAME in os-release)
            local elem_old_codename="$DISTRO_VERSION_CODENAME"

            # Determine new Ubuntu codename from meta-release-lts
            local elem_new_ubuntu_codename=""
            local ubuntu_meta
            ubuntu_meta=$(curl -sf --max-time 10 "http://changelogs.ubuntu.com/meta-release-lts" 2>/dev/null) || true
            if [[ -n "$ubuntu_meta" ]]; then
                elem_new_ubuntu_codename=$(echo "$ubuntu_meta" | grep -oP '^Dist: \K\S+' | tail -1)
            fi
            if [[ -z "$elem_new_ubuntu_codename" ]]; then
                error "Could not determine target Ubuntu codename for Elementary OS upgrade."
                return 1
            fi

            info "Upgrading Elementary OS to ${target_version}..."
            info "Underlying Ubuntu: ${elem_old_ubuntu_codename} -> ${elem_new_ubuntu_codename}"

            # Step 1: Swap Ubuntu codenames in Ubuntu repos
            _apt_codename_upgrade "$elem_old_ubuntu_codename" "$elem_new_ubuntu_codename" \
                "archive.ubuntu.com security.ubuntu.com" || return 1

            # Step 2: Swap Elementary codename in Elementary repos
            # Elementary repos use their own codename (e.g., "horus", "jolnir")
            # which differs from the Ubuntu codename. We need to update these too.
            # If the Elementary codename is unknown for the new version, warn and skip.
            if [[ -n "$elem_old_codename" ]]; then
                local elem_new_codename=""
                # Try to discover new Elementary codename from repo metadata
                local elem_repo_info
                elem_repo_info=$(curl -sf --max-time 10 "https://packages.elementary.io/appcenter/dists/" 2>/dev/null) || true
                if [[ -n "$elem_repo_info" ]]; then
                    # Look for a codename that isn't the current one
                    elem_new_codename=$(echo "$elem_repo_info" | grep -oP 'href="\K[a-z]+(?=/")' | grep -v "$elem_old_codename" | tail -1)
                fi
                if [[ -n "$elem_new_codename" && "$elem_new_codename" != "$elem_old_codename" ]]; then
                    info "Updating Elementary codename: ${elem_old_codename} -> ${elem_new_codename}"
                    _apt_codename_upgrade "$elem_old_codename" "$elem_new_codename" \
                        "packages.elementary.io" || warn "Elementary repo codename update failed — may need manual update."
                else
                    warn "Could not determine new Elementary codename. Elementary-specific repos may need manual updating."
                fi
            fi
            return 0
            ;;
        zorin)
            # Read underlying Ubuntu codename
            local zorin_old_ubuntu_codename=""
            if [[ -f /etc/os-release ]]; then
                zorin_old_ubuntu_codename=$(grep -oP '^UBUNTU_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)
            fi
            if [[ -z "$zorin_old_ubuntu_codename" ]]; then
                error "Could not determine underlying Ubuntu codename for Zorin OS."
                return 1
            fi

            # Read Zorin's own codename (VERSION_CODENAME in os-release)
            local zorin_old_codename="$DISTRO_VERSION_CODENAME"

            # Determine new Ubuntu codename from meta-release-lts
            local zorin_new_ubuntu_codename=""
            local zorin_meta
            zorin_meta=$(curl -sf --max-time 10 "http://changelogs.ubuntu.com/meta-release-lts" 2>/dev/null) || true
            if [[ -n "$zorin_meta" ]]; then
                zorin_new_ubuntu_codename=$(echo "$zorin_meta" | grep -oP '^Dist: \K\S+' | tail -1)
            fi
            if [[ -z "$zorin_new_ubuntu_codename" ]]; then
                error "Could not determine target Ubuntu codename for Zorin OS upgrade."
                return 1
            fi

            info "Upgrading Zorin OS to ${target_version}..."
            info "Underlying Ubuntu: ${zorin_old_ubuntu_codename} -> ${zorin_new_ubuntu_codename}"

            # Step 1: Swap Ubuntu codenames in Ubuntu repos
            _apt_codename_upgrade "$zorin_old_ubuntu_codename" "$zorin_new_ubuntu_codename" \
                "archive.ubuntu.com security.ubuntu.com" || return 1

            # Step 2: Swap Zorin codename in Zorin repos
            # Zorin repos may use their own codename distinct from Ubuntu's.
            if [[ -n "$zorin_old_codename" && "$zorin_old_codename" != "$zorin_old_ubuntu_codename" ]]; then
                # Zorin uses a different codename — try to discover the new one
                local zorin_new_codename=""
                local zorin_repo_info
                zorin_repo_info=$(curl -sf --max-time 10 "https://packages.zorinos.com/dists/" 2>/dev/null) || true
                if [[ -n "$zorin_repo_info" ]]; then
                    zorin_new_codename=$(echo "$zorin_repo_info" | grep -oP 'href="\K[a-z]+(?=/")' | grep -v "$zorin_old_codename" | tail -1)
                fi
                if [[ -n "$zorin_new_codename" && "$zorin_new_codename" != "$zorin_old_codename" ]]; then
                    info "Updating Zorin codename: ${zorin_old_codename} -> ${zorin_new_codename}"
                    _apt_codename_upgrade "$zorin_old_codename" "$zorin_new_codename" \
                        "packages.zorinos.com" || warn "Zorin repo codename update failed — may need manual update."
                else
                    warn "Could not determine new Zorin codename. Zorin-specific repos may need manual updating."
                fi
            fi
            return 0
            ;;
        opensuse-tumbleweed|arch|manjaro|endeavouros|garuda|artix|cachyos|kali)
            # Rolling releases have no discrete version upgrades — pkg_check_upgrade_available
            # returns 2 for these distros, so this case should never be reached via the
            # normal upgrade flow. Guard it explicitly to give a clear message if called directly.
            warn "${DISTRO_ID} is a rolling release. There is no discrete version upgrade to perform."
            warn "To update all packages, use the standard system update instead."
            return 1
            ;;
        *)
            # Should never be reached (guarded by pkg_check_upgrade_available)
            error "Distribution upgrade not supported for ${DISTRO_ID}."
            return 1
            ;;
    esac
}

pkg_get_version() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)     dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "unknown" ;;
        dnf|yum|zypper) rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$pkg" 2>/dev/null || echo "unknown" ;;
        pacman)  pacman -Q "$pkg" 2>/dev/null | awk '{print $2}' || echo "unknown" ;;
    esac
}

# --- Helper checks for other utilities ---

has_snap() {
    command -v snap &>/dev/null
}

has_flatpak() {
    command -v flatpak &>/dev/null
}

# Returns 0 if a Flatpak app matching the given ID (or grep pattern) is installed.
flatpak_is_installed() {
    has_flatpak && flatpak list 2>/dev/null | grep -qi "$1"
}

# Standard 3-way installation check used by most simple installers.
# Usage: _check_standard binary pkg flatpak_id
#   binary     — command name to test with "command -v"; pass "" to skip
#   pkg        — package name for pkg_check_installed; pass "" to skip
#   flatpak_id — Flatpak application ID for "flatpak list | grep -qi"; pass "" to skip
_check_standard() {
    local binary="$1" pkg="$2" flatpak_id="$3"
    [[ -n "$binary"     ]] && command -v "$binary" &>/dev/null && return 0
    [[ -n "$pkg"        ]] && pkg_check_installed "$pkg"       && return 0
    [[ -n "$flatpak_id" ]] && has_flatpak && flatpak list 2>/dev/null | grep -qi "$flatpak_id" && return 0
    return 1
}

# ─── Version helpers (used by get_version_XXX in installer scripts) ──────────

# Extract the first X.Y.Z semver from a binary's version output.
# Pass a subcommand as the second arg when the binary uses one (e.g. "version")
# instead of the standard --version flag.
# Usage: _ver_from_cmd binary [flag]
_ver_from_cmd() {
    local _cmd="$1" _flag="${2:---version}" v
    command -v "$_cmd" &>/dev/null || return 1
    v=$("$_cmd" "$_flag" 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ -n "$v" ]] && printf '%s\n' "$v" || return 1
}

# Get the version string from the package manager and strip epoch prefix and
# distro suffix so "1:3.5.7-2ubuntu1" becomes "3.5.7".
# Returns 1 (and prints nothing) when the package is not installed.
# Usage: _ver_from_pkg pkg_name
_ver_from_pkg() {
    local v
    v=$(pkg_get_version "$1" 2>/dev/null | sed 's/^[0-9]*://; s/-.*//') || return 1
    [[ -z "$v" || "$v" == "unknown" ]] && return 1
    printf '%s\n' "$v"
}

# Get the version of an installed Flatpak by application ID substring (case-insensitive).
# Returns 1 (and prints nothing) when the app is not installed.
# Usage: _ver_from_flatpak flatpak_id
_ver_from_flatpak() {
    has_flatpak || return 1
    local v
    v=$(flatpak list 2>/dev/null | grep -i "$1" | awk -F'\t' '{print $3}' | head -1)
    [[ -n "$v" ]] && printf '%s\n' "$v" || return 1
}

# Get the version of an installed snap package.
# Returns 1 (and prints nothing) when the package is not installed.
# Usage: _ver_from_snap pkg_name
_ver_from_snap() {
    has_snap || return 1
    local v
    v=$(snap list "$1" 2>/dev/null | awk 'NR==2{print $2}')
    [[ -n "$v" ]] && printf '%s\n' "$v" || return 1
}

# ============================================================================
# APT REPOSITORY HELPER
# ============================================================================

# Add an APT repository with a GPG keyring.
# Usage: _add_apt_repo KEY_URL KEYRING_PATH SOURCES_LINE SOURCES_LIST_PATH
#   KEY_URL          — URL to the GPG public key
#                      .asc / .pub / .key  → piped through gpg --dearmor
#                      .gpg                → downloaded as-is (already binary)
#   KEYRING_PATH     — full destination path for the keyring (sudo-created)
#   SOURCES_LINE     — complete "deb [signed-by=...] ..." line
#   SOURCES_LIST_PATH — full path of the .list file under /etc/apt/sources.list.d/
# Runs "sudo apt update" after writing the repo.
_add_apt_repo() {
    local key_url="$1"
    local keyring_path="$2"
    local sources_line="$3"
    local sources_list_path="$4"

    sudo install -d -m 0755 "$(dirname "$keyring_path")"

    # Download to a user-owned temp file (no sudo — public key, no auth needed).
    # Detect ASCII-armored vs binary regardless of URL file extension.
    local _tmpkey
    _tmpkey=$(mktemp)
    if ! curl -fsSL "$key_url" -o "$_tmpkey"; then
        rm -f "$_tmpkey"
        error "Failed to download GPG key from: $key_url"
        return 1
    fi
    if grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$_tmpkey" 2>/dev/null; then
        gpg --dearmor < "$_tmpkey" | sudo tee "$keyring_path" > /dev/null
    else
        sudo install -m 0644 "$_tmpkey" "$keyring_path"
    fi
    rm -f "$_tmpkey"
    sudo chmod go+r "$keyring_path"

    echo "$sources_line" | sudo tee "$sources_list_path" > /dev/null
    sudo apt update
}

# Ensure required tools are installed (gnupg, curl, wget)
ensure_tools() {
    case "$PKG_MGR" in
        apt)
            # Check if gnupg, curl, and wget are installed
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                info "Installing required tools (gnupg, curl, wget)..."
                sudo apt-get update -qq
                sudo apt-get install -y gnupg curl wget 2>/dev/null || true
            fi
            ;;
        dnf|yum)
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                sudo "$PKG_MGR" install -y gnupg2 curl wget 2>/dev/null || true
            fi
            ;;
        pacman)
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                info "Installing required tools (gnupg, curl, wget)..."
                sudo pacman -S --noconfirm --needed gnupg curl wget 2>/dev/null || true
            fi
            ;;
        zypper)
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                sudo zypper install -y gpg2 curl wget 2>/dev/null || true
            fi
            ;;
    esac
}

# Check for internet connectivity; warns but does not abort (best-effort).
check_internet() {
    if ! { curl -fsS --max-time 5 https://1.1.1.1 || ping -c1 -W3 8.8.8.8; } &>/dev/null; then
        warn "Internet connectivity check failed. Downloads may not work."
        return 1
    fi
    return 0
}

# download_file <url> <dest> [retries=3]
# Robust download with retries; prefers wget, falls back to curl.
# After downloading, call verify_download() from lib/verify.sh to check the
# file is non-empty, not an HTML error page, and has the expected magic bytes.
# For GitHub releases that provide a checksums asset, also call
# github_verify_checksum() to validate the SHA256 hash.
download_file() {
    local url="$1" dest="$2" retries="${3:-3}" attempt=1
    while (( attempt <= retries )); do
        if command -v wget &>/dev/null; then
            wget -q --timeout=30 -O "$dest" "$url" && return 0
        else
            curl -fsSL --max-time 30 --retry 2 -o "$dest" "$url" && return 0
        fi
        warn "Download attempt $attempt/$retries failed: $(basename "$url")"
        (( attempt++ ))
        (( attempt <= retries )) && sleep $(( 2 ** (attempt - 1) ))
    done
    error "Failed to download after $retries attempts: $url"
    return 1
}

# Returns a hash of the current installed-package state.
# Used to detect whether updates actually changed anything.
pkg_snapshot() {
    case "$PKG_MGR" in
        apt)     dpkg -l 2>/dev/null | md5sum | awk '{print $1}' ;;
        dnf|yum) rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null | sort | md5sum | awk '{print $1}' ;;
        pacman)  pacman -Q 2>/dev/null | md5sum | awk '{print $1}' ;;
        zypper)  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null | sort | md5sum | awk '{print $1}' ;;
    esac
}
