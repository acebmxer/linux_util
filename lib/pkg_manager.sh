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
    else
        echo "Error: Cannot detect Linux distribution (/etc/os-release not found)."
        exit 1
    fi

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
        arch|manjaro|endeavouros|garuda|artix)
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

    echo "Detected: ${DISTRO_NAME} (family: ${DISTRO_FAMILY}, package manager: ${PKG_MGR})"
    log_info "System detected: ${DISTRO_NAME} (family: ${DISTRO_FAMILY}, package manager: ${PKG_MGR})"
}

# --- Package Manager Wrappers ---

pkg_refresh() {
    case "$PKG_MGR" in
        apt)     sudo apt update ;;
        dnf|yum) sudo "$PKG_MGR" makecache ;;
        # NOTE: On Arch, -Sy without -u risks partial upgrades. We use -Syu
        # here so that any subsequent pkg_install calls have a consistent DB+system.
        pacman)  sudo pacman -Syu --noconfirm ;;
        zypper)  sudo zypper refresh ;;
    esac
}

pkg_install() {
    case "$PKG_MGR" in
        apt)     sudo apt install -y "$@" ;;
        dnf|yum) sudo "$PKG_MGR" install -y "$@" ;;
        pacman)  sudo pacman -S --noconfirm "$@" ;;
        zypper)  sudo zypper install -y "$@" ;;
    esac
}

pkg_remove() {
    case "$PKG_MGR" in
        apt)     sudo apt remove -y "$@" ;;
        dnf|yum) sudo "$PKG_MGR" remove -y "$@" ;;
        pacman)  sudo pacman -Rs --noconfirm "$@" ;;
        zypper)  sudo zypper remove -y "$@" ;;
    esac
}

pkg_upgrade() {
    case "$PKG_MGR" in
        apt)     sudo apt update && sudo apt upgrade -y "$@" ;;
        dnf|yum) sudo "$PKG_MGR" upgrade -y "$@" ;;
        pacman)  sudo pacman -S --noconfirm "$@" ;;
        zypper)  sudo zypper update -y "$@" ;;
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
    case "$PKG_MGR" in
        apt)     sudo apt install -y "$1" ;;
        dnf|yum) sudo "$PKG_MGR" install -y "$1" ;;
        pacman)  sudo pacman -U --noconfirm "$1" ;;
        zypper)  sudo zypper install -y --allow-unsigned-rpm "$1" ;;
    esac
}

pkg_autoremove() {
    case "$PKG_MGR" in
        apt)     sudo apt autoremove -y ;;
        dnf|yum) sudo "$PKG_MGR" autoremove -y ;;
        pacman)  pacman -Qdtq 2>/dev/null | sudo pacman -Rs --noconfirm - 2>/dev/null || true ;;
        zypper)  true ;;
    esac
}

pkg_full_upgrade() {
    case "$PKG_MGR" in
        apt)     sudo apt full-upgrade -y ;;
        dnf|yum) sudo "$PKG_MGR" upgrade -y ;;
        pacman)  sudo pacman -Syu --noconfirm ;;
        zypper)  sudo zypper update -y ;;
    esac
}

pkg_clean() {
    case "$PKG_MGR" in
        apt)     sudo apt clean && sudo apt autoclean ;;
        dnf|yum) sudo "$PKG_MGR" clean all ;;
        pacman)  sudo pacman -Sc --noconfirm ;;
        zypper)  sudo zypper clean -a ;;
    esac
}

# Thorough cleanup: autoremove, old kernels, purge configs, clean cache
pkg_cleanup_thorough() {
    info "Running thorough system cleanup..."

    # Step 1: Remove orphaned dependencies
    pkg_autoremove

    # Step 2: Remove old kernels (keep current + one previous)
    local current_kernel
    current_kernel=$(uname -r)
    info "Current kernel: ${current_kernel} (will be preserved)"

    case "$PKG_MGR" in
        apt)
            # List installed kernels, exclude current and latest, purge the rest
            local kernels_to_remove=""
            local installed_kernels
            installed_kernels=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii.*linux-image-[0-9]/ {print $2}' | sort -V)
            if [[ -n "$installed_kernels" ]]; then
                # Keep the two newest and the currently running kernel
                local keep_count=2
                local total
                total=$(echo "$installed_kernels" | wc -l)
                if (( total > keep_count )); then
                    kernels_to_remove=$(echo "$installed_kernels" | head -n -${keep_count} | grep -Fv "$current_kernel" || true)
                fi
            fi
            if [[ -n "$kernels_to_remove" ]]; then
                info "Removing old kernels: $(echo "$kernels_to_remove" | tr '\n' ' ')"
                # Also remove matching headers
                local headers_to_remove=""
                for kern in $kernels_to_remove; do
                    local ver
                    ver=$(echo "$kern" | sed 's/linux-image-\(unsigned-\)\?//')
                    if dpkg -l "linux-headers-${ver}" 2>/dev/null | grep -q "^ii"; then
                        headers_to_remove+="linux-headers-${ver} "
                    fi
                done
                # shellcheck disable=SC2086
                sudo apt-get purge -y $kernels_to_remove $headers_to_remove 2>/dev/null || true
            else
                info "No old kernels to remove."
            fi
            ;;
        dnf|yum)
            sudo "$PKG_MGR" remove -y --oldinstallonly --setopt installonly_limit=2 2>/dev/null || true
            ;;
        pacman)
            # Arch doesn't accumulate old kernels the same way; skip
            ;;
        zypper)
            sudo zypper purge-kernels --keep 2 2>/dev/null || true
            ;;
    esac

    # Step 3: Purge removed package configs (Debian family only)
    if [[ "$PKG_MGR" == "apt" ]]; then
        local rc_packages
        rc_packages=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')
        if [[ -n "$rc_packages" ]]; then
            info "Purging removed package configs..."
            # shellcheck disable=SC2086
            sudo dpkg --purge $rc_packages 2>/dev/null || true
        fi
    fi

    # Step 4: Clean package cache
    pkg_clean

    # Step 5: Clean apt lists partial files (Debian family only)
    if [[ "$PKG_MGR" == "apt" ]]; then
        sudo rm -f /var/lib/apt/lists/partial/* 2>/dev/null || true
    fi

    info "System cleanup completed."
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

    # Step 1: Create persistent backup directory
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

    # Step 2: Check for held packages
    local held_packages
    held_packages=$(apt-mark showhold 2>/dev/null)
    if [[ -n "$held_packages" ]]; then
        warn "The following packages are held and may block the upgrade:"
        echo "$held_packages"
        echo ""
        local hold_confirm=""
        read -rp "Continue with held packages? (y/N): " hold_confirm
        if [[ ! "$hold_confirm" =~ ^[Yy]$ ]]; then
            info "Upgrade aborted due to held packages."
            sudo rm -rf "$backup_dir"
            return 1
        fi
    fi

    # Step 3: Build a grep pattern to match official mirror URLs
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

    # Step 4: Swap codenames in traditional .list files
    # Only replace on deb/deb-src lines that ALSO contain an official mirror URL.
    # This prevents modifying third-party repo lines in the same file.
    local sources_file
    local skipped_repos=false
    if [[ -f /etc/apt/sources.list ]]; then
        info "Updating codename in /etc/apt/sources.list..."
        sudo sed -i "/^[[:space:]]*deb\(-src\)\?[[:space:]].*\(${mirror_sed_pattern}\)/s/\b${old_codename}\b/${new_codename}/g" /etc/apt/sources.list
    fi
    for sources_file in /etc/apt/sources.list.d/*.list; do
        [[ -f "$sources_file" ]] || continue
        if grep -qE "(${mirror_grep_pattern})" "$sources_file" 2>/dev/null; then
            info "Updating codename in $(basename "$sources_file")..."
            sudo sed -i "/^[[:space:]]*deb\(-src\)\?[[:space:]].*\(${mirror_sed_pattern}\)/s/\b${old_codename}\b/${new_codename}/g" "$sources_file"
        else
            verbose "Skipping third-party repo: $(basename "$sources_file")"
            skipped_repos=true
        fi
    done

    # Step 5: Swap codenames in DEB822 .sources files (Suites: lines only)
    # DEB822 files group URIs and Suites in the same stanza, so we check
    # if the file contains an official mirror and only then swap Suites.
    for sources_file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$sources_file" ]] || continue
        if grep -qE "(${mirror_grep_pattern})" "$sources_file" 2>/dev/null; then
            info "Updating codename in $(basename "$sources_file") (DEB822)..."
            sudo sed -i "/^Suites:/s/\b${old_codename}\b/${new_codename}/g" "$sources_file"
        else
            verbose "Skipping third-party repo: $(basename "$sources_file")"
            skipped_repos=true
        fi
    done

    if [[ "$skipped_repos" == "true" ]]; then
        warn "Third-party repositories were not modified. They may need manual updating for the new release."
    fi

    # Step 6: Run apt-get update (apt-get is more stable for scripted use)
    info "Refreshing package lists for ${new_codename}..."
    if ! sudo apt-get update; then
        error "apt-get update failed after codename swap. Restoring sources..."
        _apt_codename_upgrade_restore "$backup_dir"
        return 1
    fi

    # Step 7: Run apt-get dist-upgrade (standard for major version upgrades)
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

# Check if a distribution version upgrade is available.
# Returns 0 if available (outputs target version to stdout), 1 if not.
# Dispatches on DISTRO_ID since upgrade paths are distro-specific.
pkg_check_upgrade_available() {
    case "$DISTRO_ID" in
        ubuntu|kubuntu|pop|neon)
            # Ensure do-release-upgrade is available
            if ! command -v do-release-upgrade &>/dev/null; then
                info "Installing update-manager-core for upgrade checks..."
                sudo apt-get install -y update-manager-core 2>/dev/null || {
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
            # Rolling release — no discrete version upgrades
            return 1
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            # CentOS Stream is rolling — no discrete version upgrades
            if [[ -f /etc/centos-release ]] && grep -qi "stream" /etc/centos-release 2>/dev/null; then
                return 1
            fi

            # Install leapp if not present
            if ! command -v leapp &>/dev/null; then
                info "Installing leapp for upgrade checks..."
                sudo "$PKG_MGR" install -y leapp leapp-upgrade 2>/dev/null || {
                    warn "Could not install leapp"
                    return 1
                }
            fi

            # Target is next major version
            local current_major
            current_major=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
            local target_major=$(( current_major + 1 ))

            # Lightweight check only — full preupgrade is deferred to
            # pkg_distro_upgrade since it takes 10-30 minutes.
            # Just verify leapp is installed and the target is a reasonable version.
            if command -v leapp &>/dev/null && (( target_major >= 8 && target_major <= 11 )); then
                echo "$target_major"
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
                info "Installing mintupgrade for upgrade checks..."
                sudo apt-get install -y mintupgrade 2>/dev/null || {
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
        elementary|zorin)
            # Handled in subsequent steps
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
                # Only check for ubuntu proper — kubuntu/pop/neon may not follow same LTS scheme
                local is_lts=false
                if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                    local year month
                    year=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
                    month=$(echo "$DISTRO_VERSION_ID" | cut -d. -f2)
                    if (( month == 4 && year % 2 == 0 )); then
                        is_lts=true
                    fi
                fi

                if [[ "$is_lts" == "true" ]]; then
                    echo ""
                    echo "You are currently on an LTS release (${DISTRO_NAME} ${DISTRO_VERSION_ID})."
                    echo ""
                    echo "  1) Stay on LTS track (upgrade only to next LTS release)"
                    echo "  2) Upgrade to latest release (including non-LTS)"
                    echo ""
                    local lts_choice=""
                    while [[ "$lts_choice" != "1" && "$lts_choice" != "2" ]]; do
                        read -rp "Choose [1/2]: " lts_choice
                    done

                    if [[ "$lts_choice" == "1" ]]; then
                        sudo sed -i "s/^Prompt=.*/Prompt=lts/" "$release_config"
                    else
                        sudo sed -i "s/^Prompt=.*/Prompt=normal/" "$release_config"
                    fi
                fi
            fi

            # I-4: Run upgrade and always restore prompt setting afterward
            info "Starting distribution upgrade to ${target_version}..."
            local rc=0
            sudo do-release-upgrade -f DistUpgradeViewNonInteractive || rc=$?

            # Always restore original prompt setting
            if [[ -n "$original_prompt" && -f "$release_config" ]]; then
                sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
            fi

            if (( rc == 0 )); then
                info "Distribution upgrade to ${target_version} completed successfully."
                return 0
            else
                error "Distribution upgrade to ${target_version} failed."
                return 1
            fi
            ;;
        fedora)
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
                return 1
            fi
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            # Install leapp if not present
            if ! command -v leapp &>/dev/null; then
                info "Installing leapp and leapp-upgrade..."
                sudo "$PKG_MGR" install -y leapp leapp-upgrade 2>/dev/null || {
                    error "Failed to install leapp. Cannot proceed with upgrade."
                    return 1
                }
            fi

            # Run full preupgrade analysis (this is the expensive check, done once)
            info "Running leapp preupgrade analysis for version ${target_version}..."
            info "This may take 10-30 minutes..."
            local preupgrade_output
            local preupgrade_rc=0
            preupgrade_output=$(sudo leapp preupgrade --target "$target_version" 2>&1) || preupgrade_rc=$?

            # Check for critical inhibitors via the structured report
            if [[ -f /var/log/leapp/leapp-report.json ]]; then
                local inhibitor_count
                inhibitor_count=$(grep -c '"risk factor": "high"' /var/log/leapp/leapp-report.json 2>/dev/null || echo "0")
                if (( inhibitor_count > 0 )); then
                    error "Leapp preupgrade found ${inhibitor_count} high-risk inhibitor(s)."
                    echo ""
                    # Show summary from text report
                    grep -B1 -A3 "Risk Factor: high" /var/log/leapp/leapp-report.txt 2>/dev/null || \
                        echo "$preupgrade_output" | grep -A2 -i "inhibitor"
                    echo ""
                    error "Resolve the above inhibitors before attempting the upgrade."
                    error "Full report: /var/log/leapp/leapp-report.txt"
                    return 1
                fi
            elif echo "$preupgrade_output" | grep -qi "inhibitor"; then
                # Fallback if structured report not available
                error "Leapp preupgrade found inhibitors:"
                echo ""
                echo "$preupgrade_output" | grep -A2 -i "inhibitor"
                echo ""
                error "Full report: /var/log/leapp/leapp-report.txt"
                return 1
            fi

            if (( preupgrade_rc != 0 )); then
                error "Leapp preupgrade failed (exit code: ${preupgrade_rc})."
                error "Check /var/log/leapp/leapp-report.txt for details."
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
# NOTE: Checksum verification is not implemented because download URLs
# change frequently and upstream projects do not consistently provide
# checksum files at predictable URLs. If a utility provides a .sha256
# file alongside its download, verify it in the individual install function.
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
        (( attempt <= retries )) && sleep 2
    done
    error "Failed to download after $retries attempts: $url"
    return 1
}
