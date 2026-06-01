#!/bin/bash
# Homebrew (Linuxbrew) installer functions
#
# Homebrew is a cross-distro, user-space package manager. It installs into
# /home/linuxbrew/.linuxbrew and must NOT be run as root. Works alongside the
# native package manager on all supported families.
# Project: https://brew.sh

# --- Homebrew ---

_BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
_BREW_MARKER="# linux_util:homebrew"

# Locate the brew binary whether or not it's on PATH yet.
_brew_path() {
    if command -v brew &>/dev/null; then
        command -v brew
    elif [[ -x "$_BREW_BIN" ]]; then
        echo "$_BREW_BIN"
    else
        return 1
    fi
}

check_homebrew() { _brew_path &>/dev/null; }

# Append the brew shellenv line to interactive shell rc files (idempotent).
_homebrew_configure_shells() {
    local brew_bin shellenv_line rc
    brew_bin=$(_brew_path) || return 0
    shellenv_line="eval \"\$(${brew_bin} shellenv)\""

    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [[ -e "$rc" || "$rc" == "$HOME/.bashrc" ]] || continue
        if ! grep -qF "$_BREW_MARKER" "$rc" 2>/dev/null; then
            printf '\n%s\n%s\n' "$_BREW_MARKER" "$shellenv_line" >> "$rc"
            info "Added Homebrew to $rc"
        fi
    done

    # fish uses its own syntax
    if command -v fish &>/dev/null; then
        local frc="$HOME/.config/fish/config.fish"
        mkdir -p "$(dirname "$frc")"
        if ! grep -qF "$_BREW_MARKER" "$frc" 2>/dev/null; then
            printf '\n%s\n%s shellenv | source\n' "$_BREW_MARKER" "$brew_bin" >> "$frc"
            info "Added Homebrew to $frc"
        fi
    fi
}

_homebrew_deconfigure_shells() {
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.config/fish/config.fish"; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$_BREW_MARKER" "$rc"; then
            sed -i "/^${_BREW_MARKER}$/{N;d}" "$rc"
            info "Removed Homebrew from $rc"
        fi
    done
}

# Install the build toolchain Homebrew needs to compile formulae from source.
_homebrew_install_deps() {
    case "$DISTRO_FAMILY" in
        debian) sudo apt-get install -y build-essential procps curl file git ;;
        fedora) sudo dnf group install -y development-tools 2>/dev/null || sudo dnf groupinstall -y 'Development Tools'
                sudo dnf install -y procps-ng curl file git ;;
        rhel)   sudo "$PKG_MGR" groupinstall -y 'Development Tools'
                sudo "$PKG_MGR" install -y procps-ng curl file git ;;
        arch)   sudo pacman -S --noconfirm --needed base-devel procps-ng curl file git ;;
        suse)   sudo zypper install -y -t pattern devel_basis
                sudo zypper install -y procps curl file git ;;
    esac
}

install_homebrew() {
    info "Installing Homebrew (Linuxbrew)..."
    # Homebrew refuses to install or run as root.
    if [[ $EUID -eq 0 ]]; then
        error "Homebrew cannot be installed as root. Re-run this tool as a normal user (it will use sudo where needed)."
        return 1
    fi
    ensure_tools
    _homebrew_install_deps

    # NONINTERACTIVE=1 skips the installer's confirmation prompt; it still uses
    # sudo internally to create /home/linuxbrew.
    if ! NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        error "Homebrew installation failed."
        return 1
    fi
    _homebrew_configure_shells
    info "Homebrew installed. Open a new shell (or run: eval \"\$(${_BREW_BIN} shellenv)\") then try: brew install <pkg>"
}

uninstall_homebrew() {
    info "Uninstalling Homebrew..."
    if [[ $EUID -eq 0 ]]; then
        error "Homebrew must be uninstalled as the user that owns it, not root."
        return 1
    fi
    warn "All packages installed via Homebrew will be removed."
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" 2>/dev/null || true
    _homebrew_deconfigure_shells
}

update_homebrew() {
    info "Updating Homebrew..."
    local brew_bin
    brew_bin=$(_brew_path) || { error "Homebrew not found."; return 1; }
    "$brew_bin" update && "$brew_bin" upgrade
}

get_version_homebrew() {
    local brew_bin
    brew_bin=$(_brew_path) || { echo ""; return; }
    "$brew_bin" --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
