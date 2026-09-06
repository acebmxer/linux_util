#!/bin/bash
# tmux-resurrect installer functions

# --- tmux Resurrect ---
#
# tmux sessions live in the tmux server's memory, so they survive a dropped SSH
# connection but not a reboot of the machine they run on. tmux-resurrect closes
# that gap: it saves the session layout to disk and restores it afterwards.
#
# What it restores is windows, panes, working directories and layout -- not the
# processes that were running in them. A long job interrupted by a reboot is
# still gone; what comes back is the workspace it was running in.
#
# It is a tmux plugin, not a distro package -- no repo ships it -- so it is
# installed by cloning upstream, the same way the Zsh plugins are handled.

_TMUX_RESURRECT_DIR="$HOME/.tmux/plugins/tmux-resurrect"
_TMUX_RESURRECT_REPO="https://github.com/tmux-plugins/tmux-resurrect"

# Markers delimit the block so the uninstaller removes exactly what was added.
_TMUX_RESURRECT_MARKER="# >>> linux_util tmux-resurrect >>>"
_TMUX_RESURRECT_MARKER_END="# <<< linux_util tmux-resurrect <<<"

check_tmux_resurrect() { [[ -d "$_TMUX_RESURRECT_DIR" ]]; }

install_tmux_resurrect() {
    info "Installing tmux Resurrect..."

    # The plugin is inert without tmux itself, so pull tmux in first rather than
    # leaving a clone that does nothing.
    if ! check_tmux; then
        info "tmux is required by tmux-resurrect; installing it first..."
        install_tmux || { error "tmux installation failed."; return 1; }
    fi

    ensure_tools
    if [[ -d "$_TMUX_RESURRECT_DIR" ]]; then
        info "tmux Resurrect is already present."
    else
        git clone --depth=1 "$_TMUX_RESURRECT_REPO" "$_TMUX_RESURRECT_DIR" 2>/dev/null \
            || { error "Could not clone tmux-resurrect."; return 1; }
    fi

    _tmux_resurrect_configure

    info "tmux Resurrect installed. Save with prefix + Ctrl-s, restore with prefix + Ctrl-r."
}

# Wire the plugin into ~/.tmux.conf. Sourcing the plugin directly is deliberate:
# it avoids making TPM (a second plugin manager) a dependency for one plugin.
_tmux_resurrect_configure() {
    local conf="$HOME/.tmux.conf"

    if grep -q "$_TMUX_RESURRECT_MARKER" "$conf" 2>/dev/null; then
        info "tmux Resurrect is already configured in ${conf}."
        return 0
    fi

    cat >> "$conf" <<EOF

${_TMUX_RESURRECT_MARKER}
# Save and restore tmux sessions across reboots.
#   prefix + Ctrl-s  save
#   prefix + Ctrl-r  restore
run-shell ${_TMUX_RESURRECT_DIR}/resurrect.tmux
${_TMUX_RESURRECT_MARKER_END}
EOF

    info "tmux Resurrect configured in ${conf}."

    # A running server has already read its config, so the keybindings would not
    # appear until the next server start without this.
    if check_tmux && tmux has-session 2>/dev/null; then
        tmux source-file "$conf" 2>/dev/null \
            && info "Reloaded the running tmux configuration." \
            || warn "Could not reload tmux; run 'tmux source-file ${conf}'."
    fi
}

uninstall_tmux_resurrect() {
    info "Uninstalling tmux Resurrect..."
    _tmux_resurrect_deconfigure
    rm -rf "$_TMUX_RESURRECT_DIR"

    # Saved sessions are the user's data, not ours to delete.
    if [[ -d "$HOME/.local/share/tmux/resurrect" ]]; then
        info "Saved sessions kept at ~/.local/share/tmux/resurrect (remove by hand if unwanted)."
    fi
}

# Strip only the marked block; the rest of ~/.tmux.conf is the user's own.
_tmux_resurrect_deconfigure() {
    local conf="$HOME/.tmux.conf"
    [[ -f "$conf" ]] || return 0
    grep -q "$_TMUX_RESURRECT_MARKER" "$conf" 2>/dev/null || return 0
    sed -i "\|${_TMUX_RESURRECT_MARKER}|,\|${_TMUX_RESURRECT_MARKER_END}|d" "$conf"
    info "Removed the tmux Resurrect block from ${conf}."
}

update_tmux_resurrect() {
    info "Updating tmux Resurrect..."
    [[ -d "$_TMUX_RESURRECT_DIR" ]] || { install_tmux_resurrect; return $?; }
    git -C "$_TMUX_RESURRECT_DIR" pull --ff-only 2>/dev/null \
        || warn "Could not update tmux-resurrect; leaving the existing checkout in place."
}

get_version_tmux_resurrect() {
    [[ -d "$_TMUX_RESURRECT_DIR" ]] || { echo ""; return; }
    git -C "$_TMUX_RESURRECT_DIR" log -1 --format=%cd --date=short 2>/dev/null || echo ""
}
