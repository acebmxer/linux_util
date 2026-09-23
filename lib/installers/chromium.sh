#!/bin/bash
# Chromium Browser installer functions

# --- Chromium Browser ---

check_chromium() {
    _have_cmd chromium || _have_cmd chromium-browser || \
        pkg_check_installed chromium || pkg_check_installed chromium-browser
}

install_chromium() {
    info "Installing Chromium Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            # Package name is 'chromium' on Debian, 'chromium-browser' on older Ubuntu
            pkg_install chromium 2>/dev/null || sudo apt install -y chromium-browser
            ;;
        fedora|rhel)
            pkg_install chromium
            ;;
        arch)
            pkg_install chromium
            ;;
        suse)
            pkg_install chromium
            ;;
    esac
}

uninstall_chromium() {
    info "Uninstalling Chromium Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove chromium chromium-browser 2>/dev/null || true
            ;;
        fedora|rhel)
            pkg_remove chromium
            ;;
        arch)
            pkg_remove chromium
            ;;
        suse)
            pkg_remove chromium
            ;;
    esac
    rm -rf ~/.config/chromium
}

update_chromium() {
    info "Updating Chromium Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade chromium chromium-browser 2>/dev/null || true
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
        _have_cmd "$cmd" || continue
        _run_native "$cmd" --version 2>/dev/null | grep -oP '(Chromium|chromium)\s+\K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' && return
    done
    echo ""
}
