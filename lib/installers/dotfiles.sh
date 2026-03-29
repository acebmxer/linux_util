#!/bin/bash
# Dotfiles installer functions

check_dotfiles() {
    [[ -d ~/dotfiles ]] || [[ "$(basename "$(getent passwd "$USER" | cut -d: -f7)" 2>/dev/null)" == "zsh" ]]
}

uninstall_dotfiles() {
    info "Uninstalling dotfiles..."

    # Remove dotfiles directory for current user
    if [[ -d ~/dotfiles ]]; then
        rm -rf ~/dotfiles
        info "Removed ~/dotfiles directory."
    fi

    # Remove zsh config files that dotfiles created
    for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.p10k.zsh; do
        [[ -e "$f" || -L "$f" ]] && rm -f "$f" && info "Removed $f"
    done

    # Change shell back to bash for current user
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" == */zsh ]]; then
        chsh -s /bin/bash || warn "Failed to change shell back to bash for current user."
        info "Default shell changed back to bash for $USER."
    fi

    # Clean up root's dotfiles and shell
    sudo -s <<'EOF'
info() { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
if [[ -d ~/dotfiles ]]; then
    rm -rf ~/dotfiles
    info "Removed root's ~/dotfiles directory."
fi
for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.p10k.zsh; do
    [[ -e "$f" || -L "$f" ]] && rm -f "$f" && info "Removed root's $f"
done
if [[ "$(getent passwd root | cut -d: -f7)" == */zsh ]]; then
    if command -v chsh &> /dev/null; then
        chsh -s /bin/bash || warn "Failed to change shell back to bash for root."
        info "Default shell changed back to bash for root."
    else
        warn "chsh not found. Run 'chsh -s /bin/bash' manually for root."
    fi
fi
EOF

    info "Dotfiles uninstall completed."
    return 0
}

setup_install_dotfiles() {
    info "Installing dotfiles..."

    if [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" ]]; then
        warn "Dotfiles installation not supported for Fedora-based distros."
        return 1
    fi

    info "Starting as regular user"
    rm -rf ~/dotfiles
    info "Previous dotfiles folder was removed."
    git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || { warn "Failed to clone dotfiles"; return 1; }
    (
        cd ~/dotfiles || exit 1
        ./install.sh
    ) || { warn "Dotfiles install.sh failed"; return 1; }
    if ! command -v zsh &>/dev/null; then
        sudo apt-get install -y zsh 2>/dev/null || sudo "$PKG_MGR" install -y zsh 2>/dev/null || warn "Could not install zsh automatically."
    fi
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for current user."

    info "Installing dotfiles for root..."
    sudo -s <<'EOF'
info() { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
info "Now running as root"
rm -rf ~/dotfiles
git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || exit 0
cd ~/dotfiles || exit 0
./install.sh
if command -v chsh &> /dev/null; then
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for root."
else
    warn "chsh command not found for root. Run 'chsh -s /bin/zsh' manually after installing util-linux-user package."
fi
EOF
    info "Back to regular user."

    info "Dotfiles installation completed."
    return 0
}
