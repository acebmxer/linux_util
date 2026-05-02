#!/bin/bash
# NVIDIA Drivers installer functions

# --- NVIDIA Drivers & Toolkit ---
check_nvidia_drivers() {
    command -v nvidia-smi &>/dev/null || lsmod | grep -q "^nvidia"
}
get_version_nvidia_drivers() {
    local ver
    if ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null); then
        echo "$ver" | head -1
    else
        echo ""
    fi
}

install_nvtop_package() {
    echo "Installing nvtop..."
    case "$PKG_MGR" in
        apt)
            sudo apt-get update
            sudo apt-get install -y nvtop
            ;;
        dnf|yum)
            sudo "$PKG_MGR" install -y nvtop
            ;;
        pacman)
            sudo pacman -S --noconfirm nvtop
            ;;
        zypper)
            sudo zypper install -y nvtop
            ;;
    esac
}

install_nvidia_container_toolkit() {
    echo "Installing NVIDIA Container Toolkit for Docker..."
    case "$DISTRO_FAMILY" in
        debian)
            ensure_tools
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
            sudo apt-get update
            sudo apt-get install -y nvidia-container-toolkit
            ;;
        fedora|rhel)
            ensure_tools
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo "$PKG_MGR" makecache
            sudo "$PKG_MGR" install -y nvidia-container-toolkit
            ;;
        arch)
            pkg_install nvidia-container-toolkit
            ;;
        suse)
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/zypp/repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo zypper refresh
            sudo zypper install -y nvidia-container-toolkit
            ;;
        *)
            warn "NVIDIA Container Toolkit installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, openSUSE."
            warn "Manual instructions: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
            return 1
            ;;
    esac
}

# --- NVIDIA i386 / 32-bit library helpers ---

# Save the selected NVIDIA driver version to a persistent config file so that
# other installers (e.g. Steam) can reference it later.
save_nvidia_driver_version() {
    local version="$1"
    mkdir -p "$(dirname "$NVIDIA_VERSION_FILE")"
    echo "$version" > "$NVIDIA_VERSION_FILE"
}

# Return the saved NVIDIA driver version, falling back to package detection.
get_nvidia_installed_version() {
    if [[ -f "$NVIDIA_VERSION_FILE" ]]; then
        cat "$NVIDIA_VERSION_FILE"
        return 0
    fi
    # Fallback: detect from installed packages
    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l 'nvidia-driver-*' 2>/dev/null | grep '^ii' | \
                grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | head -1
            ;;
        fedora|rhel)
            rpm -qa 'akmod-nvidia*' 'kmod-nvidia*' 2>/dev/null | \
                grep -oP '(?:akmod|kmod)-nvidia-\K[0-9]+' | sort -rn | head -1
            ;;
        arch)
            pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}' | cut -d- -f1
            ;;
        suse)
            rpm -qa 'nvidia-driver*' 2>/dev/null | \
                grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

# Return 0 if the matching NVIDIA 32-bit libraries are already installed.
check_nvidia_i386_libs() {
    local driver_version
    driver_version=$(get_nvidia_installed_version)
    [[ -z "$driver_version" ]] && return 1

    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l "libnvidia-gl-${driver_version}:i386" 2>/dev/null | grep -q '^ii'
            ;;
        fedora|rhel)
            rpm -q nvidia-driver-libs.i686 &>/dev/null || \
                rpm -q xorg-x11-drv-nvidia-470xx-libs.i686 &>/dev/null || \
                rpm -q xorg-x11-drv-nvidia-390xx-libs.i686 &>/dev/null
            ;;
        arch)
            pacman -Qi lib32-nvidia-utils &>/dev/null
            ;;
        suse)
            rpm -q nvidia-32bit &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Install the NVIDIA 32-bit libraries that match the installed driver version.
# An explicit version can be passed as $1; otherwise the saved version is used.
install_nvidia_i386_libs() {
    local driver_version="${1:-}"
    if [[ -z "$driver_version" ]]; then
        driver_version=$(get_nvidia_installed_version)
    fi

    if [[ -z "$driver_version" ]]; then
        warn "Cannot determine NVIDIA driver version for 32-bit library installation."
        return 1
    fi

    echo "Installing NVIDIA 32-bit libraries (version ${driver_version})..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo dpkg --add-architecture i386
            sudo apt update

            # Show currently installed NVIDIA driver to confirm version
            echo "Installed NVIDIA driver packages:"
            dpkg -l | grep nvidia-driver || echo "  (none found)"

            echo "Installing libnvidia-gl-${driver_version}:i386..."
            if ! sudo apt install -y "libnvidia-gl-${driver_version}:i386"; then
                echo ""
                echo "⚠  libnvidia-gl-${driver_version}:i386 is unavailable via apt."
                echo "Alternative: manually extract 32-bit libraries from the NVIDIA installer."
                echo ""
                echo "  1. Download the driver .run file from NVIDIA's website:"
                echo "     https://www.nvidia.com/en-us/drivers/"
                echo "     (e.g. NVIDIA-Linux-x86_64-${driver_version}.run)"
                echo ""
                echo "  2. Extract the installer:"
                echo "     sudo ./NVIDIA-Linux-x86_64-${driver_version}.run -x"
                echo ""
                echo "  3. Copy 32-bit libraries to /usr/lib32:"
                echo "     sudo cp NVIDIA-Linux-x86_64-${driver_version}/32/*.so* /usr/lib32/"
                echo "     sudo ldconfig"
                echo ""
                warn "32-bit library installation incomplete. Use the manual method above if needed."
                return 1
            fi
            ;;
        fedora|rhel)
            case "$driver_version" in
                470xx)
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-470xx-libs.i686
                    ;;
                390xx)
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-390xx-libs.i686
                    ;;
                *)
                    sudo "$PKG_MGR" install -y nvidia-driver-libs.i686
                    ;;
            esac
            ;;
        arch)
            sudo pacman -S --noconfirm lib32-nvidia-utils
            ;;
        suse)
            if [[ "$driver_version" =~ ^G0[0-9]$ ]]; then
                sudo zypper install -y "nvidia-${driver_version}-32bit" 2>/dev/null || \
                    sudo zypper install -y nvidia-32bit 2>/dev/null || true
            else
                sudo zypper install -y "libnvidia-gl${driver_version}-32bit" 2>/dev/null || \
                    sudo zypper install -y nvidia-32bit 2>/dev/null || true
            fi
            ;;
        *)
            warn "NVIDIA 32-bit library installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, openSUSE."
            warn "Install 32-bit libs manually from: https://www.nvidia.com/en-us/drivers/"
            return 1
            ;;
    esac
}

install_nvidia_drivers() {
    echo "Installing NVIDIA drivers..."
    ensure_tools

    local driver_version=""
    local -a available_drivers=()

    # Detect available NVIDIA drivers based on distribution
    case "$DISTRO_FAMILY" in
        debian)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1
            
            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                command -v ubuntu-drivers &>/dev/null || sudo apt-get install -y ubuntu-drivers-common
                mapfile -t available_drivers < <(ubuntu-drivers list --gpgpu 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            else
                # Debian and derivatives
                mapfile -t available_drivers < <(apt-cache search '^nvidia-driver-[0-9]+$' 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            fi
            ;;
        fedora|rhel)
            echo "Detecting available NVIDIA drivers..."
            
            # Check if RPM Fusion (nonfree) is enabled
            if ! dnf repolist 2>/dev/null | grep -qi 'rpmfusion.*nonfree'; then
                echo ""
                echo "[!] RPM Fusion (nonfree) repository is required for NVIDIA drivers on Fedora/RHEL."
                echo ""
                read -rp "Would you like to enable RPM Fusion repositories now? (y/N): " enable_rpmfusion < /dev/tty
                
                if [[ "$enable_rpmfusion" =~ ^[Yy]$ ]]; then
                    echo "Enabling RPM Fusion repositories..."
                    if [[ "$DISTRO_ID" == "fedora" ]]; then
                        sudo "$PKG_MGR" install -y \
                            "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" \
                            "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    else
                        # RHEL/CentOS
                        sudo "$PKG_MGR" install -y \
                            "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" \
                            "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    fi
                    pkg_refresh >/dev/null 2>&1
                else
                    warn "RPM Fusion is required for NVIDIA drivers. Installation cancelled."
                    return 1
                fi
            fi
            
            pkg_refresh >/dev/null 2>&1
            
            # Check for available NVIDIA driver packages
            # Main driver: akmod-nvidia (latest, recommended)
            if $PKG_MGR list available akmod-nvidia &>/dev/null; then
                available_drivers+=("latest")
            fi
            
            # Legacy drivers
            if $PKG_MGR list available xorg-x11-drv-nvidia-470xx &>/dev/null; then
                available_drivers+=("470xx")
            fi
            
            if $PKG_MGR list available xorg-x11-drv-nvidia-390xx &>/dev/null; then
                available_drivers+=("390xx")
            fi
            
            # Also check for any kmod-nvidia versioned packages
            local kmod_versions
            mapfile -t kmod_versions < <($PKG_MGR list available 'kmod-nvidia-*' 2>/dev/null | grep -oP 'kmod-nvidia-\K[0-9]+' | sort -rn | uniq)
            available_drivers+=("${kmod_versions[@]}")
            ;;
        arch)
            echo "Detecting available NVIDIA drivers..."
            if [[ "${DISTRO_ID:-}" == "cachyos" ]]; then
                # CachyOS ships kernel-paired nvidia-open modules instead of vanilla
                # nvidia/nvidia-dkms/nvidia-lts. Offer one entry per installed
                # cachyos kernel that has a matching -nvidia-open package in repos,
                # plus nvidia-open-dkms as a universal DKMS fallback.
                local installed_kernels
                mapfile -t installed_kernels < <(pacman -Q 2>/dev/null \
                    | awk '{print $1}' \
                    | grep '^linux-cachyos' \
                    | grep -v '\-headers$\|-nvidia')
                for kern in "${installed_kernels[@]}"; do
                    local mod_pkg="${kern}-nvidia-open"
                    if pacman -Si "$mod_pkg" &>/dev/null; then
                        available_drivers+=("$mod_pkg")
                    fi
                done
                # nvidia-open-dkms works with any kernel (DKMS rebuild on upgrade)
                if pacman -Si nvidia-open-dkms &>/dev/null; then
                    available_drivers+=("nvidia-open-dkms")
                fi
            else
                # Vanilla Arch / Manjaro / other Arch derivatives
                available_drivers=("latest" "dkms" "lts")
            fi
            ;;
        suse)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1
            
            mapfile -t available_drivers < <(zypper search -s nvidia-driver 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            
            # Check for G06/G05 packages (openSUSE naming)
            if zypper search -s nvidia-computeG06 &>/dev/null; then
                available_drivers+=("G06")
            fi
            if zypper search -s nvidia-computeG05 &>/dev/null; then
                available_drivers+=("G05")
            fi
            ;;
        *)
            warn "NVIDIA driver detection not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, openSUSE."
            warn "Install drivers manually from: https://www.nvidia.com/en-us/drivers/"
            return 1
            ;;
    esac

    # Display available drivers and let user select
    if [[ ${#available_drivers[@]} -eq 0 ]]; then
        warn "No NVIDIA drivers found in repositories. Please check your repository configuration."
        return 1
    fi

    echo ""
    echo "Available NVIDIA driver versions:"
    echo "────────────────────────────────────────────────────────────────"
    for i in "${!available_drivers[@]}"; do
        echo "  $((i+1)). ${available_drivers[$i]}"
    done
    echo "  0. Cancel"
    echo "────────────────────────────────────────────────────────────────"
    
    local choice
    read -rp "Select driver version to install (1-${#available_drivers[@]}, or 0 to cancel): " choice < /dev/tty
    
    if [[ "$choice" == "0" ]] || [[ -z "$choice" ]]; then
        warn "Installation cancelled."
        return 2
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#available_drivers[@]} ]]; then
        driver_version="${available_drivers[$((choice-1))]}"
        echo "Selected driver version: $driver_version"
        # Persist the chosen version so other installers (e.g. Steam) can reference it
        save_nvidia_driver_version "$driver_version"
    else
        warn "Invalid selection. Cancelling installation."
        return 1
    fi

    # Install the selected driver
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get update
            sudo apt-get install -y "nvidia-driver-${driver_version}"
            ;;
        fedora|rhel)
            case "$driver_version" in
                latest)
                    echo "Installing latest NVIDIA driver (akmod-nvidia)..."
                    sudo "$PKG_MGR" install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
                    ;;
                470xx)
                    echo "Installing legacy NVIDIA 470 driver..."
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-470xx akmod-nvidia-470xx
                    ;;
                390xx)
                    echo "Installing legacy NVIDIA 390 driver..."
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-390xx akmod-nvidia-390xx
                    ;;
                [0-9]*)
                    echo "Installing NVIDIA driver version ${driver_version}..."
                    sudo "$PKG_MGR" install -y "kmod-nvidia-${driver_version}"
                    ;;
                *)
                    warn "Unknown driver version: ${driver_version}"
                    return 1
                    ;;
            esac
            ;;
        arch)
            case "$driver_version" in
                linux-cachyos*-nvidia-open|nvidia-open-dkms)
                    # CachyOS: kernel-paired or DKMS open module + utils
                    sudo pacman -S --noconfirm "$driver_version" nvidia-utils
                    ;;
                latest)
                    sudo pacman -S --noconfirm nvidia nvidia-utils
                    ;;
                dkms)
                    sudo pacman -S --noconfirm nvidia-dkms nvidia-utils
                    ;;
                lts)
                    sudo pacman -S --noconfirm nvidia-lts nvidia-utils
                    ;;
            esac
            ;;
        suse)
            if [[ "$driver_version" =~ ^G0[0-9]$ ]]; then
                sudo zypper install -y "nvidia-compute${driver_version}"
            else
                sudo zypper install -y "nvidia-driver-${driver_version}"
            fi
            ;;
        *)
            warn "NVIDIA driver installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, openSUSE."
            warn "Install drivers manually from: https://www.nvidia.com/en-us/drivers/"
            return 1
            ;;
    esac

    # Install matching 32-bit libraries (required by Steam and other 32-bit apps)
    install_nvidia_i386_libs "$driver_version"

    install_nvtop_package

    if check_docker; then
        install_nvidia_container_toolkit || warn "Failed to install NVIDIA Container Toolkit."
    else
        info "Docker not detected. Skipping NVIDIA Container Toolkit installation."
    fi
}

uninstall_nvidia_drivers() {
    info "Uninstalling NVIDIA drivers..."
    case "$PKG_MGR" in
        apt)
            sudo apt-get purge --autoremove -y 'nvidia-driver-*' nvtop
            sudo apt-get autoclean
            ;;
        dnf|yum)
            sudo "$PKG_MGR" remove -y 'nvidia*' nvtop
            ;;
        pacman)
            # Remove any installed nvidia module packages (vanilla or CachyOS kernel-paired)
            local _nvidia_pkgs
            mapfile -t _nvidia_pkgs < <(pacman -Q 2>/dev/null \
                | awk '{print $1}' \
                | grep -E '^(nvidia|linux-cachyos.*-nvidia)')
            [[ ${#_nvidia_pkgs[@]} -gt 0 ]] && \
                sudo pacman -Rs --noconfirm "${_nvidia_pkgs[@]}" 2>/dev/null || true
            sudo pacman -Rs --noconfirm nvtop 2>/dev/null || true
            ;;
        zypper)
            sudo zypper remove -y 'nvidia*' nvtop
            ;;
    esac
    rm -rf ~/.config/nvidia
    rm -rf ~/.nv
}

update_nvidia_drivers() {
    install_nvidia_drivers
}
