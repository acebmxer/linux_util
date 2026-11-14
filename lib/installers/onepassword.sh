#!/bin/bash
# 1Password installer functions
# Debian/Ubuntu, Fedora, RHEL clones and openSUSE use 1Password's own signed
# repository (downloads.1password.com), so updates arrive with the system.
# Arch has no vendor repository: the package comes from the AUR, which this
# tool only uses when AUR_ENABLED=true. 1Password publishes no Alpine package.

# --- 1Password ---

_OP_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"
# Fingerprint of the signing key (key ID AC2D62742012EA22), checked against the
# downloaded key before it is trusted.
_OP_KEY_FPR="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
_OP_APT_KEYRING="/usr/share/keyrings/1password-archive-keyring.gpg"
_OP_APT_LIST="/etc/apt/sources.list.d/1password.list"
_OP_REPO_FILE="/etc/yum.repos.d/1password.repo"

check_onepassword() { _check_standard 1password 1password ""; }

_op_import_rpm_key() {
    sudo rpm --import "$_OP_KEY_URL" || { error "Could not import the 1Password signing key."; return 1; }
}

install_onepassword() {
    info "Installing 1Password..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local arch
            arch=$(dpkg --print-architecture)
            _add_apt_repo "$_OP_KEY_URL" "$_OP_APT_KEYRING" \
                "deb [arch=${arch} signed-by=${_OP_APT_KEYRING}] https://downloads.1password.com/linux/debian/${arch} stable main" \
                "$_OP_APT_LIST" "$_OP_KEY_FPR" || return 1
            pkg_install 1password
            ;;
        fedora|rhel)
            _op_import_rpm_key || return 1
            printf '%s\n' \
                '[1password]' \
                'name=1Password Stable Channel' \
                'baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch' \
                'enabled=1' \
                'gpgcheck=1' \
                'repo_gpgcheck=1' \
                "gpgkey=${_OP_KEY_URL}" | sudo tee "$_OP_REPO_FILE" >/dev/null
            pkg_install 1password
            ;;
        suse)
            _op_import_rpm_key || return 1
            sudo zypper --non-interactive removerepo 1password &>/dev/null || true
            sudo zypper --non-interactive addrepo --refresh \
                "https://downloads.1password.com/linux/rpm/stable/$(uname -m)" 1password || return 1
            sudo zypper --non-interactive --gpg-auto-import-keys refresh 1password || return 1
            pkg_install 1password
            ;;
        arch)
            # The AUR package verifies its download against this key.
            curl -fsSL "$_OP_KEY_URL" | gpg --import - || { error "Could not import the 1Password signing key."; return 1; }
            repo_or_aur 1password || return 1
            ;;
        *)
            error "1Password publishes no package for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    info "1Password installed."
}

# The signed-in account and its vault cache (~/.config/1Password) are kept.
uninstall_onepassword() {
    info "Uninstalling 1Password..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove 1password
            sudo rm -f "$_OP_APT_LIST" "$_OP_APT_KEYRING"
            ;;
        fedora|rhel)
            pkg_remove 1password
            sudo rm -f "$_OP_REPO_FILE"
            ;;
        suse)
            pkg_remove 1password
            sudo zypper --non-interactive removerepo 1password 2>/dev/null || true
            ;;
        arch)
            aur_remove 1password 2>/dev/null || pkg_remove 1password
            ;;
    esac
}

update_onepassword() {
    info "Updating 1Password..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur 1password
    else
        pkg_upgrade 1password
    fi
}

get_version_onepassword() { _ver_from_pkg 1password || echo ""; }
