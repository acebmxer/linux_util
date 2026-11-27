#!/bin/bash
# kubectl Kubernetes CLI installer functions

# --- kubectl ---

check_kubectl() { _check_standard kubectl kubectl ""; }

install_kubectl() {
    info "Installing kubectl..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official Kubernetes apt repository
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | \
                sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | \
                sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
            sudo apt update
            pkg_install kubectl
            ;;
        fedora|rhel)
            sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null <<'REPO'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
REPO
            pkg_install kubectl
            ;;
        arch)
            pkg_install kubectl
            ;;
        suse)
            pkg_install kubectl 2>/dev/null || _install_kubectl_binary
            ;;
    esac
    info "kubectl installed."
}

# Fallback: install kubectl binary directly
_install_kubectl_binary() {
    local version arch
    version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    [[ -z "$version" ]] && { error "Could not determine latest kubectl version."; return 1; }
    arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
    # A private temp file (not a fixed /tmp name another user could plant), and
    # the binary must match the SHA-256 Kubernetes publishes beside it.
    local tmpfile base="https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl" want
    tmpfile=$(mktemp /tmp/kubectl-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpfile")
    if ! curl -fsSL "$base" -o "$tmpfile"; then
        error "Failed to download kubectl binary."
        return 1
    fi
    want=$(curl -fsSL "${base}.sha256" 2>/dev/null | awk '{print $1}')
    if [[ ! "$want" =~ ^[0-9a-fA-F]{64}$ ]]; then
        error "Could not read the published SHA-256 for kubectl ${version}; kubectl was not installed."
        return 1
    fi
    verify_sha256 "$tmpfile" "$want" "kubectl ${version}" || return 1
    sudo install -o root -g root -m 0755 "$tmpfile" /usr/local/bin/kubectl
}

uninstall_kubectl() {
    info "Uninstalling kubectl..."
    if [[ -f /usr/local/bin/kubectl ]]; then
        sudo rm -f /usr/local/bin/kubectl
    fi
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove kubectl 2>/dev/null || true
            sudo rm -f /etc/apt/sources.list.d/kubernetes.list
            sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            ;;
        fedora|rhel)
            pkg_remove kubectl 2>/dev/null || true
            sudo rm -f /etc/yum.repos.d/kubernetes.repo
            ;;
        arch)
            pkg_remove kubectl 2>/dev/null || true
            ;;
        suse)
            pkg_remove kubectl 2>/dev/null || true
            ;;
    esac
}

update_kubectl() {
    info "Updating kubectl..."
    if [[ -f /usr/local/bin/kubectl ]]; then
        _install_kubectl_binary
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade kubectl ;;
            fedora|rhel) pkg_upgrade kubectl ;;
            arch)        pkg_upgrade kubectl ;;
            suse)        pkg_upgrade kubectl 2>/dev/null || _install_kubectl_binary ;;
        esac
    fi
}

get_version_kubectl() {
    _ver_from_cmd kubectl version --client 2>/dev/null | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
        _ver_from_pkg kubectl || echo ""
}
