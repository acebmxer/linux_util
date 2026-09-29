#!/bin/bash
# Firecracker microVM monitor installer functions

# --- Firecracker ---

_FIRECRACKER_REPO="firecracker-microvm/firecracker"
_FIRECRACKER_BINS=(firecracker jailer)

check_firecracker() { _check_standard firecracker "" "" firecracker; }

# Arch's extra repo tracks upstream releases. Elsewhere the distro packages are
# missing (Debian/Ubuntu) or several releases behind (Fedora), so the upstream
# release binary is used.
install_firecracker() {
    info "Installing Firecracker..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch) pkg_install firecracker || return 1 ;;
        *)    _install_firecracker_binary || return 1 ;;
    esac
    _firecracker_kvm_hint
    info "Firecracker installed."
}

# Downloads the latest upstream release tarball, verifies it against the
# <asset>.sha256.txt sidecar, and installs firecracker + jailer to
# /usr/local/bin. The sidecar is fetched directly rather than through
# github_verify_checksum, which only recognises a ".sha256" suffix and would
# silently skip verification for this project.
_install_firecracker_binary() {
    local version arch asset base tmpdir expected
    version=$(curl -fsSL "https://api.github.com/repos/${_FIRECRACKER_REPO}/releases/latest" \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest Firecracker version."; return 1; }
    case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *) error "Firecracker has no release for $(uname -m)."; return 1 ;;
    esac
    asset="firecracker-${version}-${arch}.tgz"
    base="https://github.com/${_FIRECRACKER_REPO}/releases/download/${version}"
    tmpdir=$(mktemp -d /tmp/firecracker-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")
    if ! wget -qO "${tmpdir}/${asset}" "${base}/${asset}"; then
        error "Failed to download Firecracker."
        return 1
    fi
    expected=$(curl -fsSL "${base}/${asset}.sha256.txt" | awk '{print $1}')
    [[ -z "$expected" ]] && { error "Could not download the Firecracker checksum."; return 1; }
    verify_sha256 "${tmpdir}/${asset}" "$expected" "$asset" || return 1
    tar -xzf "${tmpdir}/${asset}" -C "$tmpdir" || { error "Failed to extract Firecracker."; return 1; }
    local bin
    for bin in "${_FIRECRACKER_BINS[@]}"; do
        sudo install -m 0755 "${tmpdir}/release-${version}-${arch}/${bin}-${version}-${arch}" \
            "/usr/local/bin/${bin}" || { error "Failed to install ${bin}."; return 1; }
    done
}

# Firecracker needs read/write access to /dev/kvm. Warn only — granting that
# access (kvm group or an ACL) is left to the user.
_firecracker_kvm_hint() {
    if [[ ! -e /dev/kvm ]]; then
        # WSL 2 is checked first: it runs on Hyper-V, and its /dev/kvm is
        # controlled from Windows by the [wsl2] nestedVirtualization key in
        # %UserProfile%\.wslconfig (Windows 11 only, on by default), not by
        # anything inside the distro.
        if _firecracker_is_wsl2; then
            warn "/dev/kvm is missing: this is WSL 2 without nested virtualization. It needs"
            warn "Windows 11. In %UserProfile%\\.wslconfig on Windows, under [wsl2], set"
            warn "nestedVirtualization=true (or remove a =false line), then run 'wsl --shutdown'"
            warn "in PowerShell and reopen this distro."
            return 0
        fi
        # Inside a VM the BIOS setting is irrelevant: the guest only gets
        # /dev/kvm when its hypervisor passes virtualization through (nested
        # virtualization). Xen/XCP-ng has no supported nested virtualization.
        local virt
        virt=$(systemd-detect-virt --vm 2>/dev/null) || virt="none"
        case "$virt" in
            none)
                warn "/dev/kvm is missing. Enable VT-x/AMD-V in your BIOS/UEFI before running Firecracker." ;;
            xen)
                warn "/dev/kvm is missing: this is a Xen VM (e.g. XCP-ng), and Xen does not support"
                warn "nested virtualization, so Firecracker cannot start microVMs here. Run it on"
                warn "bare metal or in a VM on a hypervisor with nested virtualization enabled." ;;
            *)
                warn "/dev/kvm is missing: this is a ${virt} VM without nested virtualization."
                warn "Enable nested virtualization for this VM on its hypervisor before running Firecracker." ;;
        esac
    elif [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        warn "No read/write access to /dev/kvm. Add yourself to the kvm group:"
        warn "  sudo usermod -aG kvm \$USER   (then log out and back in)"
    fi
}

# WSL 2 kernels carry a "-microsoft-standard-WSL2" release suffix. /proc/version
# is read rather than $WSL_DISTRO_NAME, which sudo strips from the environment.
_firecracker_is_wsl2() {
    grep -q 'WSL2' /proc/version 2>/dev/null
}

uninstall_firecracker() {
    info "Uninstalling Firecracker..."
    local bin
    for bin in "${_FIRECRACKER_BINS[@]}"; do
        sudo rm -f "/usr/local/bin/${bin}"
    done
    case "$DISTRO_FAMILY" in
        arch) pkg_remove firecracker 2>/dev/null || true ;;
    esac
}

update_firecracker() {
    info "Updating Firecracker..."
    if [[ "$DISTRO_FAMILY" == "arch" ]] && ! [[ -f /usr/local/bin/firecracker ]]; then
        pkg_upgrade firecracker
    else
        _install_firecracker_binary
    fi
}

get_version_firecracker() {
    _ver_from_cmd firecracker --version || _ver_from_pkg firecracker || echo ""
}
