#!/bin/bash
# Tailscale installer functions

# --- Tailscale ---

check_tailscale() { _check_standard tailscale tailscale ""; }

install_tailscale() {
    info "Installing Tailscale..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official Tailscale apt repo
            local codename
            codename="${DISTRO_VERSION_CODENAME:-stable}"
            # Derivatives map to their upstream Ubuntu/Debian codename
            if [[ "$DISTRO_ID" == "kubuntu" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" ]]; then
                codename=$(grep -oP '(?<=UBUNTU_CODENAME=).+' /etc/os-release 2>/dev/null || echo "$codename")
            elif [[ "$DISTRO_ID" == "neon" ]]; then
                codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release 2>/dev/null || echo "noble")
            fi
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" | \
                sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
            curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.tailscale-keyring.list" | \
                sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null
            sudo apt update
            sudo apt install -y tailscale
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" config-manager --add-repo \
                "https://pkgs.tailscale.com/stable/fedora/tailscale.repo" 2>/dev/null || \
            sudo tee /etc/yum.repos.d/tailscale.repo <<'REPO' > /dev/null
[tailscale-stable]
name=Tailscale stable
baseurl=https://pkgs.tailscale.com/stable/fedora/$basearch
enabled=1
type=rpm
repo_gpgcheck=1
gpgcheck=0
gpgkey=https://pkgs.tailscale.com/stable/fedora/repo.gpg
REPO
            sudo "$PKG_MGR" install -y tailscale
            ;;
        arch)
            sudo pacman -S --noconfirm tailscale
            ;;
        suse)
            sudo zypper addrepo -f \
                "https://pkgs.tailscale.com/stable/opensuse/tumbleweed/tailscale.repo" \
                tailscale 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y tailscale
            ;;
    esac

    # Enable and start the service
    sudo systemctl enable --now tailscaled
    info "Tailscale installed and daemon started."
    info "Run 'sudo tailscale up' to connect to your tailnet."
}

uninstall_tailscale() {
    info "Uninstalling Tailscale..."
    sudo tailscale down 2>/dev/null || true
    sudo systemctl stop tailscaled 2>/dev/null || true
    sudo systemctl disable tailscaled 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y tailscale
            sudo rm -f /etc/apt/sources.list.d/tailscale.list
            sudo rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y tailscale
            sudo rm -f /etc/yum.repos.d/tailscale.repo
            ;;
        arch)
            sudo pacman -Rs --noconfirm tailscale
            ;;
        suse)
            sudo zypper remove -y tailscale
            sudo zypper removerepo tailscale 2>/dev/null || true
            ;;
    esac
}

update_tailscale() {
    info "Updating Tailscale..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y --only-upgrade tailscale ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y tailscale ;;
        arch)    sudo pacman -S --noconfirm tailscale ;;
        suse)    sudo zypper update -y tailscale ;;
    esac
}

get_version_tailscale() {
    _ver_from_cmd tailscale version || echo ""
}
