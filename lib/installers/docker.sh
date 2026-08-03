#!/bin/bash
# Docker installer functions

# --- Docker (utility version) ---
setup_install_docker() {
    info "Installing Docker..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            run_as_root apt-get install -y apt-transport-https ca-certificates curl gnupg

            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                run_as_root apt-get install -y software-properties-common
            fi

            local docker_dist="$DISTRO_ID"
            local docker_codename="${DISTRO_VERSION_CODENAME:-stable}"
            if [[ "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" || "$DISTRO_ID" == "kubuntu" ]]; then
                docker_dist="ubuntu"
                if [[ "$DISTRO_ID" == "neon" ]]; then
                    if [[ -f /etc/upstream-release/lsb-release ]]; then
                        docker_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                    fi
                    docker_codename="${docker_codename:-noble}"
                fi
            fi

            run_as_root_sh "curl -fsSL https://download.docker.com/linux/${docker_dist}/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
            run_as_root chmod 644 /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${docker_dist} ${docker_codename} stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root apt-get update
            run_as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;

        dnf|yum)
            run_as_root_sh "$PKG_MGR install -y dnf-plugins-core 2>/dev/null || $PKG_MGR install -y yum-utils"

            local docker_repo
            [[ "$DISTRO_ID" == "fedora" ]] && docker_repo="https://download.docker.com/linux/fedora/docker-ce.repo" || docker_repo="https://download.docker.com/linux/centos/docker-ce.repo"

            run_as_root curl -fsSLo /etc/yum.repos.d/docker-ce.repo "${docker_repo}"
            run_as_root "$PKG_MGR" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            run_as_root systemctl start docker
            run_as_root systemctl enable docker
            ;;

        zypper)
            run_as_root zypper install -y docker docker-compose
            run_as_root systemctl start docker
            run_as_root systemctl enable docker
            ;;

        pacman)
            run_as_root pacman -S --noconfirm docker docker-compose docker-buildx
            run_as_root systemctl enable --now containerd.service
            run_as_root systemctl enable --now docker.service
            ;;

        *)
            error "Docker installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    run_as_root_sh "groupadd docker 2>/dev/null || true"
    run_as_root usermod -aG docker "${USER}" || warn "Failed to add ${USER} to docker group — you may need to run docker with sudo."

    info "Docker installed successfully. You may need to log out and back in for group membership to take effect."

    sudo docker version &>/dev/null && info "Docker verification complete."

    return 0
}

check_docker() {
    _run_native docker --version &>/dev/null
}

uninstall_docker() {
    info "Uninstalling Docker..."
    run_as_root systemctl stop docker 2>/dev/null || true
    run_as_root systemctl disable docker 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            run_as_root rm -f /etc/apt/sources.list.d/docker.list
            run_as_root rm -f /usr/share/keyrings/docker-archive-keyring.gpg
            run_as_root rm -f /etc/apt/keyrings/docker.gpg
            ;;
        fedora|rhel)
            pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            pkg_remove docker docker-compose docker-buildx
            ;;
        suse)
            pkg_remove docker docker-compose docker-buildx
            ;;
    esac
    rm -rf ~/.config/docker
    rm -rf ~/.docker
}

update_docker() {
    info "Updating Docker..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora|rhel)
            pkg_upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            pkg_upgrade docker docker-compose docker-buildx
            ;;
        suse)
            pkg_upgrade docker docker-compose docker-buildx
            ;;
    esac
}
get_version_docker() {
    _run_native docker --version 2>/dev/null | grep -oP 'Docker version \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}
