#!/bin/bash
# minikube installer functions
#
# Runs a local single-node Kubernetes cluster for development. The distro package on Arch and openSUSE Tumbleweed; otherwise the GitHub release, SHA-256 checked, in /usr/local/bin. Needs a driver such as Docker, Podman or KVM, which this does not install.

# --- minikube ---

_minikube_REPO="kubernetes/minikube"
_minikube_RE='minikube-linux-@GO@'

# Latest upstream version, for System Updates.
_minikube_latest_version() { github_latest_tag "$_minikube_REPO" | sed 's/^v//'; }

check_minikube() { _check_standard minikube minikube "" || [[ -x /usr/local/bin/minikube ]]; }

install_minikube() {
    info "Installing minikube..."
    native_or_github_install minikube "$_minikube_REPO" "$_minikube_RE" minikube || return 1
    info "minikube installed."
}

uninstall_minikube() {
    info "Uninstalling minikube..."
    native_or_github_uninstall minikube minikube
}

update_minikube() {
    info "Updating minikube..."
    native_or_github_update minikube "$_minikube_REPO" "$_minikube_RE" minikube minikube "$(get_version_minikube)"
}

get_version_minikube() { _ver_from_pkg minikube || _ver_from_cmd minikube version || echo ""; }
