#!/bin/bash
# Mozilla Firefox installer functions

# --- Mozilla Firefox ---

check_firefox() {
    command -v firefox &>/dev/null || pkg_check_installed firefox
}

install_firefox() {
    info "Installing Mozilla Firefox..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Prefer the official Mozilla-signed APT repository over the Ubuntu snap
            local key_path="/usr/share/keyrings/mozilla-firefox-keyring.gpg"
            sudo install -d -m 0755 /usr/share/keyrings
            sudo curl -fsSL "https://packages.mozilla.org/apt/repo-signing-key.gpg" \
                -o "$key_path"
            echo "deb [signed-by=${key_path}] https://packages.mozilla.org/apt mozilla main" | \
                sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
            # Pin so the Mozilla repo takes precedence over distro packages
            printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1001\n' | \
                sudo tee /etc/apt/preferences.d/mozilla > /dev/null
            sudo apt update
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
            sudo apt purge --autoremove -y firefox
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/mozilla.list
            sudo rm -f /usr/share/keyrings/mozilla-firefox-keyring.gpg
            sudo rm -f /etc/apt/preferences.d/mozilla
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
    firefox --version 2>/dev/null | grep -oP 'Mozilla Firefox \K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}
