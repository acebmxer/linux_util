#!/bin/bash

# ============================================================================
# Linux Utilities - System Module
# Provides system detection, setup functions, and NVIDIA driver utilities
# ============================================================================

# Helper functions for system setup
# NOTE: run_as_root passes its arguments as a single string to sh -c.
# Arguments containing spaces, quotes, or special characters will be
# subject to word-splitting by sh. For commands with complex quoting,
# use 'sudo bash -c "..."' directly instead of this helper.
run_as_root() { sudo -E sh -c "$*"; }
info()  { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
error() { printf '\e[31m[ERROR]\e[0m %s\n' "$*" >&2; }

# --- System Update Options ---

# Full system update and upgrade (bare metal)
setup_full_update_bare_metal() {
    info "Starting full system update and upgrade (bare metal)..."

    # Install basic tools
    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            # Install core packages first
            run_as_root "apt-get install -y --no-install-recommends jq tzdata git curl wget gnupg"
            # Install software-properties-common only on Ubuntu
            if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "linuxmint" ]] || [[ "$DISTRO_ID" == "pop" ]]; then
                run_as_root "apt-get install -y --no-install-recommends software-properties-common"
            fi
            ;;
        dnf|yum)
            run_as_root "$PKG_MGR install -y jq git curl wget util-linux-user"
            ;;
        pacman)
            run_as_root "pacman -S --noconfirm --needed jq git curl wget"
            ;;
        zypper)
            run_as_root "zypper install -y jq git curl wget"
            ;;
        *)
            run_as_root "$PKG_MGR install -y jq git curl wget"
            ;;
    esac

    # Backup GNOME keyring before upgrade to prevent credentials being wiped
    # if gnome-keyring or libsecret is upgraded and restarts the daemon mid-session.
    local keyring_dir="${HOME}/.local/share/keyrings"
    local keyring_backup=""
    if [[ -d "$keyring_dir" ]] && [[ -n "$(ls -A "$keyring_dir" 2>/dev/null)" ]]; then
        keyring_backup=$(mktemp -d)
        CLEANUP_FILES+=("$keyring_backup")
        cp -a "$keyring_dir/." "$keyring_backup/"
        info "Keyring backed up to ${keyring_backup}"
    fi

    # Full system upgrade
    pkg_full_upgrade
    pkg_autoremove
    pkg_clean

    # Restore keyring if the upgrade caused any keyring files to change
    if [[ -n "$keyring_backup" ]]; then
        local restored=false
        for backed_up_file in "$keyring_backup"/*; do
            local filename
            filename=$(basename "$backed_up_file")
            local live_file="${keyring_dir}/${filename}"
            # Restore if the live file is missing or smaller than the backup
            # (upgrade reset it to an empty/new keyring)
            if [[ ! -f "$live_file" ]] || \
               [[ $(stat -c%s "$backed_up_file") -gt $(stat -c%s "$live_file") ]]; then
                mkdir -p "$keyring_dir"
                cp -a "$backed_up_file" "$live_file"
                restored=true
                info "Restored keyring file: ${filename}"
            fi
        done
        if [[ "$restored" == "true" ]]; then
            info "Keyring restored. Restarting gnome-keyring daemon..."
            pkill -u "$USER" gnome-keyring-daemon 2>/dev/null || true
            sleep 1
        fi
        rm -rf "$keyring_backup"
    fi

    info "System has been fully updated and upgraded."
    return 0
}

# Install/Update XEN Guest Utilities
setup_xen_guest_utilities() {
    info "Installing/Updating XEN Guest Utilities..."

    # CentOS / Fedora: install from EPEL repository
    if [[ "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "fedora" ]]; then
        info "Installing xe-guest-utilities-latest via yum (EPEL)..."
        run_as_root "yum install -y xe-guest-utilities-latest" || { error "Failed to install xe-guest-utilities-latest"; return 1; }
        info "Enabling and starting xe-linux-distribution service..."
        run_as_root "systemctl enable xe-linux-distribution" || warn "Failed to enable xe-linux-distribution"
        run_as_root "systemctl start xe-linux-distribution" || warn "Failed to start xe-linux-distribution"
        info "XEN Guest Utilities installation completed."
        return 0
    fi

    # Debian-based systems: install from debian-backports, or build from source
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "Installing xe-guest-utilities via apt..."
        run_as_root "apt-get install -y --no-install-recommends xe-guest-utilities" || {
            warn "xe-guest-utilities unavailable from repositories. Attempting manual install from source..."
            local build_dir
            build_dir=$(mktemp -d)
            CLEANUP_FILES+=("$build_dir")
            cd "$build_dir" || return 1
            run_as_root "apt-get install -y build-essential python3-dev" || return 1
            git clone https://github.com/xenserver/xe-guest-utilities.git "$build_dir/xe-guest-utilities" || {
                error "Failed to clone xe-guest-utilities repository."
                return 1
            }
            cd "$build_dir/xe-guest-utilities" || return 1
            run_as_root "python3 setup.py install" || {
                error "Failed to install xe-guest-utilities from source."
                return 1
            }
        }
        info "Enabling and starting xen-guest-utils service..."
        run_as_root "systemctl enable xen-guest-utils" 2>/dev/null || warn "Failed to enable xen-guest-utils"
        run_as_root "systemctl start xen-guest-utils" 2>/dev/null || warn "Failed to start xen-guest-utils"
        info "XEN Guest Utilities installation completed."
        return 0
    fi

    # Arch-based: install from AUR
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        info "Installing xe-guest-utilities-new from AUR..."
        if has_aur_helper; then
            aur_install xe-guest-utilities-new || {
                error "Failed to install xe-guest-utilities-new from AUR."
                return 1
            }
        else
            warn "No AUR helper found. Please install yay or paru, then install xe-guest-utilities-new manually."
            return 1
        fi
        info "Enabling and starting xen-guest-utils service..."
        run_as_root "systemctl enable xen-guest-utils" 2>/dev/null || warn "Failed to enable xen-guest-utils"
        run_as_root "systemctl start xen-guest-utils" 2>/dev/null || warn "Failed to start xen-guest-utils"
        info "XEN Guest Utilities installation completed."
        return 0
    fi

    info "XEN Guest Utilities installation completed."
    return 0
}

# System updates only
setup_system_updates() {
    info "Running system updates..."
    pkg_full_upgrade
    pkg_autoremove
    pkg_clean
    info "System updates completed."
    return 0
}

# Detect and export the desktop environment for AppImage installers (Joplin, etc.)
detect_and_export_desktop_env() {
    local desktop_env=""
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        desktop_env="$XDG_CURRENT_DESKTOP"
    elif command -v plasmashell &>/dev/null; then
        desktop_env="KDE"
    elif command -v gnome-shell &>/dev/null; then
        desktop_env="GNOME"
    elif command -v xfce4-session &>/dev/null; then
        desktop_env="XFCE"
    elif command -v cinnamon &>/dev/null; then
        desktop_env="X-Cinnamon"
    fi
    if [[ -n "$desktop_env" ]]; then
        export XDG_CURRENT_DESKTOP="$desktop_env"
    fi
}

# Helper function to detect mixed repository issues
detect_debian_repo_mix() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi

    local has_stable=false
    local has_testing=false
    local has_unstable=false

    # Check for different Debian releases in sources.list
    if grep -qE "^deb .*(bookworm|bullseye|buster)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_stable=true
    fi
    if grep -qE "^deb .*(trixie|testing)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_testing=true
    fi
    if grep -qE "^deb .*(sid|unstable)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_unstable=true
    fi

    local mix_count=0
    $has_stable && ((mix_count++))
    $has_testing && ((mix_count++))
    $has_unstable && ((mix_count++))

    if [[ $mix_count -gt 1 ]]; then
        echo "⚠️  WARNING: Mixed Debian repositories detected!"
        echo "Your system has multiple Debian releases configured:"
        $has_stable && echo "  - Stable (Bookworm/Bullseye)"
        $has_testing && echo "  - Testing (Trixie)"
        $has_unstable && echo "  - Unstable (Sid)"
        echo "This can cause package version conflicts and dependency issues."
        echo "Consider using a single Debian release for better stability."
        echo ""
        return 1
    fi
    return 0
}

# --- NVIDIA Driver Functions ---

# Save the selected NVIDIA driver version to a persistent config file so that
# other installers (e.g. Steam) can reference it later.
save_nvidia_driver_version() {
    local version="$1"
    mkdir -p "$(dirname "$NVIDIA_VERSION_FILE")"
    echo "$version" > "$NVIDIA_VERSION_FILE"
}

# Return the saved NVIDIA driver version, falling back to package detection.
get_nvidia_installed_version() {
    if [[ -f "$NVIDIA_VERSION_FILE" ]]; then
        cat "$NVIDIA_VERSION_FILE"
        return 0
    fi
    # Fallback: detect from installed packages
    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l 'nvidia-driver-*' 2>/dev/null | grep '^ii' | \
                grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- Local MOTD Setup ---

setup_local_motd() {
    info "Installing/Updating Landscape Client and configuring Local MOTD..."

    # Install landscape-client
    run_as_root "add-apt-repository -y ppa:landscape/self-hosted-beta 2>/dev/null || true"
    run_as_root "apt-get update && apt-get install -y --no-install-recommends landscape-client" || {
        warn "Failed to install landscape-client"
        return 1
    }

    # Add MOTD display code to shell config files
    local motd_code='# Display MOTD for ZSH
if [ -f /etc/update-motd.d/00-header ]; then
    /etc/update-motd.d/00-header
fi
if [ -f /etc/update-motd.d/10-help-text ]; then
    /etc/update-motd.d/10-help-text
fi
if [ -f /etc/update-motd.d/50-motd-news ]; then
    /etc/update-motd.d/50-motd-news
fi
if [ -f /etc/update-motd.d/85-fwupd ]; then
    /etc/update-motd.d/85-fwupd
fi
if [ -f /etc/update-motd.d/90-updates-available ]; then
    /etc/update-motd.d/90-updates-available
fi
if [ -f /etc/update-motd.d/91-contract-ua-esm-status ]; then
    /etc/update-motd.d/91-contract-ua-esm-status
fi
if [ -f /etc/update-motd.d/91-release-upgrade ]; then
    /etc/update-motd.d/91-release-upgrade
fi
if [ -f /etc/update-motd.d/95-hwe-eol ]; then
    /etc/update-motd.d/95-hwe-eol
fi
if [ -f /etc/update-motd.d/98-fsck-at-reboot ]; then
    /etc/update-motd.d/98-fsck-at-reboot
fi
if [ -f /etc/update-motd.d/98-reboot-required ]; then
    /etc/update-motd.d/98-reboot-required
fi'

    # Add to ~/.bashrc
    if [[ -f "${HOME}/.bashrc" ]]; then
        if ! grep -q "Display MOTD for ZSH" "${HOME}/.bashrc"; then
            echo "" >> "${HOME}/.bashrc"
            echo "$motd_code" >> "${HOME}/.bashrc"
            info "Added MOTD display code to ~/.bashrc"
            source "${HOME}/.bashrc"
        else
            info "MOTD code already present in ~/.bashrc"
        fi
    fi

    # Add to ~/.zshrc if it exists
    if [[ -f "${HOME}/.zshrc" ]]; then
        if ! grep -q "Display MOTD for ZSH" "${HOME}/.zshrc"; then
            echo "" >> "${HOME}/.zshrc"
            echo "$motd_code" >> "${HOME}/.zshrc"
            info "Added MOTD display code to ~/.zshrc"
            source "${HOME}/.zshrc"
        else
            info "MOTD code already present in ~/.zshrc"
        fi
    fi

    info "Local MOTD configuration complete."
}
