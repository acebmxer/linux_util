#!/bin/bash
# Mullvad VPN installer functions
#
# Debian/Ubuntu, Fedora, RHEL clones and openSUSE use Mullvad's own signed
# repository (repository.mullvad.net), so updates arrive with the system.
# Arch carries mullvad-vpn in its own repositories. The package enables and
# starts its own background service. Not offered on Alpine
# (glibc build).

# --- Mullvad VPN ---

_MULLVAD_APT_KEY_URL="https://repository.mullvad.net/deb/mullvad-keyring.asc"
_MULLVAD_RPM_KEY_URL="https://repository.mullvad.net/rpm/mullvad-keyring.asc"
# Primary fingerprint of Mullvad's code-signing key (key ID D5A1D4F266DE8DDF),
# checked against the downloaded key before it is trusted.
_MULLVAD_KEY_FPR="A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF"
_MULLVAD_APT_KEYRING="/usr/share/keyrings/mullvad-keyring.gpg"
_MULLVAD_APT_LIST="/etc/apt/sources.list.d/mullvad.list"
_MULLVAD_REPO_FILE="/etc/yum.repos.d/mullvad.repo"

check_mullvad_vpn() { _check_standard mullvad mullvad-vpn ""; }

install_mullvad_vpn() {
    info "Installing Mullvad VPN..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local arch
            arch=$(dpkg --print-architecture)
            _add_apt_repo "$_MULLVAD_APT_KEY_URL" "$_MULLVAD_APT_KEYRING" \
                "deb [arch=${arch} signed-by=${_MULLVAD_APT_KEYRING}] https://repository.mullvad.net/deb/stable stable main" \
                "$_MULLVAD_APT_LIST" "$_MULLVAD_KEY_FPR" || return 1
            pkg_install mullvad-vpn || return 1
            ;;
        fedora|rhel|suse)
            # libXScrnSaver, which the app needs, is in EPEL on RHEL clones 10.
            ensure_epel
            rpm_import_key_checked "$_MULLVAD_RPM_KEY_URL" "$_MULLVAD_KEY_FPR" || return 1
            if [[ "$DISTRO_FAMILY" == "suse" ]]; then
                sudo zypper --non-interactive removerepo mullvad-stable &>/dev/null || true
                sudo zypper --non-interactive addrepo --refresh \
                    "https://repository.mullvad.net/rpm/stable/$(uname -m)" mullvad-stable || return 1
                sudo zypper --non-interactive --gpg-auto-import-keys refresh mullvad-stable || return 1
            else
                printf '%s\n' \
                    '[mullvad-stable]' \
                    'name=Mullvad VPN' \
                    'baseurl=https://repository.mullvad.net/rpm/stable/$basearch' \
                    'type=rpm' \
                    'enabled=1' \
                    'gpgcheck=1' \
                    "gpgkey=${_MULLVAD_RPM_KEY_URL}" | sudo tee "$_MULLVAD_REPO_FILE" >/dev/null
            fi
            pkg_install mullvad-vpn || return 1
            ;;
        arch)
            pkg_install mullvad-vpn || return 1
            ;;
        *)
            error "Mullvad publishes no package for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    info "Mullvad VPN installed."
}

uninstall_mullvad_vpn() {
    info "Uninstalling Mullvad VPN..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove mullvad-vpn
            sudo rm -f "$_MULLVAD_APT_LIST" "$_MULLVAD_APT_KEYRING"
            ;;
        fedora|rhel)
            pkg_remove mullvad-vpn
            sudo rm -f "$_MULLVAD_REPO_FILE"
            ;;
        suse)
            pkg_remove mullvad-vpn
            sudo zypper --non-interactive removerepo mullvad-stable 2>/dev/null || true
            ;;
        arch)
            pkg_remove mullvad-vpn
            ;;
    esac
}

update_mullvad_vpn() {
    info "Updating Mullvad VPN..."
    pkg_upgrade mullvad-vpn
}

get_version_mullvad_vpn() { _ver_from_pkg mullvad-vpn || echo ""; }
