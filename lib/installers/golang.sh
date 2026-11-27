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
            pkg_install golang-go
            ;;
        fedora)
            pkg_install golang
            ;;
        rhel)
            pkg_install golang 2>/dev/null || {
                # Fall back to binary install for older RHEL releases
                _install_golang_binary || return 1
            }
            ;;
        arch)
            pkg_install go
            ;;
        suse)
            pkg_install go
            ;;
    esac
    info "Go SDK installed."
    info "Add /usr/local/go/bin to PATH if not already present."
}

# Install the official Go binary tarball for distros with no/old Go packages
_install_golang_binary() {
    info "Installing Go from official binary release..."
    local go_version arch tmpfile version_text
    # VERSION?m=text returns the version on the first line and a timestamp on the
    # second. Captured and trimmed rather than piped to `head -1`, which closes
    # the pipe early and makes curl report error 23 on stderr.
    version_text=$(curl -fsSL https://go.dev/VERSION?m=text)
    go_version="${version_text%%$'\n'*}"
    [[ -z "$go_version" ]] && { error "Could not determine latest Go version."; return 1; }
    arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && arch="arm64"
    local archive="${go_version}.linux-${arch}.tar.gz"
    tmpfile=$(mktemp /tmp/go-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")
    if ! wget -qO "$tmpfile" "https://dl.google.com/go/${archive}"; then
        error "Failed to download Go binary."
        return 1
    fi
    # go.dev publishes a SHA-256 for every file; the archive must match it
    # before anything on the system is touched. The listing is flattened so one
    # file's entry is one run of text up to its closing brace.
    local listing expected
    listing=$(curl -fsSL 'https://go.dev/dl/?mode=json' 2>/dev/null | tr -d '\n\t ')
    expected=$(grep -oP "\"filename\":\"${archive//./\\.}\"[^}]*?\"sha256\":\"\K[0-9a-f]{64}" <<<"$listing" | head -1)
    if [[ -z "$expected" ]]; then
        error "Could not find the published SHA-256 for ${archive} on go.dev; Go was not changed."
        return 1
    fi
    verify_sha256 "$tmpfile" "$expected" "$archive" || return 1
    # Unpack beside the live copy, check it, then swap with two renames on the
    # same filesystem: a failed extract leaves the old Go exactly as it was.
    local staging=/usr/local/.go-new.$$ old=/usr/local/.go-old.$$
    sudo rm -rf "$staging" "$old"
    sudo mkdir "$staging" && sudo tar -C "$staging" -xzf "$tmpfile" && [[ -x "$staging/go/bin/go" ]] || {
        sudo rm -rf "$staging"
        error "Could not unpack Go; the existing Go was left in place."
        return 1
    }
    if [[ -e /usr/local/go ]]; then
        sudo mv /usr/local/go "$old" || { sudo rm -rf "$staging"; error "Could not replace the existing Go."; return 1; }
    fi
    if ! sudo mv "$staging/go" /usr/local/go; then
        [[ -e "$old" ]] && sudo mv "$old" /usr/local/go
        sudo rm -rf "$staging"
        error "Could not put the new Go in place; the existing Go was restored."
        return 1
    fi
    sudo rm -rf "$staging" "$old"
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
        debian)      pkg_remove golang-go golang 2>/dev/null || true ;;
        fedora|rhel) pkg_remove golang 2>/dev/null || true ;;
        arch)        pkg_remove go 2>/dev/null || true ;;
        suse)        pkg_remove go 2>/dev/null || true ;;
    esac
}

update_golang() {
    info "Updating Go SDK..."
    if [[ -d /usr/local/go ]]; then
        _install_golang_binary
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade golang-go ;;
            fedora|rhel) pkg_upgrade golang ;;
            arch)        pkg_upgrade go ;;
            suse)        pkg_upgrade go ;;
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
