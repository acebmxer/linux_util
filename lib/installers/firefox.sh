#!/bin/bash
# Mozilla Firefox installer functions

# --- Mozilla Firefox ---

check_firefox() {
    command -v firefox &>/dev/null || \
    pkg_check_installed firefox || \
    snap list firefox &>/dev/null 2>&1
}

install_firefox() {
    info "Installing Mozilla Firefox..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Prefer the official Mozilla-signed APT repository over the Ubuntu snap
            _add_apt_repo \
                "https://packages.mozilla.org/apt/repo-signing-key.gpg" \
                "/usr/share/keyrings/mozilla-firefox-keyring.gpg" \
                "deb [signed-by=/usr/share/keyrings/mozilla-firefox-keyring.gpg] https://packages.mozilla.org/apt mozilla main" \
                "/etc/apt/sources.list.d/mozilla.list"
            # Pin so the Mozilla repo takes precedence over distro packages
            printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1001\n' | \
                sudo tee /etc/apt/preferences.d/mozilla > /dev/null
            # Purge Ubuntu's snap-wrapper stub (1:1snap1-*) if present — it
            # would otherwise satisfy the install and pull in the snap instead
            # of the real Mozilla deb.
            if dpkg -l firefox 2>/dev/null | grep -q "^ii.*1snap1"; then
                sudo apt purge -y firefox 2>/dev/null || true
            fi
            sudo apt install -y firefox
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y firefox
            ;;
        arch)
            pkg_install firefox
            ;;
        suse)
            sudo zypper install -y MozillaFirefox
            ;;
    esac
}

uninstall_firefox() {
    info "Uninstalling Mozilla Firefox..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y firefox 2>/dev/null || true
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/mozilla.list
            sudo rm -f /usr/share/keyrings/mozilla-firefox-keyring.gpg
            sudo rm -f /etc/apt/preferences.d/mozilla
            # Also remove snap if present
            if snap list firefox &>/dev/null 2>&1; then
                sudo snap remove --purge firefox
            fi
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y firefox
            ;;
        arch)
            pkg_remove firefox
            ;;
        suse)
            sudo zypper remove -y MozillaFirefox
            ;;
    esac
    rm -rf ~/.mozilla/firefox
}

update_firefox() {
    info "Updating Mozilla Firefox..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y firefox
            ;;
        arch)
            pkg_install firefox
            ;;
        *)
            pkg_upgrade firefox
            ;;
    esac
}

get_version_firefox() {
    # Try binary first (covers both deb and snap installs)
    local _ver
    _ver=$(firefox --version 2>/dev/null | grep -oP 'Mozilla Firefox \K[0-9]+\.[0-9]+(\.[0-9]+)?')
    if [[ -z "$_ver" ]]; then
        # Fallback: parse snap list output
        _ver=$(snap list firefox 2>/dev/null | awk 'NR==2{print $2}')
    fi
    echo "${_ver:-}"
}
