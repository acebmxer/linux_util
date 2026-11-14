#!/bin/bash
# NordVPN installer functions
#
# Debian/Ubuntu, Fedora, RHEL clones and openSUSE use NordVPN's own signed
# repository (repo.nordvpn.com), so updates arrive with the system. Arch has no
# repository package: nordvpn-bin comes from the AUR, which this tool only uses
# when AUR_ENABLED=true. The package needs glibc 2.35, so it is not offered on
# Rocky/Alma/RHEL 8 and 9. The command-line client needs its background service
# and a "nordvpn" group; both are set up here. Not offered on Alpine
# (glibc build).

# --- NordVPN ---

_NORD_KEY_URL="https://repo.nordvpn.com/gpg/nordvpn_public.asc"
# Primary fingerprint of NordVPN's signing key (key ID 6B219E535C964CA1), checked
# against the downloaded key before it is trusted.
_NORD_KEY_FPR="BC5480EFEC5C081CE5BCFBE26B219E535C964CA1"
_NORD_APT_KEYRING="/usr/share/keyrings/nordvpn-archive-keyring.gpg"
_NORD_APT_LIST="/etc/apt/sources.list.d/nordvpn.list"
_NORD_REPO_FILE="/etc/yum.repos.d/nordvpn.repo"
_NORD_RPM_URL="https://repo.nordvpn.com/yum/nordvpn/centos/x86_64"

check_nordvpn() { _check_standard nordvpn nordvpn "" nordvpn-bin; }

install_nordvpn() {
    info "Installing NordVPN..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo "$_NORD_KEY_URL" "$_NORD_APT_KEYRING" \
                "deb [signed-by=${_NORD_APT_KEYRING}] https://repo.nordvpn.com/deb/nordvpn/debian stable main" \
                "$_NORD_APT_LIST" "$_NORD_KEY_FPR" || return 1
            pkg_install nordvpn || return 1
            ;;
        fedora|rhel|suse)
            if [[ "$(uname -m)" != "x86_64" ]]; then
                error "NordVPN's RPM repository is x86_64 only."
                return 1
            fi
            rpm_import_key_checked "$_NORD_KEY_URL" "$_NORD_KEY_FPR" || return 1
            if [[ "$DISTRO_FAMILY" == "suse" ]]; then
                sudo zypper --non-interactive removerepo nordvpn &>/dev/null || true
                sudo zypper --non-interactive addrepo --refresh "$_NORD_RPM_URL" nordvpn || return 1
                sudo zypper --non-interactive --gpg-auto-import-keys refresh nordvpn || return 1
            else
                printf '%s\n' \
                    '[nordvpn]' \
                    'name=NordVPN' \
                    "baseurl=${_NORD_RPM_URL}" \
                    'enabled=1' \
                    'gpgcheck=1' \
                    "gpgkey=${_NORD_KEY_URL}" | sudo tee "$_NORD_REPO_FILE" >/dev/null
            fi
            pkg_install nordvpn || return 1
            ;;
        arch)
            repo_or_aur nordvpn-bin || return 1
            ;;
        *)
            error "NordVPN publishes no package for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    _nordvpn_setup_access
    info "NordVPN installed. Log in with: nordvpn login (log out and in again first so the new group applies)."
}

# The nordvpn command talks to a service that only members of the "nordvpn"
# group may use, so the user who ran this is added to it, as NordVPN's own
# installer does. A change that applies at the next login.
_nordvpn_setup_access() {
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        sudo systemctl enable --now nordvpnd.service 2>/dev/null || true
    fi
    local user="${SUDO_USER:-$USER}"
    if [[ -n "$user" && "$user" != "root" ]] && getent group nordvpn &>/dev/null; then
        sudo usermod -aG nordvpn "$user" || warn "Could not add ${user} to the nordvpn group."
    fi
}

# The nordvpn group stays, as it may be shared with a reinstall.
uninstall_nordvpn() {
    info "Uninstalling NordVPN..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove nordvpn
            sudo rm -f "$_NORD_APT_LIST" "$_NORD_APT_KEYRING"
            ;;
        fedora|rhel)
            pkg_remove nordvpn
            sudo rm -f "$_NORD_REPO_FILE"
            ;;
        suse)
            pkg_remove nordvpn
            sudo zypper --non-interactive removerepo nordvpn 2>/dev/null || true
            ;;
        arch)
            aur_remove nordvpn-bin 2>/dev/null || pkg_remove nordvpn-bin
            ;;
    esac
}

update_nordvpn() {
    info "Updating NordVPN..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur nordvpn-bin
    else
        pkg_upgrade nordvpn
    fi
}

get_version_nordvpn() { _ver_from_pkg nordvpn || _ver_from_pkg nordvpn-bin || echo ""; }
