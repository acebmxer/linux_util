#!/bin/bash
# Chromium Browser installer functions

# --- Chromium Browser ---

check_chromium() {
    command -v chromium &>/dev/null || command -v chromium-browser &>/dev/null || \
        pkg_check_installed chromium || pkg_check_installed chromium-browser
}

install_chromium() {
    info "Installing Chromium Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            # Package name is 'chromium' on Debian, 'chromium-browser' on older Ubuntu
            sudo apt install -y chromium 2>/dev/null || sudo apt install -y chromium-browser
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y chromium
            ;;
        arch)
            pkg_install chromium
            ;;
        suse)
            sudo zypper install -y chromium
            ;;
    esac
}

uninstall_chromium() {
    info "Uninstalling Chromium Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y chromium chromium-browser 2>/dev/null || true
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y chromium
            ;;
        arch)
            pkg_remove chromium
            ;;
        suse)
            sudo zypper remove -y chromium
            ;;
    esac
    rm -rf ~/.config/chromium
}

update_chromium() {
    info "Updating Chromium Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y chromium chromium-browser 2>/dev/null || true
            ;;
        arch)
            pkg_install chromium
            ;;
        *)
            pkg_upgrade chromium
            ;;
    esac
}

get_version_chromium() {
    local cmd
    for cmd in chromium chromium-browser; do
        command -v "$cmd" &>/dev/null || continue
        "$cmd" --version 2>/dev/null | grep -oP '(Chromium|chromium)\s+\K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' && return
    done
    echo ""
}
