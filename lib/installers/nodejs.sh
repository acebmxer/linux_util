#!/bin/bash
# Node.js installer (direct, not via NVM)

NODEJS_LTS_VERSION="24.14.1"
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
    local branch
    branch=$(prompt_nodejs_version)
    local version url pkg
    if [[ "$branch" == "current" ]]; then
        version="$NODEJS_CURRENT_VERSION"
    else
        version="$NODEJS_LTS_VERSION"
    fi
    url="https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz"
    pkg="node-v${version}-linux-x64.tar.xz"
    tmpdir="$(mktemp -d)"
    pushd "$tmpdir" || return 1
    info "Downloading Node.js $version..."
    if ! curl -fsSLO "$url"; then
        error "Failed to download Node.js archive."
        popd; rm -rf "$tmpdir"; return 1
    fi
    tar -xf "$pkg"
    sudo cp -r "node-v${version}-linux-x64"/* /usr/local/
    popd
    rm -rf "$tmpdir"
    info "Node.js $version installed to /usr/local/bin."
}

check_nodejs() {
    command -v node >/dev/null 2>&1
}

uninstall_nodejs() {
    info "Removing Node.js binaries from /usr/local/bin..."
    sudo rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx
    info "Node.js uninstalled."
}

update_nodejs() {
    local current_branch
    if node --version | grep -q '^v${NODEJS_LTS_VERSION%%.*}\.'; then
        current_branch="lts"
    elif node --version | grep -q '^v${NODEJS_CURRENT_VERSION%%.*}\.'; then
        current_branch="current"
    else
        current_branch="unknown"
    fi
    echo "Current Node.js branch: $current_branch"
    echo "Update options:"
    echo "  1) Stay on current branch"
    echo "  2) Switch to LTS (${NODEJS_LTS_VERSION})"
    echo "  3) Switch to Current (${NODEJS_CURRENT_VERSION})"
    read -rp "Enter 1, 2, or 3 [1]: " choice
    case "$choice" in
        2) branch="lts" ;;
        3) branch="current" ;;
        *) branch="$current_branch" ;;
    esac
    if [[ "$branch" == "unknown" ]]; then
        branch=$(prompt_nodejs_version)
    fi
    uninstall_nodejs
    install_nodejs "$branch"
}

get_version_nodejs() {
    node --version 2>/dev/null | sed 's/^v//'
}
