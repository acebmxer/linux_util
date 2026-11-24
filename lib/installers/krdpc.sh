#!/bin/bash
# krdpc installer functions
# https://github.com/acebmxer/krdpc
#
# A KDE (Qt) list of saved remote computers that opens each with FreeRDP. It is
# in no distribution's repositories, so the package is taken from krdpc's own
# GitHub release -- a .rpm on Fedora, a .deb on Debian and Ubuntu, a .pkg.tar.zst
# on Arch -- checked against the SHA-256 GitHub publishes for it, then installed
# with the package manager so FreeRDP 3, PySide6 and keyring come from the
# distribution. krdpc has only pre-releases so far, so the newest release of any
# kind is used. Offered on Fedora 45 and newer (the rpm needs its Python),
# Debian 13 and newer, Ubuntu 26.04 and newer, and Arch.
#
# Uninstalling keeps your computers (~/.config/krdpc), your settings and the
# passwords remembered in KDE Wallet.

# --- krdpc ---

_krdpc_REPO="acebmxer/krdpc"
github_allow_prerelease "$_krdpc_REPO"

# Release file name for this family.
_krdpc_asset_re() {
    case "$DISTRO_FAMILY" in
        fedora) echo 'krdpc-[0-9][^/]*\.noarch\.rpm' ;;
        debian) echo 'krdpc_[^/]*_all\.deb' ;;
        arch)   echo 'krdpc-[^/]*-any\.pkg\.tar\.zst' ;;
        *)      return 1 ;;
    esac
}

# Newest release as the package's own version spelling without the package
# release number: v0.1.0-beta.7 -> 0.1.0-beta.7. Also what System Updates
# compares against get_version_krdpc.
_krdpc_latest_version() { github_latest_tag "$_krdpc_REPO" | sed 's/^v//'; }

check_krdpc() { _check_standard krdpc krdpc ""; }

# Download the newest release file, check it and install it.
_krdpc_install_release() {
    local re tmp file rc
    re=$(_krdpc_asset_re) || { error "krdpc has no package for ${DISTRO_NAME:-this system}."; return 1; }
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/krdpc-XXXXXX") || return 1
    file=$(github_asset_download "$_krdpc_REPO" "$re" "$tmp") || { rm -rf "$tmp"; return 1; }
    pkg_install_local "$file"
    rc=$?
    rm -rf "$tmp"
    return $rc
}

install_krdpc() {
    info "Installing krdpc..."
    ensure_tools
    _krdpc_install_release || return 1
    info "krdpc installed."
}

# Your computers (~/.config/krdpc) and the KDE Wallet passwords are kept.
uninstall_krdpc() {
    info "Uninstalling krdpc..."
    pkg_remove krdpc
}

update_krdpc() {
    info "Updating krdpc..."
    local latest cur
    latest=$(_krdpc_latest_version) || latest=""
    [[ -n "$latest" ]] || { error "Could not read the latest krdpc release from GitHub."; return 1; }
    cur=$(get_version_krdpc)
    if [[ "$cur" == "$latest" ]]; then
        info "krdpc is already at the latest version (${cur})."
        return 0
    fi
    _krdpc_install_release
}

# 0.1.0~beta.7 (rpm, deb) and 0.1.0_beta.7 (Arch) both read 0.1.0-beta.7, the
# spelling of the release tag.
get_version_krdpc() {
    local v
    v=$(_ver_from_pkg krdpc) || { echo ""; return 0; }
    printf '%s\n' "${v//[~_]/-}"
}
