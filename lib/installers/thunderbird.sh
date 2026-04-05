#!/bin/bash
# Mozilla Thunderbird installer functions

# --- Mozilla Thunderbird ---

check_thunderbird() {
    command -v thunderbird &>/dev/null || pkg_check_installed thunderbird
}

install_thunderbird() {
    info "Installing Mozilla Thunderbird..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Prefer the official Mozilla-signed APT repository over distro or snap packages
            local key_path="/usr/share/keyrings/mozilla-thunderbird-keyring.gpg"
            sudo install -d -m 0755 /usr/share/keyrings
            sudo curl -fsSL "https://packages.mozilla.org/apt/repo-signing-key.gpg" \
                -o "$key_path"
            echo "deb [signed-by=${key_path}] https://packages.mozilla.org/apt mozilla main" | \
                sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null 2>&1 || true
            # Pin so the Mozilla repo takes precedence over distro packages
            printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1001\n' | \
                sudo tee /etc/apt/preferences.d/mozilla > /dev/null
            sudo apt update
            sudo apt install -y thunderbird
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y thunderbird
            ;;
        arch)
            pkg_install thunderbird
            ;;
        suse)
            sudo zypper install -y MozillaThunderbird
            ;;
    esac
}

uninstall_thunderbird() {
    info "Uninstalling Mozilla Thunderbird..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y thunderbird
            sudo apt autoclean
            # Only remove the Mozilla repo/keyring if Firefox is also absent
            if ! check_firefox 2>/dev/null; then
                sudo rm -f /etc/apt/sources.list.d/mozilla.list
                sudo rm -f /usr/share/keyrings/mozilla-thunderbird-keyring.gpg
                sudo rm -f /etc/apt/preferences.d/mozilla
            fi
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y thunderbird
            ;;
        arch)
            pkg_remove thunderbird
            ;;
        suse)
            sudo zypper remove -y MozillaThunderbird
            ;;
    esac
    rm -rf ~/.thunderbird
}

update_thunderbird() {
    info "Updating Mozilla Thunderbird..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y thunderbird
            ;;
        arch)
            pkg_install thunderbird
            ;;
        *)
            pkg_upgrade thunderbird
            ;;
    esac
}

get_version_thunderbird() {
    thunderbird --version 2>/dev/null | grep -oP 'Mozilla Thunderbird \K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}
