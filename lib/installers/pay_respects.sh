#!/bin/bash
# Pay Respects installer functions
# Press F to fix the last command — a Rust command-corrector in the vein of
# thefuck, plus a command-not-found handler and an inline Ctrl+X correction mode.

# --- Pay Respects ---

_PAYR_BASH_BEGIN="# linux_util: pay-respects (bash) -- begin"
_PAYR_BASH_END="# linux_util: pay-respects (bash) -- end"
_PAYR_ZSH_BEGIN="# linux_util: pay-respects (zsh) -- begin"
_PAYR_ZSH_END="# linux_util: pay-respects (zsh) -- end"

check_pay_respects() {
    _have_cmd pay-respects && return 0
    pkg_check_installed pay-respects && return 0
    pkg_check_installed pay-respects-bin
}

# Print the download URL of the newest tagged release asset matching $1 (an ERE).
#
# Upstream keeps a rolling "nightly" build in the releases list, published as an
# ordinary release rather than a prerelease, so it can outrank the tagged
# versions on GitHub's /releases/latest endpoint at any time. Requiring a
# /download/vX.Y.Z/ path skips it and takes the newest numbered release; the
# list is returned newest-first, so the first match is the right one.
_payr_asset_url() {
    local pattern="$1"
    curl -fsSL "https://api.github.com/repos/iffse/pay-respects/releases?per_page=10" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -E '/download/v[0-9]+\.[0-9]+\.[0-9]+/' \
        | grep -m1 -E "$pattern"
}

# Install upstream's own .deb or .rpm ($1 = deb|rpm). Both are dependency-free
# and carry the core binary, the runtime-rules and request-ai modules, and the
# man pages — pay-respects is in no Debian, Ubuntu, Fedora or openSUSE repo.
_payr_install_pkg() {
    local ext="$1" pattern="" url tmpfile tag arch
    arch=$(uname -m)

    case "${ext}:${arch}" in
        deb:x86_64)          pattern='_amd64\.deb$' ;;
        deb:aarch64|deb:arm64) pattern='_arm64\.deb$' ;;
        rpm:x86_64)          pattern='\.x86_64\.rpm$' ;;
        rpm:aarch64|rpm:arm64) pattern='\.aarch64\.rpm$' ;;
        *)
            error "Unsupported architecture for Pay Respects: ${arch}"
            return 1
            ;;
    esac

    url=$(_payr_asset_url "$pattern")
    if [[ -z "$url" ]]; then
        error "Could not find a Pay Respects .${ext} release asset."
        return 1
    fi

    tmpfile=$(mktemp "/tmp/pay-respects-XXXXXX.${ext}")
    CLEANUP_FILES+=("$tmpfile")
    wget -qO "$tmpfile" "$url" || { error "Failed to download Pay Respects .${ext}."; return 1; }
    verify_download "$tmpfile" "$ext" "Pay Respects" || return 1
    # Checksums are looked up per release tag, not from /releases/latest, for the
    # same reason _payr_asset_url walks the list.
    tag=$(basename "$(dirname "$url")")
    github_verify_checksum \
        "https://api.github.com/repos/iffse/pay-respects/releases/tags/${tag}" \
        "$(basename "$url")" "$tmpfile" || return 1
    pkg_install_local "$tmpfile"
}

# pay-respects installs a command_not_found hook of its own. When the
# Command-Not-Found Prompt task has already written its handler into the same rc
# file, two handlers end up in one shell and whichever is sourced last silently
# wins — so hand pay-respects --nocnf and leave the existing prompt in charge.
_payr_init_flags() {
    local rcfile="$1"
    grep -qF "# linux_util: command-not-found" "$rcfile" 2>/dev/null && printf ' --nocnf'
}

# Append the shell-init block for $2 (bash|zsh) to the rc file $1.
# Nothing happens if the block is already there.
_payr_apply_rc() {
    local rcfile="$1" shell="$2" begin="$3" end="$4" flags
    if grep -qF "$begin" "$rcfile" 2>/dev/null; then
        info "Pay Respects ${shell} block already present in ${rcfile}"
        return 0
    fi
    flags=$(_payr_init_flags "$rcfile")

    # printf, not a heredoc: the $(pay-respects ...) call must reach the rc file
    # unexpanded, and the --nocnf flag is decided per file above.
    # The guard is an `if` rather than `&&` so the block does not leave a
    # non-zero $? behind in shells where the binary is gone.
    # shellcheck disable=SC2016  # the rc file, not this script, expands these
    {
        printf '\n%s\n' "$begin"
        printf '%s\n' '# Press F to fix the last command; Ctrl+X twice corrects it inline without running it.'
        printf '%s\n' '# The bundled request-ai module sends the failed command and its error message to'
        printf '%s\n' '# pay-respects'"'"' API server when no local rule matches. Delete the next line to allow that.'
        printf '%s\n' 'export _PR_AI_DISABLE=1'
        printf 'if command -v pay-respects >/dev/null 2>&1; then eval "$(pay-respects %s%s)"; fi\n' "$shell" "$flags"
        printf '%s\n' "$end"
    } >> "$rcfile"
    info "Added Pay Respects ${shell} block to ${rcfile}"
}

# Remove a begin/end marker block using exact string matching (awk), avoiding
# regex-escaping issues with BRE and sed.
_payr_remove_rc() {
    local rcfile="$1" begin="$2" end="$3"
    [[ -f "$rcfile" ]] || return 0
    grep -qF "$begin" "$rcfile" 2>/dev/null || return 0
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { skip=1 }
        skip { if ($0 == end) { skip=0 } next }
        { print }
    ' "$rcfile" > "${rcfile}.tmp" && mv "${rcfile}.tmp" "$rcfile"
    info "Removed Pay Respects block from ${rcfile}"
}

# The binary alone does nothing: the shell has to be told to bind F to it.
# ~/.zshrc is only written when it already exists (zsh may not be set up yet) —
# rerun Update after installing zsh to add it.
_payr_setup_shells() {
    _payr_apply_rc "$HOME/.bashrc" bash "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END"
    [[ -f "$HOME/.zshrc" ]] && _payr_apply_rc "$HOME/.zshrc" zsh "$_PAYR_ZSH_BEGIN" "$_PAYR_ZSH_END"
    return 0
}

install_pay_respects() {
    info "Installing Pay Respects..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _payr_install_pkg deb || return 1
            ;;
        fedora|rhel|suse)
            _payr_install_pkg rpm || return 1
            ;;
        arch)
            # No official repo build — the AUR is the only Arch path, which is
            # why "Pay Respects" is marked AUR-only in lib/installers.sh.
            aur_ensure pay-respects-bin || return 1
            ;;
        *)
            warn "Pay Respects installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, openSUSE, Arch/Manjaro."
            return 1
            ;;
    esac

    _payr_setup_shells

    info "Pay Respects installed."
    info "Open a new terminal, then press F after a failed command to get a fix."
    info "AI suggestions are off by default — remove the _PR_AI_DISABLE line from your shell rc file to enable them."
}

uninstall_pay_respects() {
    info "Uninstalling Pay Respects..."

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y pay-respects 2>/dev/null || true
            ;;
        fedora|rhel|suse)
            sudo "$PKG_MGR" remove -y pay-respects 2>/dev/null || true
            ;;
        arch)
            aur_remove pay-respects-bin 2>/dev/null || \
                sudo pacman -Rs --noconfirm pay-respects 2>/dev/null || true
            ;;
    esac

    _payr_remove_rc "$HOME/.bashrc" "$_PAYR_BASH_BEGIN" "$_PAYR_BASH_END"
    _payr_remove_rc "$HOME/.zshrc"  "$_PAYR_ZSH_BEGIN"  "$_PAYR_ZSH_END"

    # Custom rules and config live here; nothing else on the system is touched.
    rm -rf "$HOME/.config/pay-respects"

    info "Pay Respects has been uninstalled."
}

update_pay_respects() {
    info "Updating Pay Respects..."
    case "$DISTRO_FAMILY" in
        debian)            _payr_install_pkg deb || return 1 ;;
        fedora|rhel|suse)  _payr_install_pkg rpm || return 1 ;;
        arch)              aur_ensure pay-respects-bin || return 1 ;;
        *)                 install_pay_respects; return ;;
    esac
    # Picks up a ~/.zshrc that appeared after the initial install.
    _payr_setup_shells
}

get_version_pay_respects() {
    _ver_from_pkg pay-respects \
        || _ver_from_pkg pay-respects-bin \
        || _ver_from_cmd pay-respects \
        || echo ""
}
