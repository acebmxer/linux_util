#!/bin/bash
# tmux installer functions

# --- tmux ---
#
# tmux is the session-persistence answer for SSH: the server runs on the remote
# machine only, so a dropped connection kills the client while the session and
# everything running in it stay alive. Reattaching lands back in the same shell.
# Nothing is needed on the local side, which is why it works from any terminal
# emulator or SSH client (Konsole, GNOME Terminal, Termius, a phone) -- unlike
# mosh or Eternal Terminal, which need matching binaries at both ends.
#
# This installer is deliberately a stock package install and nothing more: it
# does not write to ~/.tmux.conf, ~/.bashrc or ~/.zshrc. tmux configuration is
# the user's own. Do not add shell-rc or config-file editing back here.

check_tmux() { _check_standard tmux tmux ""; }

install_tmux() {
    info "Installing tmux..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install tmux ;;
        fedora|rhel) pkg_install tmux ;;
        arch)        pkg_install tmux ;;
        suse)        pkg_install tmux ;;
    esac
    check_tmux || { error "tmux installation failed."; return 1; }

    info "tmux installed. Start a session with 'tmux new -s work', reattach with 'tmux attach'."
}

uninstall_tmux() {
    info "Uninstalling tmux..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove tmux ;;
        fedora|rhel) pkg_remove tmux ;;
        arch)        pkg_remove tmux ;;
        suse)        pkg_remove tmux ;;
    esac
}

update_tmux() {
    info "Updating tmux..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade tmux ;;
        fedora|rhel) pkg_upgrade tmux ;;
        arch)        pkg_upgrade tmux ;;
        suse)        pkg_upgrade tmux ;;
    esac
}

get_version_tmux() {
    _ver_from_cmd tmux || echo ""
}
