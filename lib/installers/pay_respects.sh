#!/bin/bash
# Pay Respects installer functions
# Press F to fix the last command — a Rust command-corrector in the vein of
# thefuck, plus a command-not-found handler and an inline Ctrl+X correction mode.

# --- Pay Respects ---

# Arch installs upstream's static musl tarball rather than the AUR. The AUR
# package is honest (its maintainer, iff, is upstream), but it is not needed:
# the tarball carries the same static-pie binaries, so there is nothing to build
# and no dependency to resolve, and using it keeps Pay Respects installable with
# AUR_ENABLED=false. The layout below mirrors upstream's own .deb -- all three
# binaries on PATH, man pages beside them -- so every family ends up with the
# same arrangement. Module discovery works off PATH by the _pay-respects-*
# naming convention, which is why no _PR_LIB wiring is needed here.
_PAYR_PREFIX="/usr/local"
_PAYR_BINS=(pay-respects _pay-respects-module-100-runtime-rules
            _pay-respects-fallback-100-request-ai)

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
#
# curl is kept out of the pipeline and no filter stops early: a consumer that
# exits on its first match closes the pipe mid-body, and curl reports that as
# "(23) Failure writing output to destination" on stderr instead of dying
# quietly on SIGPIPE the way grep does. The first line of the result is taken
# with a parameter expansion for the same reason.
_payr_asset_url() {
    local pattern="$1" json matches
    json=$(curl -fsSL "https://api.github.com/repos/iffse/pay-respects/releases?per_page=10") || return 1
    matches=$(printf '%s\n' "$json" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -E '/download/v[0-9]+\.[0-9]+\.[0-9]+/' \
        | grep -E "$pattern") || return 1
    printf '%s\n' "${matches%%$'\n'*}"
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

# Install upstream's static musl tarball into /usr/local (Arch path).
#
# /usr/local, not /usr: nothing here is registered with pacman, and writing into
# pacman's prefix would put unowned files where a future repo package would
# collide with them.
_payr_install_tarball() {
    local pattern url tmpdir tarball tag arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)        pattern='x86_64-unknown-linux-musl\.tar\.zst$' ;;
        aarch64|arm64) pattern='aarch64-unknown-linux-musl\.tar\.zst$' ;;
        armv7l)        pattern='armv7-unknown-linux-musleabihf\.tar\.zst$' ;;
        i686|i386)     pattern='i686-unknown-linux-musl\.tar\.zst$' ;;
        *)
            error "Unsupported architecture for Pay Respects: ${arch}"
            return 1
            ;;
    esac

    if ! command -v zstd &>/dev/null; then
        info "Installing zstd (needed to unpack the Pay Respects tarball)..."
        pkg_install zstd || { error "Could not install zstd."; return 1; }
    fi

    url=$(_payr_asset_url "$pattern")
    if [[ -z "$url" ]]; then
        error "Could not find a Pay Respects musl tarball release asset."
        return 1
    fi

    tmpdir=$(mktemp -d /tmp/pay-respects-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tarball="$tmpdir/payr.tar.zst"

    wget -qO "$tarball" "$url" || { error "Failed to download Pay Respects tarball."; return 1; }
    tag=$(basename "$(dirname "$url")")
    github_verify_checksum \
        "https://api.github.com/repos/iffse/pay-respects/releases/tags/${tag}" \
        "$(basename "$url")" "$tarball" || return 1

    mkdir -p "$tmpdir/payload"
    if ! zstd -dc "$tarball" | tar x -C "$tmpdir/payload"; then
        error "Failed to unpack the Pay Respects tarball."
        return 1
    fi

    # Verify before installing anything: a layout change upstream should abort
    # rather than leave a half-installed set of binaries behind.
    local b
    for b in "${_PAYR_BINS[@]}"; do
        if [[ ! -f "$tmpdir/payload/$b" ]]; then
            error "Pay Respects tarball is missing '${b}' — upstream layout changed."
            return 1
        fi
    done

    for b in "${_PAYR_BINS[@]}"; do
        sudo install -Dm755 "$tmpdir/payload/$b" "${_PAYR_PREFIX}/bin/$b" || {
            error "Failed to install ${b} to ${_PAYR_PREFIX}/bin."
            return 1
        }
    done

    # Man pages are best-effort: a missing page is not a reason to fail an
    # otherwise working install. Section comes from the filename suffix.
    local page name section
    for page in "$tmpdir"/payload/man/*.[15]; do
        [[ -f "$page" ]] || continue
        name=$(basename "$page")
        section="${name##*.}"
        sudo install -Dm644 "$page" \
            "${_PAYR_PREFIX}/share/man/man${section}/${name}" 2>/dev/null || true
    done
    [[ -f "$tmpdir/payload/LICENSE" ]] && sudo install -Dm644 "$tmpdir/payload/LICENSE" \
        "${_PAYR_PREFIX}/share/licenses/pay-respects/LICENSE" 2>/dev/null

    command -v mandb &>/dev/null && sudo mandb -q 2>/dev/null || true
    return 0
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
            # A derivative that packages it in its own repos still wins; the
            # fallback is upstream's tarball, never the AUR.
            if ! (arch_repo_has pay-respects && pkg_install pay-respects); then
                _payr_install_tarball || return 1
            fi
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

# Remove what _payr_install_tarball laid down. Only ever called on Arch, and
# only touches paths this installer owns.
_payr_remove_tarball() {
    local b
    for b in "${_PAYR_BINS[@]}"; do
        sudo rm -f "${_PAYR_PREFIX}/bin/$b"
    done
    sudo rm -f "${_PAYR_PREFIX}/share/man/man1/pay-respects.1" \
               "${_PAYR_PREFIX}/share/man/man5/pay-respects.5" \
               "${_PAYR_PREFIX}/share/man/man5/pay-respects-rules.5" \
               "${_PAYR_PREFIX}/share/man/man5/pay-respects-modules.5"
    sudo rm -rf "${_PAYR_PREFIX}/share/licenses/pay-respects"
    command -v mandb &>/dev/null && sudo mandb -q 2>/dev/null || true
    return 0
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
            # Package first (an AUR or repo install predating the tarball
            # path), then the files this installer lays down itself.
            if pkg_check_installed pay-respects-bin; then
                sudo pacman -Rs --noconfirm pay-respects-bin 2>/dev/null || true
            elif pkg_check_installed pay-respects; then
                sudo pacman -Rs --noconfirm pay-respects 2>/dev/null || true
            fi
            _payr_remove_tarball
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
        arch)
            if pkg_check_installed pay-respects || pkg_check_installed pay-respects-bin; then
                repo_or_aur pay-respects || _payr_install_tarball || return 1
            else
                _payr_install_tarball || return 1
            fi
            ;;
        *)                 install_pay_respects; return ;;
    esac
    # Picks up a ~/.zshrc that appeared after the initial install.
    _payr_setup_shells
}

get_version_pay_respects() {
    # The tarball install is not registered with any package manager, so the
    # binary's own --version ("version: 0.8.8") is the only source for it.
    _ver_from_pkg pay-respects \
        || _ver_from_pkg pay-respects-bin \
        || _ver_from_cmd pay-respects \
        || echo ""
}
