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
            sudo apt install -y kubectl
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
            sudo "$PKG_MGR" install -y kubectl
            ;;
        arch)
            sudo pacman -S --noconfirm kubectl
            ;;
        suse)
            sudo zypper install -y kubectl 2>/dev/null || _install_kubectl_binary
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
    if ! curl -fsSL "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl" \
        -o /tmp/kubectl; then
        error "Failed to download kubectl binary."
        return 1
    fi
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
}

uninstall_kubectl() {
    info "Uninstalling kubectl..."
    if [[ -f /usr/local/bin/kubectl ]]; then
        sudo rm -f /usr/local/bin/kubectl
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y kubectl 2>/dev/null || true
            sudo rm -f /etc/apt/sources.list.d/kubernetes.list
            sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y kubectl 2>/dev/null || true
            sudo rm -f /etc/yum.repos.d/kubernetes.repo
            ;;
        arch)
            sudo pacman -Rs --noconfirm kubectl 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y kubectl 2>/dev/null || true
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
            fedora|rhel) sudo "$PKG_MGR" upgrade -y kubectl ;;
            arch)        sudo pacman -S --noconfirm kubectl ;;
            suse)        sudo zypper update -y kubectl 2>/dev/null || _install_kubectl_binary ;;
        esac
    fi
}

get_version_kubectl() {
    _ver_from_cmd kubectl version --client 2>/dev/null | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
        _ver_from_pkg kubectl || echo ""
}
