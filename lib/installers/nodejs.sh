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
    sudo rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx \
               /usr/local/bin/corepack
    # Also remove system-installed node if present
    if command -v node >/dev/null 2>&1; then
        local node_path
        node_path="$(command -v node)"
        if [[ "$node_path" != /usr/local/bin/* ]]; then
            info "Removing system Node.js at $node_path..."
            sudo rm -f "$node_path" "$(command -v npm 2>/dev/null)" "$(command -v npx 2>/dev/null)"
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
    node --version 2>/dev/null | sed 's/^v//'
}
