#!/bin/bash
# Helm installer functions
#
# The Kubernetes package manager. The distro package where the repositories
# have one (Fedora, Rocky/Alma 9 and 10 through EPEL, Arch, openSUSE, Alpine);
# otherwise (Debian, Ubuntu, Rocky/Alma 8) the release from get.helm.sh, checked
# against the SHA-256 file Helm publishes beside it, in /usr/local/bin.

# --- Helm ---

_HELM_REPO="helm/helm"

# Latest upstream version, for System Updates.
_helm_latest_version() { github_latest_tag "$_HELM_REPO" | sed 's/^v//'; }

check_helm() { _check_standard helm helm "" || [[ -x /usr/local/bin/helm ]]; }

_helm_install_release() {
    local tag arch tmp name want
    tag=$(github_latest_tag "$_HELM_REPO") || { error "Could not read the latest Helm release from GitHub."; return 1; }
    arch=$(upstream_arch go) || return 1
    name="helm-${tag}-linux-${arch}.tar.gz"
    tmp=$(mktemp -d) || return 1
    CLEANUP_FILES+=("$tmp")
    info "Downloading ${name}..."
    curl -fsSL --max-time 300 "https://get.helm.sh/${name}" -o "${tmp}/${name}" \
        && want=$(curl -fsSL --max-time 30 "https://get.helm.sh/${name}.sha256sum" | awk '{print $1}') \
        && [[ "$want" =~ ^[0-9a-f]{64}$ ]] || { error "Could not download Helm ${tag} or its checksum."; rm -rf "$tmp"; return 1; }
    verify_sha256 "${tmp}/${name}" "$want" "$name" || { rm -rf "$tmp"; return 1; }
    tar -xzf "${tmp}/${name}" -C "$tmp" || { error "Could not unpack ${name}."; rm -rf "$tmp"; return 1; }
    sudo install -Dm755 "${tmp}/linux-${arch}/helm" /usr/local/bin/helm || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
}

install_helm() {
    info "Installing Helm..."
    pkg_refresh
    ensure_epel
    if pkg_in_repo helm; then
        pkg_install helm || return 1
    else
        info "helm is not in the ${DISTRO_NAME:-system} repositories; installing the verified release from get.helm.sh."
        _helm_install_release || return 1
    fi
    info "Helm installed."
}

uninstall_helm() {
    info "Uninstalling Helm..."
    pkg_check_installed helm && pkg_remove helm
    sudo rm -f /usr/local/bin/helm
    return 0
}

update_helm() {
    info "Updating Helm..."
    if upstream_binary_present helm helm; then
        local tag cur
        tag=$(github_latest_tag "$_HELM_REPO") || { error "Could not read the latest Helm release from GitHub."; return 1; }
        cur=$(get_version_helm)
        if [[ -n "$cur" && "${tag#v}" == "$cur" ]]; then
            info "Helm is already at the latest version (${cur})."
            return 0
        fi
        _helm_install_release
    else
        pkg_upgrade helm
    fi
}

get_version_helm() { _ver_from_pkg helm || _ver_from_cmd helm version || echo ""; }
