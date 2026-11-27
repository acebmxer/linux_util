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
            # Tailscale keeps separate Debian and Ubuntu repositories; a Debian
            # codename under /ubuntu/ is a 404.
            local ts_dist=ubuntu
            [[ "$DISTRO_ID" == "debian" ]] && ts_dist=debian
            local ts_base="https://pkgs.tailscale.com/stable/${ts_dist}/${codename}"
            local ts_key ts_list
            sudo mkdir -p /etc/apt/keyrings
            # Download to files first: with "curl | tee" a failed download left
            # empty key and repository files behind and the install went on.
            download_script "${ts_base}.noarmor.gpg" ts_key && \
                download_script "${ts_base}.tailscale-keyring.list" ts_list || {
                error "Tailscale installation failed: could not download its ${ts_dist}/${codename} repository files."
                return 1
            }
            sudo install -m 0644 "$ts_key" /usr/share/keyrings/tailscale-archive-keyring.gpg && \
                sudo install -m 0644 "$ts_list" /etc/apt/sources.list.d/tailscale.list || {
                error "Tailscale installation failed: could not store its repository files."
                return 1
            }
            sudo apt update
            pkg_install tailscale || return 1
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
            pkg_install tailscale || return 1
            ;;
        arch)
            pkg_install tailscale || return 1
            ;;
        suse)
            sudo zypper addrepo -f \
                "https://pkgs.tailscale.com/stable/opensuse/tumbleweed/tailscale.repo" \
                tailscale 2>/dev/null || true
            sudo zypper refresh
            pkg_install tailscale || return 1
            ;;
    esac

    # Enable and start the service
    if sudo systemctl enable --now tailscaled; then
        info "Tailscale installed and daemon started."
    else
        warn "Tailscale is installed, but its service (tailscaled) could not be started."
    fi
    info "Run 'sudo tailscale up' to connect to your tailnet."
}

uninstall_tailscale() {
    info "Uninstalling Tailscale..."
    sudo tailscale down 2>/dev/null || true
    sudo systemctl stop tailscaled 2>/dev/null || true
    sudo systemctl disable tailscaled 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove tailscale
            sudo rm -f /etc/apt/sources.list.d/tailscale.list
            sudo rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
            ;;
        fedora|rhel)
            pkg_remove tailscale
            sudo rm -f /etc/yum.repos.d/tailscale.repo
            ;;
        arch)
            pkg_remove tailscale
            ;;
        suse)
            pkg_remove tailscale
            sudo zypper removerepo tailscale 2>/dev/null || true
            ;;
    esac
}

update_tailscale() {
    info "Updating Tailscale..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y --only-upgrade tailscale ;;
        fedora|rhel) pkg_upgrade tailscale ;;
        arch)    pkg_upgrade tailscale ;;
        suse)    pkg_upgrade tailscale ;;
    esac
}

get_version_tailscale() {
    _ver_from_cmd tailscale version || echo ""
}
