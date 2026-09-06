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

check_tmux() { _check_standard tmux tmux ""; }

# Markers delimit the block so the uninstaller removes exactly what was added.
_TMUX_AUTOATTACH_MARKER="# >>> linux_util tmux auto-attach >>>"
_TMUX_AUTOATTACH_MARKER_END="# <<< linux_util tmux auto-attach <<<"


install_tmux() {
    info "Installing tmux..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y tmux ;;
        fedora|rhel) sudo "$PKG_MGR" install -y tmux ;;
        arch)        sudo pacman -S --noconfirm tmux ;;
        suse)        sudo zypper install -y tmux ;;
    esac
    check_tmux || { error "tmux installation failed."; return 1; }

    _tmux_offer_autoattach

    info "tmux installed. Start a session with 'tmux new -s work', reattach with 'tmux attach'."
}

# Offer the auto-attach line for the user's shell rc. An interactive login then
# lands straight back in the persistent session instead of a bare shell.
#
# This edits a file the user owns, so it is always a question and never silent.
# The default is yes, but a non-interactive run (--yes, CI, a piped stdin) takes
# the safe branch and skips it: no unattended run may rewrite a login shell's rc.
_tmux_offer_autoattach() {
    local answer=""

    # An explicit opt-in to unattended runs answers the default (yes) for us.
    if [[ "${CFG_AUTO_CONFIRM:-false}" == "true" ]]; then
        info "Adding the shell auto-attach snippet [auto-confirmed]."
        _tmux_write_autoattach
        return $?
    fi

    # Otherwise a run with no terminal cannot be asked, and rewriting a login
    # shell's rc unattended is not a decision to take on the user's behalf.
    if [[ ! -t 0 ]]; then
        info "Non-interactive run: skipping the shell auto-attach snippet."
        info "Re-run from a terminal, or set auto_confirm=true, to add it."
        return 0
    fi

    echo ""
    echo "  Add an auto-attach line to your shell startup file?"
    echo "  On an interactive login it reattaches to your 'work' session, or"
    echo "  creates it, so an SSH drop puts you back where you were."
    echo "  This appends a few lines to a file you maintain (e.g. ~/.bashrc)."
    echo ""

    while true; do
        read -rp "  Add the auto-attach snippet? [Y/n]: " answer
        answer="${answer:-Y}"
        case "${answer,,}" in
            y|yes) _tmux_write_autoattach; return $? ;;
            n|no)
                info "Skipped. Add it later by re-running this installer."
                return 0
                ;;
            *) echo "  Please enter Y or N." ;;
        esac
    done
}

# Append the guarded auto-attach block to the rc file for the running shell.
# The single definition of the rc block. _tmux_write_autoattach compares what an
# rc file already has against this, so any change here is picked up on a re-run
# without needing a new bespoke staleness check for each edit.
_tmux_autoattach_block() {
    cat <<EOF
${_TMUX_AUTOATTACH_MARKER}
# Reattach to a persistent tmux session on interactive login, so a dropped
# connection can be resumed. Skipped when already inside tmux and when the
# shell is not interactive (scp, rsync, git).
if [ -z "\$TMUX" ] && command -v tmux >/dev/null 2>&1; then
    case \$- in
        *i*)
            # fastfetch runs only on the branch that creates the session, so a
            # reattach after a dropped connection returns you to your work
            # without reprinting the banner over it.
            if ! tmux attach -t work 2>/dev/null; then
                command -v fastfetch >/dev/null 2>&1 && fastfetch
                tmux new -s work
            fi
            ;;
    esac
fi
${_TMUX_AUTOATTACH_MARKER_END}
EOF
}

_tmux_write_autoattach() {
    local rc
    case "$(basename "${SHELL:-/bin/bash}")" in
        zsh)  rc="$HOME/.zshrc" ;;
        bash) rc="$HOME/.bashrc" ;;
        *)
            warn "Unrecognized shell '${SHELL}'. Add the auto-attach line by hand."
            return 0
            ;;
    esac

    if grep -q "$_TMUX_AUTOATTACH_MARKER" "$rc" 2>/dev/null; then
        # Compare what is on disk against what we would write now. Earlier
        # versions checked for one specific defect at a time ([ -t 1 ], a block
        # below the p10k preamble), which meant every later change to the block
        # needed its own new check and silently no-op'd on existing installs
        # until it got one. A content comparison covers all of them at once.
        local current
        current=$(sed -n "\|${_TMUX_AUTOATTACH_MARKER}|,\|${_TMUX_AUTOATTACH_MARKER_END}|p" "$rc")

        local misplaced=false
        local _p10k _blk
        _p10k=$(grep -n 'p10k-instant-prompt' "$rc" 2>/dev/null | head -1 | cut -d: -f1)
        _blk=$(grep -n "$_TMUX_AUTOATTACH_MARKER" "$rc" 2>/dev/null | head -1 | cut -d: -f1)
        if [[ -n "$_p10k" && -n "$_blk" ]] && (( _blk > _p10k )); then
            misplaced=true
        fi

        if [[ "$current" == "$(_tmux_autoattach_block)" && "$misplaced" == false ]]; then
            info "Auto-attach snippet already present in ${rc}."
            return 0
        fi

        info "Replacing an outdated auto-attach snippet in ${rc}."
        _tmux_remove_autoattach_quiet "$rc" || return 1
    fi

    # The guards matter: without them tmux would recurse inside its own shells,
    # and scp/rsync/git-over-SSH would break on a non-interactive session that
    # suddenly speaks terminal escapes.
    #
    # Interactivity is tested with \$- and NOT with [ -t 1 ]. While an rc file is
    # being sourced during shell startup, stdout is not yet connected to the
    # terminal, so [ -t 1 ] is false even in a real interactive SSH login -- the
    # block would never run. \$- carries 'i' for exactly the interactive shells
    # we want and is absent for 'ssh host cmd', scp and rsync.
    local block
    block=$(_tmux_autoattach_block)

    # Powerlevel10k's instant prompt takes over the console partway through
    # .zshrc and warns about "console output during zsh initialization" for
    # anything after it -- and tmux started from there gets no terminal at all
    # ("open terminal failed: not a terminal"). p10k documents that such code
    # must run *above* the preamble, so insert there when it is present.
    local p10k_line
    p10k_line=$(grep -n 'p10k-instant-prompt' "$rc" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$p10k_line" ]]; then
        # Back up to the comment block p10k puts above its own guard, so the
        # snippet lands before the preamble rather than inside its comments.
        local insert_at="$p10k_line"
        while (( insert_at > 1 )) &&
              [[ "$(sed -n "$((insert_at - 1))p" "$rc")" =~ ^[[:space:]]*(#.*)?$ ]]; do
            insert_at=$((insert_at - 1))
        done
        local tmp
        tmp=$(mktemp) || return 1
        {
            (( insert_at > 1 )) && sed -n "1,$((insert_at - 1))p" "$rc"
            printf '%s\n\n' "$block"
            sed -n "${insert_at},\$p" "$rc"
        } > "$tmp" && cat "$tmp" > "$rc"
        rm -f "$tmp"
        info "Auto-attach snippet added to ${rc}, above the Powerlevel10k instant prompt."
        info "Takes effect on your next login."
        return 0
    fi

    printf '\n%s\n' "$block" >> "$rc"

    info "Auto-attach snippet added to ${rc} (takes effect on your next login)."
}

uninstall_tmux() {
    info "Uninstalling tmux..."
    _tmux_remove_autoattach
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y tmux ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y tmux ;;
        arch)        sudo pacman -Rs --noconfirm tmux ;;
        suse)        sudo zypper remove -y tmux ;;
    esac
}

# Delete the marked block from one rc file, without announcing it. Shared with
# _tmux_remove_autoattach so the deletion pattern exists in exactly one place --
# do not add a third copy of this sed.
_tmux_remove_autoattach_quiet() {
    local rc="$1"
    sed -i "\|${_TMUX_AUTOATTACH_MARKER}|,\|${_TMUX_AUTOATTACH_MARKER_END}|d" "$rc"
}

# Strip the marked block from whichever rc files carry it. Only the block this
# installer wrote is touched; the rest of the user's rc is left alone.
_tmux_remove_autoattach() {
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        grep -q "$_TMUX_AUTOATTACH_MARKER" "$rc" 2>/dev/null || continue
        _tmux_remove_autoattach_quiet "$rc"
        info "Removed the auto-attach snippet from ${rc}."
    done
}

update_tmux() {
    info "Updating tmux..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade tmux ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y tmux ;;
        arch)        sudo pacman -S --noconfirm tmux ;;
        suse)        sudo zypper update -y tmux ;;
    esac
}

get_version_tmux() {
    _ver_from_cmd tmux || echo ""
}
