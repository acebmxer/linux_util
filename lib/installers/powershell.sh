#!/bin/bash
# PowerShell installer functions

# --- PowerShell ---

check_powershell() {
    _check_standard pwsh powershell "" powershell-bin || { has_snap && snap list powershell &>/dev/null 2>&1; }
}

# Downloads the latest PowerShell .deb from GitHub releases and installs via dpkg.
# Used when the Microsoft apt repo doesn't yet carry the package for this distro version.
_powershell_install_github_deb() {
    local _arch
    _arch=$(dpkg --print-architecture)
    local _version
    _version=$(curl -fsSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" 2>/dev/null \
               | grep -oP '"tag_name":\s*"v\K[^"]+')
    [[ -n "$_version" ]] || { error "Could not determine latest PowerShell version from GitHub"; return 1; }
    local _deb_url="https://github.com/PowerShell/PowerShell/releases/download/v${_version}/powershell_${_version}-1.deb_${_arch}.deb"
    local _deb_tmp
    _deb_tmp=$(mktemp /tmp/powershell-XXXXXX.deb)
    info "Downloading PowerShell ${_version} from GitHub releases..."
    if ! curl -fsSL -o "$_deb_tmp" "$_deb_url"; then
        rm -f "$_deb_tmp"
        error "Failed to download PowerShell .deb from GitHub"
        return 1
    fi
    sudo dpkg -i "$_deb_tmp" || true
    sudo apt-get install -f -y
    rm -f "$_deb_tmp"
}

# Install PowerShell from Microsoft's own linux tarball.
#
# Used on Arch, which has no repo package. This is the same artifact Microsoft
# publishes for every distro they do not ship a repo for, and the release
# carries a hashes.sha256 manifest, so the download is verified rather than
# trusted on TLS alone.
_PWSH_GH_API="https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
_PWSH_DIR="/opt/microsoft/powershell"
_PWSH_LINK="/usr/local/bin/pwsh"

_pwsh_install_tarball() {
    local machine pattern url tmpdir tarball sums
    machine=$(uname -m)
    case "$machine" in
        x86_64)        pattern='linux-x64\.tar\.gz$' ;;
        aarch64|arm64) pattern='linux-arm64\.tar\.gz$' ;;
        armv7l)        pattern='linux-arm32\.tar\.gz$' ;;
        *) error "Unsupported architecture for PowerShell: ${machine}"; return 1 ;;
    esac

    url=$(curl -fsSL "$_PWSH_GH_API" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' | grep -m1 -E "$pattern")
    [[ -z "$url" ]] && { error "Could not find a PowerShell tarball asset."; return 1; }

    tmpdir=$(mktemp -d /tmp/pwsh-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tarball="$tmpdir/$(basename "$url")"

    info "Downloading PowerShell..."
    wget -qO "$tarball" "$url" || { error "Failed to download PowerShell."; return 1; }

    # Verify against upstream's hashes.sha256 when it is present in the release.
    sums=$(curl -fsSL "$_PWSH_GH_API" 2>/dev/null \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+hashes\.sha256')
    if [[ -n "$sums" ]]; then
        local want got
        want=$(curl -fsSL "$sums" 2>/dev/null | grep -F "$(basename "$url")" | awk '{print $1}' | head -1)
        got=$(sha256sum "$tarball" | awk '{print $1}')
        if [[ -n "$want" && "$want" != "$got" ]]; then
            error "PowerShell checksum mismatch — refusing to install."
            return 1
        fi
        [[ -n "$want" ]] && verbose "PowerShell checksum verified."
    else
        warn "No hashes.sha256 in the PowerShell release; skipping checksum verification."
    fi

    local version
    version=$(basename "$url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local dest="${_PWSH_DIR}/${version:-current}"

    info "Installing PowerShell to ${dest}..."
    sudo rm -rf "$dest"
    sudo mkdir -p "$dest" || { error "Could not create ${dest}."; return 1; }
    sudo tar xzf "$tarball" -C "$dest" || { error "Failed to unpack PowerShell."; return 1; }
    sudo chmod +x "$dest/pwsh"
    sudo ln -sf "$dest/pwsh" "$_PWSH_LINK"
    return 0
}

install_powershell() {
    info "Installing PowerShell..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local _ms_distro _ms_ver _ms_codename
            _ms_codename="$DISTRO_VERSION_CODENAME"
            case "$DISTRO_ID" in
                debian)
                    _ms_distro="debian"
                    _ms_ver=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
                    ;;
                *)
                    # Ubuntu and Ubuntu-based derivatives
                    _ms_distro="ubuntu"
                    _ms_ver=$(echo "$DISTRO_VERSION_ID" | grep -oP '^\d+\.\d+')
                    local _ubuntu_codename
                    _ubuntu_codename=$(grep -oP '^UBUNTU_CODENAME=\K.*' /etc/os-release 2>/dev/null || true)
                    [[ -n "$_ubuntu_codename" ]] && _ms_codename="$_ubuntu_codename"
                    ;;
            esac
            # Use packages-microsoft-prod.deb — Microsoft's canonical setup package that
            # ships the correct signing key for each distro version (microsoft.asc alone
            # does not contain the key used to sign newer Ubuntu repos like 26.04).
            local _prod_deb_url="https://packages.microsoft.com/config/${_ms_distro}/${_ms_ver}/packages-microsoft-prod.deb"
            local _prod_deb_tmp
            _prod_deb_tmp=$(mktemp /tmp/packages-microsoft-prod-XXXXXX.deb)
            if curl -fsSL -o "$_prod_deb_tmp" "$_prod_deb_url" 2>/dev/null && \
               file "$_prod_deb_tmp" 2>/dev/null | grep -q "Debian binary package"; then
                sudo dpkg -i "$_prod_deb_tmp"
                rm -f "$_prod_deb_tmp"
                sudo apt update
            else
                rm -f "$_prod_deb_tmp"
                # Fallback for distros where the .deb is not available
                _add_apt_repo \
                    "https://packages.microsoft.com/keys/microsoft.asc" \
                    "/etc/apt/keyrings/microsoft-prod.gpg" \
                    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/${_ms_distro}/${_ms_ver}/prod ${_ms_codename} main" \
                    "/etc/apt/sources.list.d/microsoft-prod.list"
            fi
            if apt-cache show powershell &>/dev/null; then
                sudo apt install -y powershell
            else
                # Microsoft apt repo doesn't carry powershell for this distro version yet
                info "PowerShell not in Microsoft apt repo for $_ms_distro $_ms_ver — downloading .deb from GitHub releases..."
                _powershell_install_github_deb
            fi
            ;;
        fedora)
            local _fedora_ver
            _fedora_ver=$(rpm -E '%{fedora}')
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo curl -sSL -o /etc/yum.repos.d/microsoft-prod.repo \
                "https://packages.microsoft.com/config/fedora/${_fedora_ver}/prod.repo"
            sudo dnf install -y powershell
            ;;
        rhel)
            local _el_ver
            _el_ver=$(rpm -E '%{rhel}')
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo curl -sSL -o /etc/yum.repos.d/microsoft-prod.repo \
                "https://packages.microsoft.com/config/rhel/${_el_ver}/prod.repo"
            sudo "$PKG_MGR" install -y powershell
            ;;
        arch)
            # repos -> (not on Flathub) -> Microsoft's tarball -> AUR.
            arch_install_ordered "powershell-bin" "" "_pwsh_install_tarball" "powershell-bin"
            ;;
        suse)
            if has_snap; then
                sudo snap install powershell --classic
            else
                local _suse_ver
                _suse_ver=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
                sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
                sudo zypper addrepo "https://packages.microsoft.com/config/sles/${_suse_ver}/prod.repo" microsoft-prod 2>/dev/null || true
                sudo zypper refresh
                sudo zypper install -y powershell
            fi
            ;;
    esac
    info "PowerShell installed. Run 'pwsh' to start a session."
}

uninstall_powershell() {
    info "Uninstalling PowerShell..."
    if has_snap && snap list powershell &>/dev/null 2>&1; then
        sudo snap remove powershell
        return
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y powershell packages-microsoft-prod 2>/dev/null || \
                sudo apt purge --autoremove -y powershell
            sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list
            # Cover all keyring locations used by different install methods
            sudo rm -f /etc/apt/keyrings/microsoft-prod.gpg
            sudo rm -f /usr/share/keyrings/microsoft-prod.gpg
            sudo rm -f /etc/apt/trusted.gpg.d/microsoft-prod.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y powershell
            sudo rm -f /etc/yum.repos.d/microsoft-prod.repo
            ;;
        arch)
            aur_remove powershell-bin 2>/dev/null || \
                sudo pacman -Rs --noconfirm powershell-bin 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y powershell
            sudo zypper removerepo microsoft-prod 2>/dev/null || true
            ;;
    esac
}

update_powershell() {
    info "Updating PowerShell..."
    if has_snap && snap list powershell &>/dev/null 2>&1; then
        sudo snap refresh powershell
        return
    fi
    case "$DISTRO_FAMILY" in
        debian)
            if apt-cache show powershell &>/dev/null; then
                sudo apt-get install -y --only-upgrade powershell
            else
                _powershell_install_github_deb
            fi
            ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y powershell ;;
        arch)        repo_or_aur powershell-bin ;;
        suse)        sudo zypper update -y powershell ;;
    esac
}

get_version_powershell() {
    _ver_from_cmd pwsh --version || _ver_from_snap powershell || _ver_from_pkg powershell || echo ""
}
