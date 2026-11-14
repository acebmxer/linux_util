#!/bin/bash
# Kopia installer functions
#
# Fast, encrypted, deduplicating backup with snapshots and a web page
# (kopia server start). The command-line program. The distro package on Fedora
# and openSUSE; everywhere else Kopia's GitHub release (a single binary), checked
# against its published SHA-256 and put in /usr/local/bin. The KopiaUI desktop
# app is a separate download and is not installed. Not offered on Alpine.

# --- Kopia ---

_kopia_REPO="kopia/kopia"
_kopia_RE='kopia-[0-9.]+-linux-@X64@\.tar\.gz'

# Latest upstream version, for System Updates.
_kopia_latest_version() { github_latest_tag "$_kopia_REPO" | sed 's/^v//'; }

check_kopia() { _check_standard kopia kopia "" || [[ -x /usr/local/bin/kopia ]]; }

install_kopia() {
    info "Installing Kopia..."
    native_or_github_install kopia "$_kopia_REPO" "$_kopia_RE" kopia || return 1
    info "Kopia installed."
}

# Your repository connections and passwords (~/.config/kopia) are kept.
uninstall_kopia() {
    info "Uninstalling Kopia..."
    native_or_github_uninstall kopia kopia
}

update_kopia() {
    info "Updating Kopia..."
    native_or_github_update kopia "$_kopia_REPO" "$_kopia_RE" kopia kopia "$(get_version_kopia)"
}

get_version_kopia() { _ver_from_pkg kopia || _ver_from_cmd kopia --version || echo ""; }
