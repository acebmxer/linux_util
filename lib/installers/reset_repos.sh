#!/bin/bash
# Reset Repos to Default — restore base distro repositories toward their stock
# state, while detecting third-party repos that installed packages depend on and
# keeping those. Action-style system task. Everything is backed up first, and
# every removal/disable is confirmed (per repo).
#
# Reliability notes (documented for maintainers):
#   - dnf/zypper: stock repo files are owned by an rpm (rpm -qf), so "default vs
#     third-party" is a clean signal. dnf records each package's origin repo
#     (from_repo), so dependency detection is reliable.
#   - pacman: default = core/extra/multilib; pacman -Sl <repo> marks installed
#     packages, so detection is reliable for currently-enabled repos.
#   - apt: there is no canonical "reset" command and derivatives (Mint, Pop,
#     Zorin, …) define their own defaults, so detection is HEURISTIC (maps repo
#     host → /var/lib/apt/lists index → installed set) and base-source
#     regeneration is only attempted for recognized Ubuntu/Debian layouts.

# --- Shared: back up the given repo paths to a timestamped dir; echo its path ---
_reset_repos_backup() {
    local ts backup_dir p
    ts=$(date +%Y%m%d_%H%M%S)
    backup_dir="/var/backups/linux_util/repos_backup_${ts}"
    sudo mkdir -p "$backup_dir" || { error "Could not create backup directory ${backup_dir}"; return 1; }
    for p in "$@"; do
        [[ -e "$p" ]] || continue
        sudo cp -a "$p" "$backup_dir/" 2>/dev/null || true
    done
    echo "$backup_dir"
}

# --- Shared: decide what to do with one third-party repo ---
# $1 = human label, $2 = newline-separated installed packages depending on it.
# Auto-keeps repos with dependents; otherwise prompts. Echoes: keep|disable|remove.
# All human-facing output goes to stderr so the action is the only thing on stdout.
_reset_repo_prompt() {
    local label="$1" pkgs="$2" count reply=""
    if [[ -n "$pkgs" ]]; then
        count=$(printf '%s\n' "$pkgs" | grep -c .)
        info "Keeping ${label} — ${count} installed package(s) depend on it:" >&2
        printf '%s\n' "$pkgs" | sed 's/^/      /' >&2
        echo "keep"
        return 0
    fi
    warn "${label} — no installed packages depend on it." >&2
    read -rp "${YELLOW:-}  [k]eep / [d]isable / [r]emove? [k]: ${RESET:-}" reply < /dev/tty
    case "${reply,,}" in
        d|disable) echo "disable" ;;
        r|remove)  echo "remove" ;;
        *)         echo "keep" ;;
    esac
}

# ============================================================================
# apt (Debian/Ubuntu family)
# ============================================================================

# Installed packages provided by the repo(s) defined in a sources file.
# Heuristic: repo host → matching /var/lib/apt/lists index → ∩ installed set.
_apt_repo_installed_pkgs() {
    local file="$1" installed="$2" hosts h idx provided
    hosts=$(grep -hoE 'https?://[^ ]+' "$file" 2>/dev/null | sed -E 's#https?://##; s#/.*##' | sort -u)
    [[ -z "$hosts" ]] && return 0
    provided=$(mktemp)
    shopt -s nullglob
    for h in $hosts; do
        for idx in /var/lib/apt/lists/*"$h"*; do
            [[ "$idx" == *_Packages ]] || continue
            grep -a '^Package: ' "$idx" 2>/dev/null | awk '{print $2}'
        done
    done | sort -u > "$provided"
    shopt -u nullglob
    comm -12 "$provided" "$installed"
    rm -f "$provided"
}

_apt_restore_base_sources() {
    local backup_dir="$1" codename="${DISTRO_VERSION_CODENAME:-}"
    if [[ -z "$codename" ]]; then
        warn "Could not determine release codename; leaving base sources unchanged."
        return 0
    fi
    case "$DISTRO_ID" in
        ubuntu|kubuntu|neon)
            _confirm_step "Regenerate stock Ubuntu base sources for '${codename}'? (overwrites the base source list)" || { info "Left base sources unchanged."; return 0; }
            if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
                printf 'Types: deb\nURIs: http://archive.ubuntu.com/ubuntu/\nSuites: %s %s-updates %s-backports\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\nTypes: deb\nURIs: http://security.ubuntu.com/ubuntu/\nSuites: %s-security\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
                    "$codename" "$codename" "$codename" "$codename" | sudo tee /etc/apt/sources.list.d/ubuntu.sources >/dev/null
                sudo truncate -s 0 /etc/apt/sources.list 2>/dev/null || true
            else
                printf 'deb http://archive.ubuntu.com/ubuntu %s main restricted universe multiverse\ndeb http://archive.ubuntu.com/ubuntu %s-updates main restricted universe multiverse\ndeb http://archive.ubuntu.com/ubuntu %s-backports main restricted universe multiverse\ndeb http://security.ubuntu.com/ubuntu %s-security main restricted universe multiverse\n' \
                    "$codename" "$codename" "$codename" "$codename" | sudo tee /etc/apt/sources.list >/dev/null
            fi
            info "Regenerated stock Ubuntu base sources."
            ;;
        debian)
            _confirm_step "Regenerate stock Debian base sources for '${codename}'? (overwrites the base source list)" || { info "Left base sources unchanged."; return 0; }
            printf 'deb http://deb.debian.org/debian %s main contrib non-free non-free-firmware\ndeb http://deb.debian.org/debian %s-updates main contrib non-free non-free-firmware\ndeb http://security.debian.org/debian-security %s-security main contrib non-free non-free-firmware\n' \
                "$codename" "$codename" "$codename" | sudo tee /etc/apt/sources.list >/dev/null
            info "Regenerated stock Debian base sources."
            ;;
        *)
            warn "Base-source regeneration is not supported for '${DISTRO_ID}' (derivative defaults vary)."
            warn "Third-party repo cleanup still ran; base sources left as-is. Backup: ${backup_dir}"
            ;;
    esac
}

_reset_repos_apt() {
    local backup_dir installed_tmp f pkgs action
    backup_dir=$(_reset_repos_backup /etc/apt/sources.list /etc/apt/sources.list.d) || return 1
    info "Backed up apt sources to ${backup_dir}"

    installed_tmp=$(mktemp)
    dpkg-query -W -f '${Package}\n' 2>/dev/null | sort -u > "$installed_tmp"

    shopt -s nullglob
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$f" ]] || continue
        pkgs=$(_apt_repo_installed_pkgs "$f" "$installed_tmp")
        action=$(_reset_repo_prompt "${f##*/}" "$pkgs")
        case "$action" in
            disable) sudo mv "$f" "${f}.disabled" && info "Disabled ${f##*/}" ;;
            remove)  sudo rm -f "$f" && info "Removed ${f##*/}" ;;
        esac
    done
    shopt -u nullglob
    rm -f "$installed_tmp"

    _apt_restore_base_sources "$backup_dir"

    info "Refreshing package lists (apt-get update)..."
    sudo apt-get update || warn "apt-get update reported errors."
}

# ============================================================================
# dnf / yum (Fedora / RHEL family)
# ============================================================================

# Set enabled=0 for every repo section in a .repo file (uniform across dnf/dnf5/yum).
_repofile_disable() {
    local f="$1" tmp
    tmp=$(awk '
        /^\[/                  { if (sec && !done) print "enabled=0"; print; sec=1; done=0; next }
        /^[[:space:]]*enabled[[:space:]]*=/ { if (sec) { print "enabled=0"; done=1; next } }
        /^[[:space:]]*$/        { if (sec && !done) { print "enabled=0"; done=1 } print; next }
        { print }
        END { if (sec && !done) print "enabled=0" }
    ' "$f")
    printf '%s\n' "$tmp" | sudo tee "$f" >/dev/null
}

_reset_repos_dnf() {
    local backup_dir origin_tmp f ids id pkgs action relpkgs
    backup_dir=$(_reset_repos_backup /etc/yum.repos.d) || return 1
    info "Backed up repo files to ${backup_dir}"

    origin_tmp=$(mktemp)
    "${PKG_MGR}" repoquery --installed --qf '%{from_repo} %{name}\n' 2>/dev/null > "$origin_tmp" || true

    shopt -s nullglob
    for f in /etc/yum.repos.d/*.repo; do
        # Stock repo files are owned by an rpm package (e.g. fedora-repos, rocky-release).
        if rpm -qf "$f" &>/dev/null; then
            verbose "Keeping stock repo file ${f##*/} (owned by $(rpm -qf "$f" 2>/dev/null))"
            continue
        fi
        ids=$(grep -oE '^\[[^]]+\]' "$f" | tr -d '[]')
        pkgs=""
        for id in $ids; do
            pkgs+="$(awk -v r="$id" '$1==r {print $2}' "$origin_tmp")"$'\n'
        done
        pkgs=$(printf '%s' "$pkgs" | sed '/^$/d' | sort -u)
        action=$(_reset_repo_prompt "${f##*/}" "$pkgs")
        case "$action" in
            disable) _repofile_disable "$f" && info "Disabled ${f##*/}" ;;
            remove)  sudo rm -f "$f" && info "Removed ${f##*/}" ;;
        esac
    done
    shopt -u nullglob
    rm -f "$origin_tmp"

    if _confirm_step "Reinstall the distro release package(s) to restore stock repo definitions?"; then
        relpkgs=$(rpm -qa --qf '%{name}\n' 2>/dev/null | grep -E -- '-(release|repos)$' | tr '\n' ' ')
        [[ -n "$relpkgs" ]] && sudo "${PKG_MGR}" reinstall -y $relpkgs
    fi
    sudo "${PKG_MGR}" clean all && sudo "${PKG_MGR}" makecache || true
}

# ============================================================================
# pacman (Arch family)
# ============================================================================

# Comment out a [repo] section (header + its body) in pacman.conf. Reversible.
_pacman_comment_repo() {
    local conf="$1" repo="$2" tmp
    tmp=$(awk -v r="[$repo]" '
        $0==r            { inblk=1; print "#"$0; next }
        inblk && /^\[/   { inblk=0 }
        inblk && /^[[:space:]]*$/ { inblk=0; print; next }
        inblk            { print "#"$0; next }
        { print }
    ' "$conf")
    printf '%s\n' "$tmp" | sudo tee "$conf" >/dev/null
}

_reset_repos_pacman() {
    local conf=/etc/pacman.conf backup_dir repos r pkgs action
    backup_dir=$(_reset_repos_backup /etc/pacman.conf /etc/pacman.d) || return 1
    info "Backed up pacman config to ${backup_dir}"

    # Mainline Arch defaults. Derivative defaults vary, so anything else is prompted.
    local default_repos=" core extra multilib "
    repos=$(grep -oE '^\[[^]]+\]' "$conf" | tr -d '[]' | grep -v '^options$')

    for r in $repos; do
        [[ "$default_repos" == *" $r "* ]] && continue
        pkgs=$(pacman -Sl "$r" 2>/dev/null | awk '/\[installed/ {print $2}')
        action=$(_reset_repo_prompt "[$r] in pacman.conf" "$pkgs")
        # disable and remove both comment the section out (clean deletion of a
        # config block is error-prone; commenting is reversible and equivalent here).
        case "$action" in
            disable|remove) _pacman_comment_repo "$conf" "$r" && info "Commented out [$r] in pacman.conf" ;;
        esac
    done

    info "Force-refreshing databases (pacman -Syy)..."
    sudo pacman -Syy || warn "Database refresh reported issues."
}

# ============================================================================
# zypper (openSUSE family)
# ============================================================================

_reset_repos_zypper() {
    local backup_dir map_tmp f alias_ pkgs action
    backup_dir=$(_reset_repos_backup /etc/zypp/repos.d) || return 1
    info "Backed up zypper repos to ${backup_dir}"

    map_tmp=$(mktemp)
    zypper --non-interactive search -i -t package --details 2>/dev/null > "$map_tmp" || true

    shopt -s nullglob
    for f in /etc/zypp/repos.d/*.repo; do
        if rpm -qf "$f" &>/dev/null; then
            verbose "Keeping stock repo file ${f##*/} (owned by $(rpm -qf "$f" 2>/dev/null))"
            continue
        fi
        alias_=$(grep -oE '^\[[^]]+\]' "$f" | head -1 | tr -d '[]')
        # Repository name is the last '|'-separated column in the search output.
        pkgs=$(awk -F'|' -v r="$alias_" 'NR>2 && $NF ~ r {gsub(/^[ \t]+|[ \t]+$/,"",$2); if($2!="") print $2}' "$map_tmp" | sort -u)
        action=$(_reset_repo_prompt "${f##*/} (alias: ${alias_})" "$pkgs")
        case "$action" in
            disable) sudo zypper modifyrepo --disable "$alias_" && info "Disabled ${alias_}" ;;
            remove)  sudo zypper removerepo "$alias_" && info "Removed ${alias_}" ;;
        esac
    done
    shopt -u nullglob
    rm -f "$map_tmp"

    info "Refreshing repositories..."
    sudo zypper refresh || warn "Repository refresh reported issues."
}

# ============================================================================
# Dispatcher
# ============================================================================
setup_reset_repos() {
    warn "This resets package repositories toward their distro defaults."
    echo "  • All current repo configuration is backed up first (/var/backups/linux_util)."
    echo "  • Third-party repos with installed packages depending on them are kept automatically."
    echo "  • You'll be prompted (keep/disable/remove) for each third-party repo nothing depends on."
    echo ""
    if ! _confirm_step "Proceed with repository reset?"; then
        info "Cancelled."
        return 3
    fi

    case "${PKG_MGR:-}" in
        apt)     _reset_repos_apt ;;
        dnf|yum) _reset_repos_dnf ;;
        pacman)  _reset_repos_pacman ;;
        zypper)  _reset_repos_zypper ;;
        *)       error "Unsupported package manager: ${PKG_MGR:-unknown}"; return 1 ;;
    esac

    info "Repository reset complete."
    _repair_done
}
