#!/bin/bash
# Node.js installer (direct, not via NVM)

NODEJS_LTS_VERSION="24.15.0"
NODEJS_CURRENT_VERSION="25.9.0"

prompt_nodejs_version() {
    echo "Choose Node.js version to install:"
    echo "  1) LTS (${NODEJS_LTS_VERSION})"
    echo "  2) Current (${NODEJS_CURRENT_VERSION})"
    read -rp "Enter 1 for LTS or 2 for Current [1]: " choice
    case "$choice" in
        2) echo "current" ;;
        *) echo "lts" ;;
    esac
}

install_nodejs() {
    local branch="${1:-}"
    if [[ -z "$branch" ]]; then
        branch=$(prompt_nodejs_version)
    fi
    local version url pkg
    if [[ "$branch" == "current" ]]; then
        version="$NODEJS_CURRENT_VERSION"
    else
        version="$NODEJS_LTS_VERSION"
    fi
    url="https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz"
    pkg="node-v${version}-linux-x64.tar.xz"
    # tar -xf on a .tar.xz needs the xz binary; minimal images (e.g. WSL
    # Fedora) lack it, and Debian calls the package xz-utils
    if ! command -v xz &>/dev/null; then
        case "$DISTRO_FAMILY" in
            debian) pkg_install xz-utils ;;
            *)      pkg_install xz ;;
        esac
        command -v xz &>/dev/null || { error "xz is required to unpack Node.js."; return 1; }
    fi
    local tmpdir
    tmpdir="$(mktemp -d)"
    pushd "$tmpdir" || return 1
    info "Downloading Node.js $version..."
    if ! curl -fsSLO "$url"; then
        error "Failed to download Node.js archive."
        popd; rm -rf "$tmpdir"; return 1
    fi
    if ! tar -xf "$pkg"; then
        error "Failed to extract the Node.js archive."
        popd; rm -rf "$tmpdir"; return 1
    fi
    if ! sudo cp -r "node-v${version}-linux-x64"/* /usr/local/; then
        error "Failed to copy Node.js into /usr/local."
        popd; rm -rf "$tmpdir"; return 1
    fi
    popd
    rm -rf "$tmpdir"
    info "Node.js $version installed to /usr/local/bin."
}

check_nodejs() {
    _have_cmd node
}

# Name of the package that owns a file, empty if none.
_nodejs_owner_pkg() {
    case "$PKG_MGR" in
        apt)         dpkg -S "$1" 2>/dev/null | head -n1 | cut -d: -f1 ;;
        dnf|yum|zypper) rpm -qf --qf '%{NAME}\n' "$1" 2>/dev/null | head -n1 ;;
        pacman)      pacman -Qoq "$1" 2>/dev/null | head -n1 ;;
    esac
}

uninstall_nodejs() {
    info "Removing Node.js binaries from /usr/local/bin..."
    sudo rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
               /usr/local/bin/corepack
    # Also remove system-installed node if present. Remove it through the
    # package manager when a package owns it; rm alone leaves the package
    # registered as installed.
    if command -v node >/dev/null 2>&1; then
        local node_path owner
        node_path="$(command -v node)"
        if [[ "$node_path" != /usr/local/bin/* ]]; then
            owner="$(_nodejs_owner_pkg "$node_path")"
            if [[ -n "$owner" ]]; then
                info "Removing system Node.js package $owner..."
                pkg_remove "$owner" || { error "Failed to remove package $owner."; return 1; }
            else
                info "Removing system Node.js at $node_path..."
                sudo rm -f "$node_path" "$(command -v npm 2>/dev/null)" "$(command -v npx 2>/dev/null)"
            fi
        fi
    fi
    info "Node.js uninstalled."
}

update_nodejs() {
    local current_branch branch choice
    if node --version | grep -q "^v${NODEJS_LTS_VERSION%%.*}\."; then
        current_branch="lts"
    elif node --version | grep -q "^v${NODEJS_CURRENT_VERSION%%.*}\."; then
        current_branch="current"
    else
        current_branch="unknown"
    fi
    echo "Current Node.js branch: $current_branch"
    echo "Update options:"
    if [[ "$current_branch" == "lts" ]]; then
        echo "  1) Stay on LTS (${NODEJS_LTS_VERSION})"
        echo "  2) Switch to Current (${NODEJS_CURRENT_VERSION})"
        read -rp "Enter 1 or 2 [1]: " choice
        case "$choice" in
            2) branch="current" ;;
            *) branch="lts" ;;
        esac
    elif [[ "$current_branch" == "current" ]]; then
        echo "  1) Stay on Current (${NODEJS_CURRENT_VERSION})"
        echo "  2) Switch to LTS (${NODEJS_LTS_VERSION})"
        read -rp "Enter 1 or 2 [1]: " choice
        case "$choice" in
            2) branch="lts" ;;
            *) branch="current" ;;
        esac
    else
        echo "  1) LTS (${NODEJS_LTS_VERSION})"
        echo "  2) Current (${NODEJS_CURRENT_VERSION})"
        read -rp "Enter 1 or 2 [1]: " choice
        case "$choice" in
            2) branch="current" ;;
            *) branch="lts" ;;
        esac
    fi
    uninstall_nodejs
    install_nodejs "$branch"
}

get_version_nodejs() {
    _run_native node --version 2>/dev/null | sed 's/^v//'
}
