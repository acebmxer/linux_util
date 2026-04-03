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

    # Dotfiles are only tested on Debian-family distros (Ubuntu, Kubuntu, Debian, etc.)
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        warn "Dotfiles installation is only supported on Debian-family distros (current: ${DISTRO_NAME})."
        return 1
    fi

    info "Starting as regular user"
    if [[ -d ~/dotfiles ]]; then
        warn "Existing ~/dotfiles directory found."
        local _df_confirm=""
        read -rp "Remove it and continue? Any uncommitted changes will be lost. (y/N): " _df_confirm < /dev/tty
        if [[ ! "$_df_confirm" =~ ^[Yy]$ ]]; then
            warn "Dotfiles installation cancelled."
            return 2
        fi
        rm -rf ~/dotfiles
        info "Previous dotfiles folder removed."
    fi
    git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || { warn "Failed to clone dotfiles"; return 1; }
    (
        cd ~/dotfiles || exit 1
        ./install.sh
    ) || { warn "Dotfiles install.sh failed"; return 1; }
    if ! command -v zsh &>/dev/null; then
        pkg_install zsh 2>/dev/null || warn "Could not install zsh automatically."
    fi
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for current user."

    info "Installing dotfiles for root..."
    sudo -s <<'EOF'
info() { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
info "Now running as root"
rm -rf ~/dotfiles
git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || exit 1
cd ~/dotfiles || exit 1
./install.sh || exit 1
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
