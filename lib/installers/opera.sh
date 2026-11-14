#!/bin/bash
# Opera browser installer functions
#
# Debian/Ubuntu, Fedora, RHEL clones and openSUSE use Opera's own signed
# repositories (deb.opera.com, rpm.opera.com), so updates arrive with the
# system. Opera's RPM repository is x86_64 only. Arch has no repository
# package: Flathub's com.opera.Opera when Flatpak is set up, else the AUR
# (only when AUR support is on). Not offered on Alpine (glibc build).

# --- Opera ---

_OPERA_APT_KEY_URL="https://deb.opera.com/archive.key"
_OPERA_RPM_KEY_URL="https://rpm.opera.com/rpmrepo.key"
# Primary fingerprint of Opera's archive signing key (key ID 11EE8C00B693A745),
# checked against the downloaded key before it is trusted.
_OPERA_KEY_FPR="6C86BE214648376680CA957B11EE8C00B693A745"
_OPERA_APT_KEYRING="/usr/share/keyrings/opera-archive-keyring.gpg"
_OPERA_APT_LIST="/etc/apt/sources.list.d/opera-stable.list"
_OPERA_REPO_FILE="/etc/yum.repos.d/opera.repo"

check_opera() { _check_standard opera opera-stable com.opera.Opera; }

install_opera() {
    info "Installing Opera..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local arch
            arch=$(dpkg --print-architecture)
            _add_apt_repo "$_OPERA_APT_KEY_URL" "$_OPERA_APT_KEYRING" \
                "deb [arch=${arch} signed-by=${_OPERA_APT_KEYRING}] https://deb.opera.com/opera-stable/ stable non-free" \
                "$_OPERA_APT_LIST" "$_OPERA_KEY_FPR" || return 1
            # Opera's package would otherwise ask whether to add its own repository
            # entry, which this has just done.
            command -v debconf-set-selections &>/dev/null && \
                echo "opera-stable opera-stable/add-deb-repo boolean false" | sudo debconf-set-selections
            pkg_install opera-stable || return 1
            ;;
        fedora|rhel|suse)
            if [[ "$(uname -m)" != "x86_64" ]]; then
                error "Opera publishes RPM packages for x86_64 only."
                return 1
            fi
            # Opera's RPM needs the Qt 5 libraries, which RHEL clones 10 carry in EPEL.
            ensure_epel
            rpm_import_key_checked "$_OPERA_RPM_KEY_URL" "$_OPERA_KEY_FPR" || return 1
            if [[ "$DISTRO_FAMILY" == "suse" ]]; then
                sudo zypper --non-interactive removerepo opera &>/dev/null || true
                sudo zypper --non-interactive addrepo --refresh https://rpm.opera.com/rpm opera || return 1
                sudo zypper --non-interactive --gpg-auto-import-keys refresh opera || return 1
            else
                printf '%s\n' \
                    '[opera]' \
                    'name=Opera packages' \
                    'type=rpm-md' \
                    'baseurl=https://rpm.opera.com/rpm' \
                    'gpgcheck=1' \
                    'gpgkey=https://rpm.opera.com/rpmrepo.key' \
                    'enabled=1' | sudo tee "$_OPERA_REPO_FILE" >/dev/null
            fi
            pkg_install opera-stable || return 1
            ;;
        arch)
            flatpak_or_aur com.opera.Opera opera || return 1
            ;;
        *)
            error "Opera publishes no package for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    info "Opera installed."
}

# Profiles, bookmarks and passwords (~/.config/opera) are kept.
uninstall_opera() {
    info "Uninstalling Opera..."
    if flatpak_is_installed com.opera.Opera; then
        flatpak uninstall -y --user com.opera.Opera 2>/dev/null || \
            sudo flatpak uninstall -y --system com.opera.Opera
        return
    fi
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove opera-stable
            sudo rm -f "$_OPERA_APT_LIST" "${_OPERA_APT_LIST%.list}.sources" "$_OPERA_APT_KEYRING"
            ;;
        fedora|rhel)
            pkg_remove opera-stable
            sudo rm -f "$_OPERA_REPO_FILE"
            ;;
        suse)
            pkg_remove opera-stable
            sudo zypper --non-interactive removerepo opera 2>/dev/null || true
            ;;
        arch)
            aur_remove opera 2>/dev/null || pkg_remove opera
            ;;
    esac
}

update_opera() {
    info "Updating Opera..."
    if flatpak_is_installed com.opera.Opera; then
        flatpak update -y --user com.opera.Opera 2>/dev/null || \
            sudo flatpak update -y --system com.opera.Opera
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur opera
    else
        pkg_upgrade opera-stable
    fi
}

get_version_opera() { _ver_from_pkg opera-stable || _ver_from_pkg opera || _ver_from_flatpak com.opera.Opera || echo ""; }
