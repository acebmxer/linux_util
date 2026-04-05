#!/bin/bash
# Mozilla Thunderbird installer functions

# --- Mozilla Thunderbird ---

check_thunderbird() { _check_standard thunderbird thunderbird ""; }

install_thunderbird() {
    info "Installing Mozilla Thunderbird..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Prefer the official Mozilla-signed APT repository over distro or snap packages
            _add_apt_repo \
                "https://packages.mozilla.org/apt/repo-signing-key.gpg" \
                "/usr/share/keyrings/mozilla-thunderbird-keyring.gpg" \
                "deb [signed-by=/usr/share/keyrings/mozilla-thunderbird-keyring.gpg] https://packages.mozilla.org/apt mozilla main" \
                "/etc/apt/sources.list.d/mozilla.list"
            # Pin so the Mozilla repo takes precedence over distro packages
            printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1001\n' | \
                sudo tee /etc/apt/preferences.d/mozilla > /dev/null
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
