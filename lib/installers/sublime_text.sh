#!/bin/bash
# Sublime Text installer functions
#
# Debian/Ubuntu, Fedora, RHEL clones and openSUSE use Sublime HQ's own signed
# repository (download.sublimetext.com), so updates arrive with the system; the
# signing key is checked against the pinned fingerprint before it is trusted.
# Arch has no vendor package this tool can use: it comes from the AUR, which is
# only used when AUR_ENABLED=true. Sublime publishes no Alpine package, and
# Rocky/Alma 9 and 10 cannot import its RPM key (a SHA-1 signature their RPM
# refuses), so it is not offered there.

# --- Sublime Text ---

_SUBL_KEY_URL="https://download.sublimetext.com/sublimehq-pub.gpg"
# Primary fingerprint of the Sublime HQ signing key.
_SUBL_KEY_FPR="1EDDE2CDFC025D17F6DA9EC0ADAE6AD28A8F901A"
_SUBL_APT_KEYRING="/usr/share/keyrings/sublimehq-archive.gpg"
_SUBL_APT_LIST="/etc/apt/sources.list.d/sublime-text.list"
_SUBL_REPO_FILE="/etc/yum.repos.d/sublime-text.repo"

check_sublime_text() { _check_standard subl sublime-text "" sublime-text-4 subl; }

# x86_64 or aarch64, the two names the vendor repository uses.
_subl_arch() {
    case "$(uname -m)" in
        x86_64|aarch64) uname -m ;;
        *) error "Sublime Text publishes no package for the $(uname -m) CPU."; return 1 ;;
    esac
}

install_sublime_text() {
    info "Installing Sublime Text..."
    ensure_tools
    local arch
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo "$_SUBL_KEY_URL" "$_SUBL_APT_KEYRING" \
                "deb [signed-by=${_SUBL_APT_KEYRING}] https://download.sublimetext.com/ apt/stable/" \
                "$_SUBL_APT_LIST" "$_SUBL_KEY_FPR" || return 1
            pkg_install sublime-text
            ;;
        fedora|rhel)
            arch=$(_subl_arch) || return 1
            rpm_import_key_checked "$_SUBL_KEY_URL" "$_SUBL_KEY_FPR" || return 1
            printf '%s\n' \
                '[sublime-text]' \
                'name=Sublime Text - stable' \
                "baseurl=https://download.sublimetext.com/rpm/stable/${arch}" \
                'enabled=1' \
                'gpgcheck=1' \
                "gpgkey=${_SUBL_KEY_URL}" | sudo tee "$_SUBL_REPO_FILE" >/dev/null
            pkg_install sublime-text
            ;;
        suse)
            arch=$(_subl_arch) || return 1
            rpm_import_key_checked "$_SUBL_KEY_URL" "$_SUBL_KEY_FPR" || return 1
            sudo zypper --non-interactive removerepo sublime-text &>/dev/null || true
            sudo zypper --non-interactive addrepo --refresh \
                "https://download.sublimetext.com/rpm/stable/${arch}/sublime-text.repo" || return 1
            sudo zypper --non-interactive --gpg-auto-import-keys refresh sublime-text || return 1
            pkg_install sublime-text
            ;;
        arch)
            repo_or_aur sublime-text-4 || return 1
            ;;
        *)
            error "Sublime Text publishes no package for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    info "Sublime Text installed."
}

# Settings, packages and the licence in ~/.config/sublime-text are kept.
uninstall_sublime_text() {
    info "Uninstalling Sublime Text..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove sublime-text
            sudo rm -f "$_SUBL_APT_LIST" "$_SUBL_APT_KEYRING"
            ;;
        fedora|rhel)
            pkg_remove sublime-text
            sudo rm -f "$_SUBL_REPO_FILE"
            ;;
        suse)
            pkg_remove sublime-text
            sudo zypper --non-interactive removerepo sublime-text 2>/dev/null || true
            ;;
        arch)
            aur_remove sublime-text-4 2>/dev/null || pkg_remove sublime-text-4
            ;;
    esac
}

update_sublime_text() {
    info "Updating Sublime Text..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur sublime-text-4
    else
        pkg_upgrade sublime-text
    fi
}

get_version_sublime_text() { _ver_from_pkg sublime-text || _ver_from_pkg sublime-text-4 || echo ""; }
