#!/bin/bash
# Helix installer functions
#
# Modal terminal editor with language-server support built in. The distro
# package where the repositories have one (Fedora, Rocky/Alma 9 and 10 through
# EPEL, Arch, openSUSE, Alpine); otherwise (Debian, Ubuntu, Rocky/Alma 8) the
# GitHub release, SHA-256 checked, unpacked whole into /opt/helix, because hx
# looks for its runtime files beside itself, with a link at /usr/local/bin/hx.

# --- Helix ---

_HELIX_REPO="helix-editor/helix"
_HELIX_DIR="/opt/helix"

# Latest upstream version, for System Updates.
_helix_latest_version() { github_latest_tag "$_HELIX_REPO"; }

check_helix() { _check_standard hx helix "" || [[ -x "${_HELIX_DIR}/hx" ]]; }

# Unpack the release's .tar.xz needs xz.
_helix_install_release() {
    local tmp file dir
    if ! command -v xz &>/dev/null; then
        case "$DISTRO_FAMILY" in
            debian) pkg_install xz-utils || return 1 ;;
            *)      pkg_install xz || return 1 ;;
        esac
    fi
    tmp=$(mktemp -d) || return 1
    CLEANUP_FILES+=("$tmp")
    file=$(github_asset_download "$_HELIX_REPO" "helix-[0-9.]+-$(upstream_arch gnu)-linux\.tar\.xz" "$tmp") || { rm -rf "$tmp"; return 1; }
    tar -xJf "$file" -C "$tmp" || { error "Could not unpack the Helix download."; rm -rf "$tmp"; return 1; }
    dir=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ -x "${dir}/hx" && -d "${dir}/runtime" ]] || { error "The Helix download is missing hx or its runtime files."; rm -rf "$tmp"; return 1; }
    sudo rm -rf "$_HELIX_DIR"
    sudo mv "$dir" "$_HELIX_DIR" || { rm -rf "$tmp"; return 1; }
    sudo ln -sf "${_HELIX_DIR}/hx" /usr/local/bin/hx
    rm -rf "$tmp"
}

install_helix() {
    info "Installing Helix..."
    pkg_refresh
    ensure_epel
    if pkg_in_repo helix; then
        pkg_install helix || return 1
    else
        info "helix is not in the ${DISTRO_NAME:-system} repositories; installing the verified release from GitHub."
        _helix_install_release || return 1
    fi
    info "Helix installed. Start it with: hx"
}

uninstall_helix() {
    info "Uninstalling Helix..."
    pkg_check_installed helix && pkg_remove helix
    if [[ -d "$_HELIX_DIR" ]]; then
        sudo rm -rf "$_HELIX_DIR"
        sudo rm -f /usr/local/bin/hx
    fi
    return 0
}

update_helix() {
    info "Updating Helix..."
    if [[ -d "$_HELIX_DIR" ]] && ! pkg_check_installed helix; then
        local tag cur
        tag=$(github_latest_tag "$_HELIX_REPO") || { error "Could not read the latest Helix release from GitHub."; return 1; }
        cur=$(get_version_helix)
        if [[ -n "$cur" && "$tag" == "$cur" ]]; then
            info "Helix is already at the latest version (${cur})."
            return 0
        fi
        _helix_install_release
    else
        pkg_upgrade helix
    fi
}

get_version_helix() { _ver_from_pkg helix || _ver_from_cmd hx || echo ""; }
