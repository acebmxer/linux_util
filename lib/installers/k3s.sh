#!/bin/bash
# k3s installer functions
#
# Lightweight Kubernetes: one binary that runs a cluster node. Alpine: the
# distro package with its OpenRC service. Everywhere else k3s's own install
# script from get.k3s.io, saved and run from a file; it downloads the k3s
# binary and checks it against the release's published SHA-256 itself, installs
# the service (and k3s-selinux on RHEL clones) and starts a server, with its
# data in /var/lib/rancher/k3s. Uninstalling runs k3s's own remover, which
# DELETES that cluster data.

# --- k3s ---

_K3S_SCRIPT_URL="https://get.k3s.io"
_K3S_UNINSTALL="/usr/local/bin/k3s-uninstall.sh"

# Latest stable release, e.g. 1.34.1: k3s's stable channel redirects to its tag.
_k3s_latest_version() {
    local url
    url=$(curl -fsSL --max-time 20 -o /dev/null -w '%{url_effective}' "https://update.k3s.io/v1-release/channels/stable" 2>/dev/null) || return 1
    grep -oP '/v\K[0-9]+\.[0-9]+\.[0-9]+' <<<"$url" | head -1
}

check_k3s() { _check_standard k3s k3s ""; }

install_k3s() {
    info "Installing k3s..."
    ensure_tools
    local script
    script=$(mktemp) || return 1
    CLEANUP_FILES+=("$script")
    curl -fsSL --max-time 60 "$_K3S_SCRIPT_URL" -o "$script" || { error "Could not download the k3s install script."; rm -f "$script"; return 1; }
    head -1 "$script" | grep -q '^#!' || { error "The k3s install script is not a script."; rm -f "$script"; return 1; }
    sudo sh "$script"
    local rc=$?
    rm -f "$script"
    [[ $rc -eq 0 ]] || { error "The k3s install script failed."; return 1; }
    info "k3s installed and running. Use it with: sudo k3s kubectl get nodes"
}

uninstall_k3s() {
    info "Uninstalling k3s..."
    if [[ -x "$_K3S_UNINSTALL" ]]; then
        sudo "$_K3S_UNINSTALL"
    else
        pkg_remove k3s
    fi
}

update_k3s() {
    info "Updating k3s..."
    if [[ ! -x "$_K3S_UNINSTALL" ]]; then
        pkg_upgrade k3s
        return $?
    fi
    local cur latest
    cur=$(get_version_k3s)
    latest=$(_k3s_latest_version) || { error "Could not read the latest k3s version."; return 1; }
    if [[ -n "$cur" && "$cur" == "$latest" ]]; then
        info "k3s is already at the latest version (${cur})."
        return 0
    fi
    install_k3s
}

get_version_k3s() { _ver_from_pkg k3s || _ver_from_cmd k3s --version || echo ""; }
