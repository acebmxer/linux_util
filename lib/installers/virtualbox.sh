#!/bin/bash
# VirtualBox installer functions
#
# Ubuntu, Arch and openSUSE: the distro's own virtualbox package (on Arch with
# the DKMS host modules and headers for each installed kernel). Debian, Fedora
# and RHEL clones have none, so those use Oracle's own signed repository
# (download.virtualbox.org), the signing key checked against the pinned
# fingerprint; Oracle publishes it for Debian 12 and 13, Fedora up to 44 and
# EL 8 to 10, and the installer says so on a release it does not cover. The
# kernel module is built for the running kernel, which needs the kernel
# headers; with Secure Boot on it must be signed before it loads. The
# installing user joins vboxusers (log out and in). Not offered on Alpine.

# --- VirtualBox ---

_VB_KEY_URL="https://www.virtualbox.org/download/oracle_vbox_2016.asc"
# Primary fingerprint of Oracle's 2016 VirtualBox signing key.
_VB_KEY_FPR="B9F8D658297AF3EFC18D5CDFA2F683C52980AECF"
_VB_APT_KEYRING="/usr/share/keyrings/oracle-virtualbox-2016.gpg"
_VB_APT_LIST="/etc/apt/sources.list.d/virtualbox.list"
_VB_REPO_FILE="/etc/yum.repos.d/virtualbox.repo"

check_virtualbox() { _check_standard VBoxManage virtualbox "" virtualbox VBoxManage || _have_cmd virtualbox; }

# Newest versioned Oracle package name (virtualbox-7.2 / VirtualBox-7.2).
_vb_vendor_package() {
    case "$DISTRO_FAMILY" in
        debian) apt-cache pkgnames virtualbox- 2>/dev/null | grep -E '^virtualbox-[0-9]+\.[0-9]+$' | sort -V | tail -1 ;;
        *)      "$PKG_MGR" -q repoquery --qf '%{name}\n' 'VirtualBox-*' 2>/dev/null | grep -E '^VirtualBox-[0-9]+\.[0-9]+$' | sort -V | tail -1 ;;
    esac
}

# Oracle's repository exists for this release? $1 is the URL of its directory.
_vb_url_exists() { curl -fsSL --max-time 20 -o /dev/null -I "$1"; }

_vb_install_debian() {
    local codename
    codename=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")
    if pkg_in_repo virtualbox; then
        pkg_install virtualbox || return 1
        return 0
    fi
    if [[ "$DISTRO_ID" != "debian" ]] || ! _vb_url_exists "https://download.virtualbox.org/virtualbox/debian/dists/${codename}/"; then
        error "VirtualBox is not in the ${DISTRO_NAME} repositories and Oracle publishes no repository for it. Nothing was changed."
        return 1
    fi
    ensure_tools
    _add_apt_repo "$_VB_KEY_URL" "$_VB_APT_KEYRING" \
        "deb [arch=$(dpkg --print-architecture) signed-by=${_VB_APT_KEYRING}] https://download.virtualbox.org/virtualbox/debian ${codename} contrib" \
        "$_VB_APT_LIST" "$_VB_KEY_FPR" || return 1
    local pkg
    pkg=$(_vb_vendor_package)
    [[ -n "$pkg" ]] || { error "Oracle's repository lists no VirtualBox package."; return 1; }
    pkg_install dkms "linux-headers-$(uname -r)" 2>/dev/null || pkg_install dkms || true
    pkg_install "$pkg"
}

_vb_install_rpm() {
    local osdir rel
    if [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        osdir=fedora; rel=${DISTRO_VERSION_ID%%.*}
    else
        osdir=el; rel=${DISTRO_VERSION_ID%%.*}
    fi
    if ! _vb_url_exists "https://download.virtualbox.org/virtualbox/rpm/${osdir}/${rel}/"; then
        error "Oracle publishes no VirtualBox repository for ${DISTRO_NAME} ${DISTRO_VERSION_ID}. Nothing was changed."
        return 1
    fi
    ensure_tools
    ensure_epel
    rpm_import_key_checked "$_VB_KEY_URL" "$_VB_KEY_FPR" || return 1
    local tmp
    tmp=$(mktemp) || return 1
    curl -fsSL --max-time 30 "https://download.virtualbox.org/virtualbox/rpm/${osdir}/virtualbox.repo" -o "$tmp" \
        || { rm -f "$tmp"; error "Could not download Oracle's repository file."; return 1; }
    sudo install -m 0644 "$tmp" "$_VB_REPO_FILE"
    rm -f "$tmp"
    pkg_refresh
    local pkg
    pkg=$(_vb_vendor_package)
    [[ -n "$pkg" ]] || { error "Oracle's repository lists no VirtualBox package."; return 1; }
    pkg_install gcc make perl bzip2 elfutils-libelf-devel "kernel-devel-$(uname -r)" 2>/dev/null \
        || pkg_install gcc make perl bzip2 elfutils-libelf-devel kernel-devel || true
    pkg_install "$pkg" || return 1
    sudo /sbin/vboxconfig 2>/dev/null || warn "The VirtualBox kernel module was not built now; run 'sudo /sbin/vboxconfig' after installing kernel-devel for the running kernel."
}

_vb_install_arch() {
    local pkgs=(virtualbox virtualbox-host-dkms) k
    # Headers for every installed kernel, so DKMS can build for each of them.
    while IFS= read -r k; do
        arch_repo_has "${k}-headers" && pkgs+=("${k}-headers")
    done < <(pacman -Qqs '^linux[a-z0-9-]*$' 2>/dev/null | grep -Ev -- '-(headers|docs|api-headers)$|^linux-firmware|^linux-api')
    pkg_install "${pkgs[@]}"
}

install_virtualbox() {
    info "Installing VirtualBox..."
    pkg_refresh
    case "$DISTRO_FAMILY" in
        debian)      _vb_install_debian || return 1 ;;
        fedora|rhel) _vb_install_rpm || return 1 ;;
        arch)        _vb_install_arch || return 1 ;;
        suse)        pkg_install virtualbox || return 1 ;;
        *)           error "VirtualBox is not offered on ${DISTRO_NAME}."; return 1 ;;
    esac
    getent group vboxusers >/dev/null 2>&1 && sudo usermod -aG vboxusers "${SUDO_USER:-$USER}" 2>/dev/null \
        && info "Added ${SUDO_USER:-$USER} to the vboxusers group; log out and back in for USB access."
    info "VirtualBox installed. With Secure Boot on, the kernel module must be signed before it loads."
}

# Virtual machines and settings under ~/VirtualBox VMs and ~/.config/VirtualBox are kept.
uninstall_virtualbox() {
    info "Uninstalling VirtualBox..."
    case "$DISTRO_FAMILY" in
        debian)
            local pkgs
            pkgs=$(dpkg -l 'virtualbox*' 2>/dev/null | awk '/^ii/{print $2}' | tr '\n' ' ')
            # shellcheck disable=SC2086
            [[ -n "$pkgs" ]] && pkg_remove $pkgs
            sudo rm -f "$_VB_APT_LIST" "$_VB_APT_KEYRING"
            ;;
        fedora|rhel)
            local pkgs
            pkgs=$(rpm -qa --qf '%{NAME}\n' 'VirtualBox-*' 2>/dev/null | tr '\n' ' ')
            # shellcheck disable=SC2086
            [[ -n "$pkgs" ]] && pkg_remove $pkgs
            sudo rm -f "$_VB_REPO_FILE"
            ;;
        arch)  pkg_remove virtualbox virtualbox-host-dkms ;;
        suse)  pkg_remove virtualbox ;;
    esac
}

update_virtualbox() {
    info "Updating VirtualBox..."
    case "$DISTRO_FAMILY" in
        debian)
            local pkg
            pkg=$(dpkg -l 'virtualbox*' 2>/dev/null | awk '/^ii/{print $2}' | head -1)
            [[ -n "$pkg" ]] && pkg_upgrade "$pkg"
            ;;
        fedora|rhel)
            local pkg
            pkg=$(rpm -qa --qf '%{NAME}\n' 'VirtualBox-*' 2>/dev/null | head -1)
            [[ -n "$pkg" ]] && pkg_upgrade "$pkg"
            ;;
        arch) pkg_upgrade virtualbox ;;
        suse) pkg_upgrade virtualbox ;;
    esac
}

get_version_virtualbox() { _ver_from_cmd VBoxManage || echo ""; }
