#!/bin/bash
# Input Leap software KVM installer functions

# --- Input Leap ---

check_input_leap() { _check_standard input-leap input-leap ""; }

install_input_leap() {
    info "Installing Input Leap..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Try distro repo first; if unavailable, download .deb from GitHub
            sudo apt install -y input-leap 2>/dev/null || _install_input_leap_github_deb
            ;;
        fedora)
            sudo "$PKG_MGR" install -y input-leap 2>/dev/null || {
                warn "input-leap not found in repos. Trying GitHub release..."
                _install_input_leap_github_rpm
            }
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y input-leap 2>/dev/null || {
                warn "input-leap not found in repos. Trying GitHub release..."
                _install_input_leap_github_rpm
            }
            ;;
        arch)
            repo_or_aur input-leap
            ;;
        suse)
            sudo zypper install -y input-leap 2>/dev/null || {
                warn "input-leap not available in repos."
                error "Install Input Leap manually from https://github.com/input-leap/input-leap/releases"
                return 1
            }
            ;;
    esac
    info "Input Leap installed."
    info "Input Leap is a software KVM: one keyboard and mouse controls multiple computers over the network."
}

_install_input_leap_github_deb() {
    local version tmpfile
    version=$(curl -fsSL https://api.github.com/repos/input-leap/input-leap/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest Input Leap version."; return 1; }
    tmpfile=$(mktemp /tmp/input-leap-XXXXXX.deb)
    CLEANUP_FILES+=("$tmpfile")
    # Try common .deb naming patterns from GitHub releases
    local base_url="https://github.com/input-leap/input-leap/releases/download/${version}"
    wget -qO "$tmpfile" "${base_url}/input-leap_${version#v}_amd64.deb" 2>/dev/null || \
    wget -qO "$tmpfile" "${base_url}/InputLeap_${version#v}_ubuntu22.04_amd64.deb" 2>/dev/null || {
        error "Could not download Input Leap .deb. Check https://github.com/input-leap/input-leap/releases"
        return 1
    }
    sudo apt install -y "$tmpfile"
}

_install_input_leap_github_rpm() {
    local version tmpfile
    version=$(curl -fsSL https://api.github.com/repos/input-leap/input-leap/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest Input Leap version."; return 1; }
    tmpfile=$(mktemp /tmp/input-leap-XXXXXX.rpm)
    CLEANUP_FILES+=("$tmpfile")
    local base_url="https://github.com/input-leap/input-leap/releases/download/${version}"
    wget -qO "$tmpfile" "${base_url}/input-leap-${version#v}-1.x86_64.rpm" 2>/dev/null || {
        error "Could not download Input Leap .rpm. Check https://github.com/input-leap/input-leap/releases"
        return 1
    }
    sudo "$PKG_MGR" install -y "$tmpfile"
}

uninstall_input_leap() {
    info "Uninstalling Input Leap..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y input-leap ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y input-leap ;;
        arch)
            aur_remove input-leap 2>/dev/null || \
                sudo pacman -Rs --noconfirm input-leap 2>/dev/null || true
            ;;
        suse)        sudo zypper remove -y input-leap 2>/dev/null || true ;;
    esac
    rm -rf "$HOME/.config/InputLeap"
}

update_input_leap() {
    info "Updating Input Leap..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade input-leap 2>/dev/null || _install_input_leap_github_deb ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y input-leap 2>/dev/null || _install_input_leap_github_rpm ;;
        arch)        repo_or_aur input-leap ;;
        suse)        sudo zypper update -y input-leap 2>/dev/null || true ;;
    esac
}

get_version_input_leap() {
    _ver_from_cmd input-leap --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_pkg input-leap || echo ""
}
