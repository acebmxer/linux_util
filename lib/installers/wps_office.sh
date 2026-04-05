#!/bin/bash
# WPS Office installer functions
# Official download: https://linux.wps.com/

# --- WPS Office ---

check_wps_office() { _check_standard wps wps-office com.wps.Office; }

# Download and install WPS Office .deb or .rpm directly from linux.wps.com.
# Usage: _wps_install_from_site <deb|rpm>
_wps_install_from_site() {
    local pkg_type="$1"  # "deb" or "rpm"
    ensure_tools
    local arch_str
    case "$(uname -m)" in
        x86_64)  arch_str="amd64" ;;
        aarch64) arch_str="arm64" ;;
        *)
            echo "Error: Unsupported architecture $(uname -m) for WPS Office direct download."
            return 1
            ;;
    esac

    # Scrape the download page for the latest package URL
    local download_url
    download_url=$(curl -fsSL "https://linux.wps.com/" | \
        grep -oP "https://[^\"']+_${arch_str}\.${pkg_type}" | head -1)

    if [[ -z "$download_url" ]]; then
        echo "Error: Could not determine WPS Office download URL from linux.wps.com."
        return 1
    fi

    local tmp_dir pkg_file
    tmp_dir=$(mktemp -d /tmp/wps-office-install-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")
    pkg_file="${tmp_dir}/wps-office.${pkg_type}"

    echo "Downloading WPS Office from ${download_url}..."
    if ! wget -q --show-progress -O "$pkg_file" "$download_url"; then
        echo "Error: Failed to download WPS Office."
        rm -rf "$tmp_dir"
        return 1
    fi

    echo "Installing WPS Office..."
    case "$pkg_type" in
        deb)
            if ! sudo dpkg -i "$pkg_file"; then
                sudo apt-get install -f -y || true
                sudo dpkg -i "$pkg_file" || { rm -rf "$tmp_dir"; return 1; }
            fi
            ;;
        rpm)
            sudo "$PKG_MGR" localinstall -y "$pkg_file" || \
                sudo rpm -i --replacefiles "$pkg_file" || { rm -rf "$tmp_dir"; return 1; }
            ;;
    esac

    rm -rf "$tmp_dir"
    echo "WPS Office installed successfully."
}

install_wps_office() {
    info "Installing WPS Office..."
    case "$DISTRO_FAMILY" in
        debian)
            _wps_install_from_site "deb"
            ;;
        fedora|rhel)
            _wps_install_from_site "rpm"
            ;;
        arch)
            aur_ensure wps-office
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub com.wps.Office
            else
                echo "Error: No supported installation method for openSUSE. Install flatpak and retry."
                return 1
            fi
            ;;
        *)
            if has_flatpak; then
                flatpak install -y flathub com.wps.Office
            else
                echo "Error: Unsupported distribution and flatpak is not available."
                return 1
            fi
            ;;
    esac
}

uninstall_wps_office() {
    info "Uninstalling WPS Office..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y wps-office
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y wps-office
            ;;
        arch)
            aur_remove wps-office 2>/dev/null || pkg_remove wps-office 2>/dev/null || true
            ;;
        suse)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak uninstall -y com.wps.Office
            else
                sudo zypper remove -y wps-office 2>/dev/null || true
            fi
            ;;
        *)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak uninstall -y com.wps.Office
            fi
            ;;
    esac
    rm -rf ~/.local/share/kingsoft
    rm -rf ~/.config/Kingsoft
    echo "WPS Office has been uninstalled."
}

update_wps_office() {
    info "Updating WPS Office..."
    case "$DISTRO_FAMILY" in
        debian)
            # WPS Office has no apt repo; re-download latest .deb
            _wps_install_from_site "deb"
            ;;
        fedora|rhel)
            _wps_install_from_site "rpm"
            ;;
        arch)
            aur_ensure wps-office
            ;;
        *)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak update -y com.wps.Office
            fi
            ;;
    esac
}

get_version_wps_office() {
    if pkg_check_installed wps-office; then
        dpkg -l wps-office 2>/dev/null | \
            awk '/^ii/ { print $3 }' | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+' | head -1
        return
    fi
    if flatpak_is_installed "com.wps.Office"; then
        flatpak list --app 2>/dev/null | grep -i "wps" | \
            grep -oP '\t[0-9]+\.[0-9]+\.[0-9]+' | tr -d '\t' | head -1
        return
    fi
    echo ""
}
