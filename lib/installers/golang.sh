#!/bin/bash
# Go SDK installer functions

# --- Go SDK ---

check_golang() {
    _have_cmd go || [[ -f /usr/local/go/bin/go ]]
}

install_golang() {
    info "Installing Go SDK..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y golang-go
            ;;
        fedora)
            sudo "$PKG_MGR" install -y golang
            ;;
        rhel)
            sudo "$PKG_MGR" install -y golang 2>/dev/null || {
                # Fall back to binary install for older RHEL releases
                _install_golang_binary
            }
            ;;
        arch)
            sudo pacman -S --noconfirm go
            ;;
        suse)
            sudo zypper install -y go
            ;;
    esac
    info "Go SDK installed."
    info "Add /usr/local/go/bin to PATH if not already present."
}

# Install the official Go binary tarball for distros with no/old Go packages
_install_golang_binary() {
    info "Installing Go from official binary release..."
    local go_version arch tmpfile
    go_version=$(curl -fsSL https://go.dev/VERSION?m=text | head -1)
    [[ -z "$go_version" ]] && { error "Could not determine latest Go version."; return 1; }
    arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
    tmpfile=$(mktemp /tmp/go-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")
    if ! wget -qO "$tmpfile" "https://dl.google.com/go/${go_version}.linux-${arch}.tar.gz"; then
        error "Failed to download Go binary."
        return 1
    fi
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$tmpfile"
    # Add to system-wide PATH
    if ! grep -q '/usr/local/go/bin' /etc/profile.d/golang.sh 2>/dev/null; then
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh > /dev/null
    fi
    export PATH="$PATH:/usr/local/go/bin"
    info "Go ${go_version} installed to /usr/local/go."
}

uninstall_golang() {
    info "Uninstalling Go SDK..."
    if [[ -d /usr/local/go ]]; then
        sudo rm -rf /usr/local/go
        sudo rm -f /etc/profile.d/golang.sh
        info "Removed /usr/local/go."
    fi
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y golang-go golang 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y golang 2>/dev/null || true ;;
        arch)        sudo pacman -Rs --noconfirm go 2>/dev/null || true ;;
        suse)        sudo zypper remove -y go 2>/dev/null || true ;;
    esac
}

update_golang() {
    info "Updating Go SDK..."
    if [[ -d /usr/local/go ]]; then
        _install_golang_binary
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade golang-go ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y golang ;;
            arch)        sudo pacman -S --noconfirm go ;;
            suse)        sudo zypper update -y go ;;
        esac
    fi
}

get_version_golang() {
    if _have_cmd go; then
        _run_native go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
    elif [[ -f /usr/local/go/bin/go ]]; then
        /usr/local/go/bin/go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
    else
        echo ""
    fi
}
