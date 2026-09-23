#!/bin/bash
# NVIDIA Drivers installer functions

# --- Debian-family helpers ---------------------------------------------------

# Return 0 when the running distro uses Ubuntu's NVIDIA packaging conventions
# (versioned nvidia-driver-<NNN> metapackages + ubuntu-drivers). This covers
# Ubuntu itself and its derivatives (Mint, Pop!_OS, Zorin, elementary, KDE neon)
# while leaving Debian proper and Debian-based distros (Debian, Kali, MX...) to
# the Debian code path, which uses unversioned metapackages.
_nvidia_is_ubuntu_like() {
    [[ "${DISTRO_ID:-}" == "ubuntu" ]] && return 0
    local id_like
    id_like=$(. /etc/os-release 2>/dev/null; echo "${ID_LIKE:-}")
    [[ " $id_like " == *" ubuntu "* ]] && return 0
    command -v ubuntu-drivers &>/dev/null && return 0
    return 1
}

# Ensure Debian's contrib + non-free components are enabled, which is required
# for the NVIDIA driver packages. Handles both the modern deb822 .sources format
# (the Debian 13 default) and the legacy one-line sources.list. Idempotent;
# prompts before modifying anything and backs up every file it edits.
_debian_enable_nonfree() {
    # Already usable? nvidia-detect lives in non-free, so a real candidate for it
    # means contrib/non-free are already enabled.
    if apt-cache policy nvidia-detect 2>/dev/null | grep -q 'Candidate:' \
        && ! apt-cache policy nvidia-detect 2>/dev/null | grep -q 'Candidate: (none)'; then
        return 0
    fi

    echo ""
    echo "[!] Debian's 'contrib' and 'non-free' components are required for NVIDIA drivers."
    local ans
    while true; do
        read -rp "Enable contrib/non-free in your apt sources now? (y/N): " ans < /dev/tty
        case "${ans,,}" in
            y|yes) break ;;
            n|no|'') warn "contrib/non-free not enabled. NVIDIA driver install cancelled."; return 1 ;;
            *) echo "  Please enter Y or N." ;;
        esac
    done

    local changed=false
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local f

    # --- deb822 format (.sources) — Debian 13 default ---
    for f in /etc/apt/sources.list.d/*.sources; do
        [[ -e "$f" ]] || continue
        # Only touch base Debian repos: Components lines that include 'main' and
        # do not already carry a standalone 'non-free' component.
        if grep -qE '^[[:space:]]*Components:.*\bmain\b' "$f" \
           && ! grep -qE '^[[:space:]]*Components:.*non-free([[:space:]]|$)' "$f"; then
            sudo cp -a "$f" "${f}.linuxutil.bak.${ts}"
            sudo awk '
                /^[[:space:]]*Components:/ {
                    has_main=0
                    for (i=2;i<=NF;i++) if ($i=="main") has_main=1
                    if (has_main) {
                        delete seen
                        for (i=2;i<=NF;i++) seen[$i]=1
                        out=""
                        for (i=2;i<=NF;i++) out=out" "$i
                        if (!("contrib" in seen))           out=out" contrib"
                        if (!("non-free" in seen))          out=out" non-free"
                        if (!("non-free-firmware" in seen)) out=out" non-free-firmware"
                        print "Components:" out
                        next
                    }
                }
                { print }
            ' "$f" | sudo tee "${f}.tmp" >/dev/null && sudo mv "${f}.tmp" "$f"
            changed=true
        fi
    done

    # --- legacy one-line format (sources.list) ---
    if [[ -f /etc/apt/sources.list ]] \
       && grep -qE '^[[:space:]]*deb(-src)?[[:space:]].*\bmain\b' /etc/apt/sources.list \
       && ! grep -qE '^[[:space:]]*deb(-src)?[[:space:]].*non-free([[:space:]]|$)' /etc/apt/sources.list; then
        sudo cp -a /etc/apt/sources.list "/etc/apt/sources.list.linuxutil.bak.${ts}"
        sudo sed -i -E \
            '/^[[:space:]]*deb(-src)?[[:space:]].*\bmain\b/{/non-free([[:space:]]|$)/!s/[[:space:]]*$/ contrib non-free non-free-firmware/}' \
            /etc/apt/sources.list
        changed=true
    fi

    if [[ "$changed" == false ]]; then
        warn "Could not locate a Debian base repo to modify automatically."
        warn "Please enable 'contrib non-free non-free-firmware' manually. See:"
        warn "  https://wiki.debian.org/SourcesList"
        return 1
    fi

    info "Enabled contrib/non-free. Refreshing package lists..."
    sudo apt-get update
    return 0
}

# --- NVIDIA Drivers & Toolkit ---
check_nvidia_drivers() {
    _have_cmd nvidia-smi || lsmod | grep -q "^nvidia"
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
            pkg_install nvtop
            ;;
        pacman)
            pkg_install nvtop
            ;;
        zypper)
            pkg_install nvtop
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
            pkg_install nvidia-container-toolkit
            ;;
        arch)
            pkg_install nvidia-container-toolkit
            ;;
        suse)
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/zypp/repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo zypper refresh
            pkg_install nvidia-container-toolkit
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
            # openSUSE identifies installed drivers by GPU generation (G04-G07),
            # not a numeric branch — see install_nvidia_drivers's suse case.
            rpm -qa 'nvidia-compute*' 'nvidia-driver-G0*-kmp-*' 2>/dev/null | \
                grep -oP 'G0[4-9]' | sort -ru | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

# Return 0 if the matching NVIDIA 32-bit libraries are already installed.
check_nvidia_i386_libs() {
    # Debian proper uses an unversioned 32-bit metapackage; check it directly
    # without needing a numeric driver version.
    if [[ "$DISTRO_FAMILY" == "debian" ]] && ! _nvidia_is_ubuntu_like; then
        dpkg -l 'nvidia-driver-libs:i386' 2>/dev/null | grep -q '^ii' && return 0
        dpkg -l 'nvidia-legacy-*-driver-libs:i386' 2>/dev/null | grep -q '^ii' && return 0
        dpkg -l 'nvidia-tesla-*-driver-libs:i386' 2>/dev/null | grep -q '^ii' && return 0
        return 1
    fi

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
            # No generic 'nvidia-32bit' package exists on openSUSE's NVIDIA
            # repo (verified) — the naming is per-generation, see the install
            # side of this in install_nvidia_i386_libs.
            rpm -q "nvidia-compute${driver_version}-32bit" &>/dev/null || \
                rpm -q "nvidia-compute-${driver_version}-32bit" &>/dev/null
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

    # Debian proper installs an unversioned 32-bit metapackage, so a numeric
    # driver version is not required there.
    local _debian_proper=false
    if [[ "$DISTRO_FAMILY" == "debian" ]] && ! _nvidia_is_ubuntu_like; then
        _debian_proper=true
    fi

    if [[ -z "$driver_version" && "$_debian_proper" == false ]]; then
        driver_version=$(get_nvidia_installed_version)
    fi

    if [[ -z "$driver_version" && "$_debian_proper" == false ]]; then
        warn "Cannot determine NVIDIA driver version for 32-bit library installation."
        return 1
    fi

    if [[ "$_debian_proper" == true ]]; then
        echo "Installing NVIDIA 32-bit libraries..."
    else
        echo "Installing NVIDIA 32-bit libraries (version ${driver_version})..."
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo dpkg --add-architecture i386
            sudo apt-get update

            if _nvidia_is_ubuntu_like; then
                # Ubuntu-style versioned 32-bit GL libs.
                echo "Installing libnvidia-gl-${driver_version}:i386..."
                if ! sudo apt-get install -y "libnvidia-gl-${driver_version}:i386"; then
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
            else
                # Debian proper: an unversioned metapackage that matches the
                # installed driver and pulls the correct 32-bit libs. Legacy
                # drivers ship their own -libs:i386 metapackage.
                local i386_pkg="nvidia-driver-libs:i386"
                case "$driver_version" in
                    nvidia-legacy-*-driver|nvidia-tesla-*-driver)
                        i386_pkg="${driver_version}-libs:i386" ;;
                esac
                echo "Installing ${i386_pkg}..."
                if ! sudo apt-get install -y "$i386_pkg"; then
                    warn "${i386_pkg} is unavailable via apt; 32-bit libraries not installed."
                    warn "Verify the i386 architecture and contrib/non-free are enabled."
                    return 1
                fi
            fi
            ;;
        fedora|rhel)
            case "$driver_version" in
                580xx)
                    pkg_install xorg-x11-drv-nvidia-580xx-libs.i686
                    ;;
                470xx)
                    pkg_install xorg-x11-drv-nvidia-470xx-libs.i686
                    ;;
                390xx)
                    pkg_install xorg-x11-drv-nvidia-390xx-libs.i686
                    ;;
                *)
                    pkg_install nvidia-driver-libs.i686
                    ;;
            esac
            ;;
        arch)
            pkg_install lib32-nvidia-utils
            ;;
        suse)
            # openSUSE's NVIDIA repo names 32-bit packages differently across
            # GPU generations (verified against the real repo, not booted):
            # G04/G05 (older, Kepler-and-earlier) use no hyphen —
            # nvidia-computeG05-32bit. G06/G07 (Maxwell-and-later) use a
            # hyphen — nvidia-compute-G06-32bit / nvidia-compute-G07-32bit.
            case "$driver_version" in
                G04|G05)
                    pkg_install "nvidia-compute${driver_version}-32bit"
                    ;;
                G06|G07)
                    pkg_install "nvidia-compute-${driver_version}-32bit"
                    ;;
                *)
                    pkg_install "libnvidia-gl${driver_version}-32bit" 2>/dev/null || pkg_install nvidia-32bit 2>/dev/null || true
                    ;;
            esac
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
    # Parallel to available_drivers: what to print in the menu for each entry.
    # available_drivers holds the value used to build package names later, so
    # it can't carry a human-friendly "580xx (580.178.04)" string itself —
    # that goes here instead, indexed the same way.
    local -a available_labels=()

    # Look up a package's newest available version string, or print nothing.
    # Used to annotate menu labels like "latest (610.57.04)" so version
    # numbers shown are real, queried values, not guesses.
    _nvidia_pkg_version() {
        case "$PKG_MGR" in
            dnf|yum)
                "$PKG_MGR" --quiet repoquery --latest-limit=1 --qf '%{version}' "$1" 2>/dev/null
                ;;
            apt)
                apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
                ;;
            zypper)
                zypper --non-interactive info "$1" 2>/dev/null | awk -F': *' '/^Version/ {print $2; exit}'
                ;;
            pacman)
                pacman -Si "$1" 2>/dev/null | awk -F': *' '/^Version/ {print $2; exit}'
                ;;
        esac
    }

    # Build "label (version)" if a version was found, else just "label".
    # Use this where the label alone doesn't tell you a version (e.g. "latest").
    _nvidia_labeled() {
        local label="$1" pkg="$2" ver
        ver=$(_nvidia_pkg_version "$pkg")
        if [[ -n "$ver" ]]; then
            echo "${label} (${ver})"
        else
            echo "$label"
        fi
    }

    # Show just the real version number, falling back to the branch label if
    # no version was found. Use this for branch names that are themselves
    # redundant once the version is known (e.g. "580xx" -> "580.178.04"),
    # unlike "latest" which carries no version information on its own.
    _nvidia_version_only() {
        local label="$1" pkg="$2" ver
        ver=$(_nvidia_pkg_version "$pkg")
        if [[ -n "$ver" ]]; then
            echo "$ver"
        else
            echo "$label"
        fi
    }

    # Detect available NVIDIA drivers based on distribution
    case "$DISTRO_FAMILY" in
        debian)
            echo "Detecting available NVIDIA drivers..."

            if _nvidia_is_ubuntu_like; then
                # --- Ubuntu and Ubuntu-based derivatives ---
                # Versioned metapackages: nvidia-driver-<NNN>, surfaced by
                # ubuntu-drivers with an apt-cache fallback.
                pkg_refresh >/dev/null 2>&1
                command -v ubuntu-drivers &>/dev/null || sudo apt-get install -y ubuntu-drivers-common
                mapfile -t available_drivers < <(ubuntu-drivers list --gpgpu 2>/dev/null \
                    | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
                if [[ ${#available_drivers[@]} -eq 0 ]]; then
                    mapfile -t available_drivers < <(apt-cache search '^nvidia-driver-[0-9]+$' 2>/dev/null \
                        | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
                fi
                local _branch
                for _branch in "${available_drivers[@]}"; do
                    available_labels+=("$(_nvidia_version_only "$_branch" "nvidia-driver-${_branch}")")
                done
            else
                # --- Debian proper and Debian-based derivatives ---
                # Debian ships *unversioned* driver metapackages (nvidia-driver,
                # nvidia-tesla-<NNN>-driver, nvidia-legacy-<NNN>xx-driver) in
                # contrib/non-free, NOT Ubuntu-style nvidia-driver-<NNN>. The
                # contrib/non-free components are also disabled by default on
                # Debian 13, so enable them first.
                _debian_enable_nonfree || return 1
                pkg_refresh >/dev/null 2>&1

                # nvidia-detect (non-free) recommends the correct package for
                # the installed GPU.
                local recommended_pkg=""
                if sudo apt-get install -y nvidia-detect >/dev/null 2>&1; then
                    recommended_pkg=$(nvidia-detect 2>/dev/null \
                        | grep -A3 -i 'It is recommended' \
                        | grep -oE 'nvidia[a-z0-9.-]*-driver' | head -1)
                    [[ -n "$recommended_pkg" ]] && info "nvidia-detect recommends: ${recommended_pkg}"
                fi

                # Enumerate the driver metapackages actually present in the repos.
                mapfile -t available_drivers < <(
                    apt-cache pkgnames nvidia 2>/dev/null \
                        | grep -E '^nvidia-(driver|tesla(-[0-9]+)?-driver|legacy-[0-9]+xx-driver)$' \
                        | sort -u
                )

                # Surface the recommended package as the first menu option.
                if [[ -n "$recommended_pkg" ]]; then
                    local -a _reordered=("$recommended_pkg") _p
                    for _p in "${available_drivers[@]}"; do
                        [[ "$_p" == "$recommended_pkg" ]] || _reordered+=("$_p")
                    done
                    available_drivers=("${_reordered[@]}")
                fi

                # Debian proper's available_drivers entries are already the
                # full metapackage name, so query each one directly.
                for _p in "${available_drivers[@]}"; do
                    local _label="$_p"
                    [[ "$_p" == "$recommended_pkg" ]] && _label="${_p} — recommended"
                    available_labels+=("$(_nvidia_labeled "$_label" "$_p")")
                done
            fi
            ;;
        fedora|rhel)
            echo "Detecting available NVIDIA drivers..."
            
            # Check if RPM Fusion (nonfree) is enabled
            if ! dnf repolist 2>/dev/null | grep -qi 'rpmfusion.*nonfree'; then
                echo ""
                echo "[!] RPM Fusion (nonfree) repository is required for NVIDIA drivers on Fedora/RHEL."
                echo ""
                while true; do
                    read -rp "Would you like to enable RPM Fusion repositories now? (y/N): " enable_rpmfusion < /dev/tty
                    case "${enable_rpmfusion,,}" in
                        y|yes|n|no|'') break ;;
                        *) echo "  Please enter Y or N." ;;
                    esac
                done
                if [[ "$enable_rpmfusion" =~ ^[Yy]$ ]]; then
                    echo "Enabling RPM Fusion repositories..."
                    if [[ "$DISTRO_ID" == "fedora" ]]; then
                        pkg_install "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    else
                        # RHEL/CentOS
                        pkg_install "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    fi
                    pkg_refresh >/dev/null 2>&1
                else
                    warn "RPM Fusion is required for NVIDIA drivers. Installation cancelled."
                    return 1
                fi
            fi
            
            pkg_refresh >/dev/null 2>&1

            # Check for available NVIDIA driver packages
            # -y: any repo on the system with an unimported GPG key (e.g. one
            # added earlier by the NVIDIA Container Toolkit installer, a
            # completely separate repo from RPM Fusion) makes dnf prompt
            # "Is this ok [y/N]" on ITS FIRST use of any repo that session --
            # not just when installing from it. Without -y that prompt blocks
            # forever here, since this call has no controlling terminal to
            # answer it and no timeout: a one-off menu freeze was traced to
            # exactly this on 2026-09-12.
            # Main driver: akmod-nvidia (latest, recommended)
            if $PKG_MGR -y list available akmod-nvidia &>/dev/null; then
                available_drivers+=("latest")
                available_labels+=("$(_nvidia_labeled "latest" "akmod-nvidia")")
            fi

            # Legacy drivers: RPM Fusion ships these as kmod-nvidia-<NNN>xx
            # (the akmod-<NNN>xx variant is what actually gets rebuilt on
            # kernel upgrades). Match only the "xx"-suffixed branch names —
            # a bare 'kmod-nvidia-*' glob also matches per-kernel build
            # artifacts like kmod-nvidia-7.2.4-200.fc44.x86_64.x86_64, whose
            # kernel-version numbers are not installable driver branches.
            local legacy_branch
            for legacy_branch in 580xx 470xx 390xx; do
                if $PKG_MGR -y list available "akmod-nvidia-${legacy_branch}" &>/dev/null \
                    || $PKG_MGR -y list available "kmod-nvidia-${legacy_branch}" &>/dev/null; then
                    available_drivers+=("$legacy_branch")
                    available_labels+=("$(_nvidia_version_only "$legacy_branch" "akmod-nvidia-${legacy_branch}")")
                fi
            done
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
                        available_labels+=("$(_nvidia_labeled "$mod_pkg" "$mod_pkg")")
                    fi
                done
                # nvidia-open-dkms works with any kernel (DKMS rebuild on upgrade)
                if pacman -Si nvidia-open-dkms &>/dev/null; then
                    available_drivers+=("nvidia-open-dkms")
                    available_labels+=("$(_nvidia_labeled "nvidia-open-dkms" "nvidia-open-dkms")")
                fi
            else
                # Vanilla Arch / Manjaro / other Arch derivatives
                available_drivers=("latest" "dkms" "lts")
                available_labels=(
                    "$(_nvidia_labeled "latest" "nvidia")"
                    "$(_nvidia_labeled "dkms" "nvidia-dkms")"
                    "$(_nvidia_labeled "lts" "nvidia-lts")"
                )
            fi
            ;;
        suse)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1

            # openSUSE's NVIDIA repo names packages by GPU generation, and the
            # naming scheme itself differs across generations (all verified
            # against the real NVIDIA openSUSE repo — there is no bare
            # 'nvidia-driver-<NNN>' package the way there is on Ubuntu):
            #   G04/G05 (Kepler-and-earlier): no hyphen, e.g. nvidia-computeG05
            #     is the actual metapackage to install.
            #   G06 (Maxwell-through-Turing): hyphenated component names, e.g.
            #     nvidia-compute-G06 exists but is not the top-level
            #     metapackage — that's nvidia-driver-G06-kmp-meta ("Meta
            #     package to select proprietary nvidia driver", per its own
            #     description). A previous version of this check queried
            #     'nvidia-computeG06' (no hyphen), which does not exist, so
            #     G06 was never offered.
            #   G07 (newest cards): the repo currently ships only the
            #     open-source kernel module variant
            #     (nvidia-open-driver-G07-signed-kmp-meta) — there is no
            #     nvidia-driver-G07-kmp-meta (proprietary) package to offer.
            if zypper search -s "nvidia-open-driver-G07-signed-kmp-meta" &>/dev/null; then
                available_drivers+=("G07")
                available_labels+=("$(_nvidia_labeled "G07 (open kernel module)" "nvidia-open-driver-G07-signed-kmp-meta")")
            fi
            if zypper search -s "nvidia-driver-G06-kmp-meta" &>/dev/null; then
                available_drivers+=("G06")
                available_labels+=("$(_nvidia_version_only "G06" "nvidia-driver-G06-kmp-meta")")
            fi
            local gen
            for gen in G05 G04; do
                if zypper search -s "nvidia-compute${gen}" &>/dev/null; then
                    available_drivers+=("$gen")
                    available_labels+=("$(_nvidia_version_only "$gen" "nvidia-compute${gen}")")
                fi
            done
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
        # available_labels should be filled in parallel to available_drivers
        # by every detection branch above; fall back to the raw value if a
        # label is missing so the menu never prints a blank line.
        echo "  $((i+1)). ${available_labels[$i]:-${available_drivers[$i]}}"
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
            if _nvidia_is_ubuntu_like; then
                # driver_version is a numeric branch (e.g. 550)
                sudo apt-get install -y "nvidia-driver-${driver_version}"
            else
                # Debian proper: driver_version holds the metapackage name.
                # Kernel headers must be present first or DKMS can't build the
                # module (required since Debian 13 / kernel 6.12).
                echo "Installing kernel headers for DKMS..."
                if ! sudo apt-get install -y "linux-headers-$(uname -r)" linux-headers-amd64; then
                    sudo apt-get install -y linux-headers-amd64 \
                        || warn "Could not install kernel headers; DKMS module build may fail."
                fi
                sudo apt-get install -y "$driver_version"
            fi
            ;;
        fedora|rhel)
            case "$driver_version" in
                latest)
                    echo "Installing latest NVIDIA driver (akmod-nvidia)..."
                    pkg_install akmod-nvidia xorg-x11-drv-nvidia-cuda
                    ;;
                580xx)
                    echo "Installing legacy NVIDIA 580 driver..."
                    pkg_install xorg-x11-drv-nvidia-580xx akmod-nvidia-580xx
                    ;;
                470xx)
                    echo "Installing legacy NVIDIA 470 driver..."
                    pkg_install xorg-x11-drv-nvidia-470xx akmod-nvidia-470xx
                    ;;
                390xx)
                    echo "Installing legacy NVIDIA 390 driver..."
                    pkg_install xorg-x11-drv-nvidia-390xx akmod-nvidia-390xx
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
                    pkg_install "$driver_version" nvidia-utils
                    ;;
                latest)
                    pkg_install nvidia nvidia-utils
                    ;;
                dkms)
                    pkg_install nvidia-dkms nvidia-utils
                    ;;
                lts)
                    pkg_install nvidia-lts nvidia-utils
                    ;;
            esac
            ;;
        suse)
            case "$driver_version" in
                G04|G05)
                    pkg_install "nvidia-compute${driver_version}"
                    ;;
                G06)
                    echo "Installing NVIDIA ${driver_version} driver (proprietary kmp)..."
                    pkg_install "nvidia-driver-${driver_version}-kmp-meta"
                    ;;
                G07)
                    # G07 ships only as the open-source kernel module on
                    # openSUSE's NVIDIA repo — no proprietary kmp package
                    # exists for it (verified against the real repo).
                    echo "Installing NVIDIA G07 driver (open kernel module)..."
                    pkg_install "nvidia-open-driver-G07-signed-kmp-meta"
                    ;;
                *)
                    pkg_install "nvidia-driver-${driver_version}"
                    ;;
            esac
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
            # Enumerate every installed NVIDIA package (incl. :i386) so this
            # works for Debian's unversioned metapackages, the tesla/legacy
            # variants, and Ubuntu's versioned ones alike.
            local -a _nv_pkgs
            mapfile -t _nv_pkgs < <(dpkg-query -W -f='${Package}:${Architecture}\n' 2>/dev/null \
                | grep -E '^(nvidia-|libnvidia-|xserver-xorg-video-nvidia)')
            if [[ ${#_nv_pkgs[@]} -gt 0 ]]; then
                sudo apt-get purge --autoremove -y "${_nv_pkgs[@]}" nvtop
            else
                sudo apt-get purge --autoremove -y 'nvidia-driver-*' nvtop
            fi
            sudo apt-get autoclean
            ;;
        dnf|yum)
            pkg_remove 'nvidia*' nvtop
            ;;
        pacman)
            # Remove any installed nvidia module packages (vanilla or CachyOS kernel-paired)
            local _nvidia_pkgs
            mapfile -t _nvidia_pkgs < <(pacman -Q 2>/dev/null \
                | awk '{print $1}' \
                | grep -E '^(nvidia|linux-cachyos.*-nvidia)')
            [[ ${#_nvidia_pkgs[@]} -gt 0 ]] && \
                pkg_remove "${_nvidia_pkgs[@]}" 2>/dev/null || true
            pkg_remove nvtop 2>/dev/null || true
            ;;
        zypper)
            pkg_remove 'nvidia*' nvtop
            ;;
    esac
    rm -rf ~/.config/nvidia
    rm -rf ~/.nv
}

update_nvidia_drivers() {
    install_nvidia_drivers
}
