#!/bin/bash
# Thorium Browser installer functions

# --- Thorium Browser ---
# Thorium is a Chromium fork with AVX optimizations.
# Official APT repo: https://dl.thorium.rocks
# GitHub releases: https://github.com/Alex313031/thorium/releases

check_thorium() { _check_standard thorium-browser thorium-browser ""; }

install_thorium() {
    info "Installing Thorium Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Thorium no longer distributes a GPG key; repo uses trusted=yes
            echo "deb [trusted=yes arch=amd64] https://dl.thorium.rocks/debian/ stable main" \
                | sudo tee /etc/apt/sources.list.d/thorium.list > /dev/null
            sudo apt update
            sudo apt install -y thorium-browser
            ;;
        fedora|rhel)
            # Thorium does not maintain an official RPM repo; install via GitHub release RPM
            local rpm_url
            rpm_url=$(curl -fsSL https://api.github.com/repos/Alex313031/thorium/releases/latest \
                | grep -oP '"browser_download_url":\s*"\K[^"]+thorium-browser[^"]+\.rpm(?=")' \
                | grep -v 'AVX2\|SSE3\|sse3\|avx2' \
                | head -1)
            if [[ -z "$rpm_url" ]]; then
                error "Could not determine Thorium RPM download URL."
                return 1
            fi
            local tmp_rpm
            tmp_rpm=$(mktemp /tmp/thorium-XXXXXX.rpm)
            curl -fsSL "$rpm_url" -o "$tmp_rpm"
            sudo "$PKG_MGR" install -y "$tmp_rpm"
            rm -f "$tmp_rpm"
            ;;
        arch)
            aur_ensure thorium-browser-bin
            ;;
        suse)
            # Install via GitHub release RPM (same approach as Fedora/RHEL)
            local rpm_url
            rpm_url=$(curl -fsSL https://api.github.com/repos/Alex313031/thorium/releases/latest \
                | grep -oP '"browser_download_url":\s*"\K[^"]+thorium-browser[^"]+\.rpm(?=")' \
                | grep -v 'AVX2\|SSE3\|sse3\|avx2' \
                | head -1)
            if [[ -z "$rpm_url" ]]; then
                error "Could not determine Thorium RPM download URL."
                return 1
            fi
            local tmp_rpm
            tmp_rpm=$(mktemp /tmp/thorium-XXXXXX.rpm)
            curl -fsSL "$rpm_url" -o "$tmp_rpm"
            sudo zypper install -y "$tmp_rpm"
            rm -f "$tmp_rpm"
            ;;
    esac
}

uninstall_thorium() {
    info "Uninstalling Thorium Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y thorium-browser
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/thorium.list
            sudo rm -f /usr/share/keyrings/thorium-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y thorium-browser
            ;;
        arch)
            aur_remove thorium-browser-bin 2>/dev/null || pkg_remove thorium-browser 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y thorium-browser
            ;;
    esac
    rm -rf ~/.config/thorium
}

update_thorium() {
    info "Updating Thorium Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y thorium-browser
            ;;
        fedora|rhel|suse)
            # Re-run install to fetch and upgrade to the latest GitHub release RPM
            install_thorium
            ;;
        arch)
            aur_ensure thorium-browser-bin
            ;;
    esac
}

get_version_thorium() {
    thorium-browser --version 2>/dev/null | grep -oP 'Thorium\s+\K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}
