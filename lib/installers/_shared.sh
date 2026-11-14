#!/bin/bash

# ============================================================================
# Shared helper functions used across multiple installer scripts.
# This file is sourced first (underscore prefix sorts before letters).
# ============================================================================

# Prompt the user to confirm a potentially destructive step.
# Returns 0 (yes) only on an explicit y/yes; defaults to No on Enter or anything else.
#
# Two cases answer without asking:
#   auto_confirm=true   -- the user has opted into unattended runs, so proceed.
#   no terminal         -- a piped or scripted run cannot answer, and the old
#                          behaviour (reading /dev/tty unconditionally) either
#                          failed the read and fell through to "No" by accident
#                          or blocked outright. Decline explicitly instead, so
#                          an unattended run never takes a destructive branch
#                          nobody approved.
_confirm_step() {
    local prompt="$1" reply=""

    if [[ "${CFG_AUTO_CONFIRM:-false}" == "true" ]]; then
        info "${prompt} [auto-confirmed]"
        return 0
    fi

    # Test that /dev/tty can actually be opened, not merely that it exists: a
    # detached session (setsid, cron, a systemd unit) still passes -r but errors
    # on open, which would leak a raw shell error before declining.
    if ! { : < /dev/tty; } 2>/dev/null; then
        warn "${prompt} -- declining, no terminal to ask on (set auto_confirm=true to proceed unattended)."
        return 1
    fi

    read -rp "${YELLOW:-}${prompt} [y/N]: ${RESET:-}" reply < /dev/tty
    [[ "${reply,,}" =~ ^(y|yes)$ ]]
}

# Gate a repair flow on whether a read-only check found problems.
# $1 = non-empty when issues were detected (caller reports the specifics).
#   Issues found -> return 0 (proceed with repair).
#   No issues    -> ask "Continue anyway?"; return 1 (caller should stop) unless the user opts in.
_repair_gate() {
    [[ -n "$1" ]] && return 0
    _confirm_step "No issues found. Continue anyway?" && return 0
    info "Nothing to do — exiting."
    return 1
}

# WSL 2 kernels carry a "-microsoft-standard-WSL2" release suffix. /proc/version
# is read rather than $WSL_DISTRO_NAME, which sudo strips from the environment.
# Usage: _is_wsl2 [version_file]   (defaults to /proc/version)
_is_wsl2() {
    grep -q 'WSL2' "${1:-/proc/version}" 2>/dev/null
}

# True only when the system has actually flagged that a reboot is required.
# Repair-style tasks (repo/package fixes) use this so the orchestrator's reboot
# prompt is offered only when a real restart is pending — e.g. a kernel pulled in
# by a dependency repair — rather than after every successful run.
_reboot_required() {
    # Debian/Ubuntu marker dropped by update-notifier-common.
    [[ -f /var/run/reboot-required ]] && return 0
    # RHEL/Fedora: needs-restarting -r exits non-zero when a reboot is pending.
    if command -v needs-restarting >/dev/null 2>&1; then
        needs-restarting -r >/dev/null 2>&1 || return 0
    fi
    # Arch family: no marker file and no needs-restarting, so neither check above
    # can ever fire -- the script reported "No reboot needed" while the desktop
    # was showing a reboot notification for the very same upgrade. Detect it the
    # way the OS itself does, from the live system.
    _reboot_required_arch && return 0
    return 1
}

# Arch has no /var/run/reboot-required and ships no needs-restarting, so a
# pending restart has to be read off the running system. Two independent signals,
# either one sufficient:
#
#   1. The running kernel's module tree is gone. pacman deletes
#      /usr/lib/modules/<release> when it upgrades the kernel package, so its
#      absence means the running kernel is no longer the installed one -- and
#      module loading for the running kernel is already broken.
#   2. Running processes still map files that have been replaced on disk. A
#      library upgraded underneath a running process keeps the old inode mapped
#      and shows in /proc/<pid>/maps as "(deleted)"; the new code is not in use
#      until that process restarts. This is what fires for an ordinary library
#      upgrade (openssl, curl, util-linux, mesa, wireplumber) where the kernel
#      never changed.
#
# Both read only /proc and the filesystem: no sudo, no package-manager call, so
# this is safe to run at the end of every batch. Only /usr paths count -- a
# process holding a deleted temp file or a browser's shm segment is not a system
# upgrade and must not trigger a reboot prompt.
_reboot_required_arch() {
    [[ "${DISTRO_FAMILY:-}" == "arch" ]] || return 1

    # 1. Running kernel replaced on disk.
    local _kver
    _kver="$(uname -r 2>/dev/null)"
    if [[ -n "$_kver" ]] && [[ -d /usr/lib/modules || -d /lib/modules ]]; then
        if [[ ! -d "/usr/lib/modules/${_kver}" && ! -d "/lib/modules/${_kver}" ]]; then
            return 0
        fi
    fi

    # 2. Stale system libraries or binaries still mapped by a running process.
    # Assigned, not piped into grep -q: the caller runs under `set -o pipefail`,
    # and grep -q exits on the first match, which SIGPIPEs the sort feeding it --
    # so the pipeline reported failure exactly when files WERE found, and the
    # check silently inverted itself inside the real script while passing in a
    # harness without pipefail.
    local _stale
    _stale="$(_reboot_stale_files)"
    [[ -n "$_stale" ]] && return 0

    return 1
}

# Print the distinct system files that have been replaced on disk but are still
# mapped by a running process, one per line (empty when there are none). Used for
# the detection above and to tell the user what actually needs the restart.
_reboot_stale_files() {
    # Most processes map nothing stale, so the inner grep fails for nearly every
    # maps file. Under the caller's `set -o pipefail` those failures would become
    # the pipeline's status, so the greps are contained in a subshell whose own
    # status is discarded and only the collected output is piped onward. Returns
    # 0 with output when stale files exist, 1 when there are none.
    local _out
    _out="$(
        for _maps in /proc/[0-9]*/maps; do
            # A maps line is: address perms offset dev inode path. Only
            # file-backed mappings under /usr count, and only those replaced.
            grep -hE '^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [0-9]+ +/usr/(lib|lib32|bin|sbin)/.*\(deleted\)$' \
                "$_maps" 2>/dev/null || true
        done | sed -E 's/^([^ ]+ ){5} *//; s/ \(deleted\)$//' | sort -u
    )"
    [[ -n "$_out" ]] || return 1
    printf '%s\n' "$_out"
}

# Final return for a repair task that completed: surface a reboot prompt only
# when one is genuinely pending, otherwise report "no changes" (exit 3) so the
# orchestrator skips the reboot prompt and offers to reload the menu instead.
_repair_done() {
    _reboot_required && return 0
    return 3
}

# Map the stale files above back to the packages that own them, comma-separated
# on one line, for the "Triggered by:" notice. A single upgrade can leave thirty
# stale paths (wireplumber alone contributes twenty modules), so listing files
# would bury the answer; the package names are what the user recognises. Falls
# back to nothing when the package manager cannot be queried -- the warning above
# still stands on its own.
_reboot_stale_packages() {
    local _files
    _files="$(_reboot_stale_files)"
    [[ -n "$_files" ]] || return 0

    case "${PKG_MGR:-}" in
        pacman) ;;
        *) return 0 ;;
    esac

    # A file that was REPLACED is often unowned under its old name: pacman knows
    # the package's current path, so a versioned soname bumped by the upgrade
    # (libgpgme.so.45.1.2 -> .46.0.0, libgallium-26.2.1 -> 26.2.2) resolves to
    # nothing. Ask about each path, and when that fails retry the unversioned
    # soname in the same directory, which the new package does own.
    local _f _owner _base _alt
    {
        while IFS= read -r _f; do
            [[ -n "$_f" ]] || continue
            if _owner="$(pacman -Qoq "$_f" 2>/dev/null)" && [[ -n "$_owner" ]]; then
                printf '%s\n' "$_owner"
                continue
            fi
            # libfoo.so.1.2.3 -> libfoo.so ; libfoo-1.2.3-arch1.so -> unchanged
            _base="${_f##*/}"
            _alt="${_f%/*}/${_base%%.so.*}.so"
            [[ "$_alt" != "$_f" && -e "$_alt" ]] || continue
            _owner="$(pacman -Qoq "$_alt" 2>/dev/null)" || continue
            [[ -n "$_owner" ]] && printf '%s\n' "$_owner"
        done <<< "$_files"
    } | sort -u | paste -sd, - | sed 's/,/, /g'
}

# Prompt for a desktop-environment install tier (Minimal / Standard / Full).
# $1 = DE display name, used in the prompt text only (e.g. "KDE Plasma").
# Echoes one of: minimal | standard | full  (capture with $(...)).
# All prompt output goes to stderr so it doesn't pollute the captured value.
# Defaults to "standard" on empty input, EOF, or when no terminal is attached.
_prompt_de_tier() {
    local de="$1" reply=""
    {
        printf '\n%sSelect a %s installation type:%s\n' "${BOLD:-}" "$de" "${RESET:-}"
        printf '  1) Minimal/Core   — base desktop only, fewest packages\n'
        printf '  2) Standard       — desktop plus common applications (Recommended)\n'
        printf '  3) Full Suite     — every default %s application\n\n' "$de"
        printf '%sEnter choice [1-3] (default 2): %s' "${YELLOW:-}" "${RESET:-}"
    } >&2
    # Prompt is emitted above (to stderr) rather than via `read -rp`, because the
    # 2>/dev/null needed to silence a missing-/dev/tty error would also hide read's
    # own prompt, leaving a blank line that looks like a hang.
    read -r reply < /dev/tty 2>/dev/null || reply=""
    case "$reply" in
        1) echo "minimal" ;;
        3) echo "full" ;;
        *) echo "standard" ;;
    esac
}

# Make a desktop's display manager start at boot and boot to the graphical target.
# $1 = display manager service name (sddm, gdm, lightdm).
# openSUSE starts its login screen through its own display-manager.service, which
# launches whatever the default-displaymanager alternative points at, so
# `systemctl enable <dm>` always fails there. The graphical target is set
# unconditionally: a minimal install defaults to multi-user.target, where no
# display manager starts.
_enable_desktop_login() {
    local dm="$1"
    info "Enabling display manager..."
    if [[ "$PKG_MGR" == "zypper" ]]; then
        run_as_root update-alternatives --set default-displaymanager "/usr/lib/X11/displaymanagers/${dm}" || \
            warn "Failed to set ${dm} as the default display manager"
    else
        run_as_root systemctl enable "$dm" || warn "Failed to enable ${dm}"
    fi
    run_as_root systemctl set-default graphical.target || warn "Failed to set graphical.target as default"
}

# Parse a multi-select string (e.g. "1,3-5") into deduplicated indices (input order preserved).
# Prints one index per line; returns 1 on invalid input.
_parse_multi_selection() {
    local input="$1" max="$2"
    local -a indices=()
    local part start end i

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part="${part// /}"
        [[ -z "$part" ]] && continue
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if (( start < 1 || end > max || start > end )); then
                return 1
            fi
            for (( i=start; i<=end; i++ )); do
                indices+=("$i")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            if (( part < 1 || part > max )); then
                return 1
            fi
            indices+=("$part")
        else
            return 1
        fi
    done

    (( ${#indices[@]} == 0 )) && return 1
    # Deduplicate while preserving the user's input order
    printf '%s\n' "${indices[@]}" | awk '!seen[$0]++'
}

# Install FUSE 2, which the runtime of a type-2 AppImage needs to mount itself.
# The package name differs by distro family. Shared by every installer that
# puts an AppImage on the system (Joplin, Xodus Nexus); do not add a copy.
ensure_appimage_fuse() {
    case "$DISTRO_FAMILY" in
        arch)
            if ! pkg_check_installed fuse2; then
                info "Installing fuse2 (required for AppImage support)..."
                pkg_install fuse2
            fi
            ;;
        debian)
            # Ubuntu 22.04 uses libfuse2; Ubuntu 24.04+ renamed it libfuse2t64
            local fuse2_pkg="libfuse2"
            if [[ "$DISTRO_ID" == "ubuntu" ]] && [[ "${DISTRO_VERSION_ID%%.*}" -ge 24 ]]; then
                fuse2_pkg="libfuse2t64"
            fi
            if ! pkg_check_installed "$fuse2_pkg"; then
                info "Installing ${fuse2_pkg} (required for AppImage support)..."
                pkg_install "$fuse2_pkg"
            fi
            ;;
        fedora|rhel)
            # `fuse` only ships the fusermount utilities and does NOT depend on
            # `fuse-libs`, which provides libfuse.so.2 — the AppImage runtime
            # needs both, so check and install each individually.
            local fuse_pkg
            for fuse_pkg in fuse fuse-libs; do
                if ! pkg_check_installed "$fuse_pkg"; then
                    info "Installing ${fuse_pkg} (required for AppImage support)..."
                    pkg_install "$fuse_pkg"
                fi
            done
            ;;
        suse)
            # Same split as Fedora: `fuse` has the utilities, `libfuse2` the library.
            local fuse_pkg
            for fuse_pkg in fuse libfuse2; do
                if ! pkg_check_installed "$fuse_pkg"; then
                    info "Installing ${fuse_pkg} (required for AppImage support)..."
                    pkg_install "$fuse_pkg"
                fi
            done
            ;;
    esac
}

# Enable the CRB repository on a RHEL clone (named powertools on EL 8). The crb
# helper ships with epel-release; config-manager is the fallback without it.
# Shared by KDE Plasma and ensure_rpmfusion; do not add a copy.
enable_crb() {
    run_as_root crb enable &>/dev/null || \
        run_as_root "$PKG_MGR" config-manager --set-enabled crb &>/dev/null || true
}

# Whether RPM Fusion's release package for the given section ($1: free or
# nonfree, default free) is installed.
rpmfusion_enabled() {
    rpm -q "rpmfusion-${1:-free}-release" &>/dev/null
}

# Enable RPM Fusion on Fedora or a RHEL clone, if it is not already enabled.
# $1 is free (the default) or nonfree; nonfree also enables free. On RHEL
# clones RPM Fusion depends on EPEL and the CRB repository, so both are enabled
# first. The release package is named by the major version (rpm -E), never the
# point release in os-release (9.8), which RPM Fusion does not publish (#86).
# Every installer that needs RPM Fusion calls this; do not add a copy.
ensure_rpmfusion() {
    local want="${1:-free}" os ver section
    local -a urls=()
    case "$DISTRO_FAMILY" in
        fedora) os=fedora; ver=$(rpm -E %fedora) ;;
        rhel)   os=el;     ver=$(rpm -E %rhel) ;;
        *)      error "RPM Fusion is only available on Fedora and RHEL-family systems."; return 1 ;;
    esac

    local -a sections=(free)
    [[ "$want" == "nonfree" ]] && sections+=(nonfree)
    for section in "${sections[@]}"; do
        rpmfusion_enabled "$section" || \
            urls+=("https://mirrors.rpmfusion.org/${section}/${os}/rpmfusion-${section}-release-${ver}.noarch.rpm")
    done
    (( ${#urls[@]} )) || return 0

    if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
        rpm -q epel-release &>/dev/null || pkg_install epel-release || {
            error "Failed to enable EPEL, which RPM Fusion needs on ${DISTRO_NAME}."
            return 1
        }
        enable_crb
    fi

    info "Enabling RPM Fusion (${sections[*]})..."
    pkg_install "${urls[@]}" || { error "Failed to enable RPM Fusion."; return 1; }
    run_as_root "$PKG_MGR" makecache &>/dev/null || true
}

# Debian 13 and Ubuntu 24.04+ renamed several libraries for the 64-bit time_t
# transition (libasound2 -> libasound2t64). apt picks the new name by itself
# for some of them but not for libasound2, which has two providers on Ubuntu.
_electron_debian_name() {
    if apt-cache show "${1}t64" &>/dev/null; then echo "${1}t64"; else echo "$1"; fi
}

# Runtime libraries for the Electron inside an AppImage (Xodus Nexus, LM Studio;
# do not add a copy). $1 is the app name used in messages. An AppImage is not
# a package, so nothing else pulls them in. Most are present on any desktop
# install; this matters on minimal ones. Taken from the libraries the bundled
# binary links (ldd), named per family the same way as NVIDIA PAIR's list.
ensure_electron_runtime_deps() {
    local app="$1"
    local -a deps=()
    case "$DISTRO_FAMILY" in
        debian)
            deps=("$(_electron_debian_name libgtk-3-0)" libnss3 libxtst6 libxss1
                  "$(_electron_debian_name libasound2)" libgbm1 libsecret-1-0 xdg-utils)
            ;;
        fedora|rhel)
            deps=(gtk3 nss libXScrnSaver libXtst xdg-utils libsecret mesa-libgbm alsa-lib)
            ;;
        suse)
            deps=(gtk3 mozilla-nss libXss1 libXtst6 xdg-utils libsecret-1-0 libgbm1 libasound2)
            ;;
        arch)
            deps=(gtk3 nss libxss libxtst xdg-utils libsecret mesa alsa-lib)
            ;;
    esac
    (( ${#deps[@]} == 0 )) && return 0

    local dep
    local -a missing=()
    for dep in "${deps[@]}"; do
        pkg_check_installed "$dep" || missing+=("$dep")
    done
    (( ${#missing[@]} == 0 )) && return 0

    # One transaction; if it fails a single wrong name is the likely cause, so
    # retry individually rather than lose the rest.
    if ! pkg_install "${missing[@]}"; then
        for dep in "${missing[@]}"; do
            pkg_check_installed "$dep" && continue
            pkg_install "$dep" || \
                verbose "${app}: runtime dependency '${dep}' unavailable; continuing."
        done
    fi
    return 0
}

# ============================================================================
# Native package, else Flathub
#
# Install source policy for apps that most distros package but some do not
# (Anki, Calibre on RHEL clones, Kodi on openSUSE, ...): the distro's own
# repository first, because it is signed by the distro and tracks the system;
# Flathub only where the repository has no such package. Used by mpv, Kodi,
# Blender, Darktable, RawTherapee, Shotcut, Scribus, Calibre, Anki, Okular,
# Xournal++ and KeePassXC. Older installers carry their own copy of this
# fallback inline; do not add another one, use these.
# ============================================================================

# Whether a package manager repository that is configured right now offers PKG.
# The query output is captured first and tested afterwards: piping it into
# grep -q would end the query early and, under pipefail, report "not found"
# for a package that is there (SIGPIPE, status 141).
pkg_in_repo() {
    local pkg="$1" out
    case "${PKG_MGR:-}" in
        apt)
            out=$(apt-cache policy "$pkg" 2>/dev/null)
            [[ "$out" == *"Candidate: "[!\(]* ]]
            ;;
        dnf|yum)
            out=$("$PKG_MGR" -q repoquery --latest-limit=1 --qf '%{name}\n' "$pkg" 2>/dev/null)
            grep -qx "$pkg" <<<"$out"
            ;;
        pacman)  arch_repo_has "$pkg" ;;
        zypper)
            out=$(zypper -q info "$pkg" 2>/dev/null)
            grep -q '^Version' <<<"$out"
            ;;
        apk)
            out=$(apk search -e "$pkg" 2>/dev/null)
            [[ -n "$out" ]]
            ;;
        *)       return 1 ;;
    esac
}

# RHEL clones carry much of this software in EPEL (which needs CRB). A no-op
# on every other family. Used by native_or_flatpak_install and the installers
# that take a package from EPEL.
ensure_epel() {
    [[ "${DISTRO_FAMILY:-}" == "rhel" ]] || return 0
    rpm -q epel-release &>/dev/null || pkg_install epel-release || true
    enable_crb
}

# Install a Flathub app system-wide, adding flatpak and the flathub remote first.
# sudo, not a bare flatpak: ensure_flatpak adds flathub as a SYSTEM remote (see
# the note in flatpak_or_aur in aur.sh).
flatpak_install_flathub() {
    local flatpak_id="$1"
    ensure_flatpak || { error "Flatpak is needed for ${flatpak_id} and could not be set up."; return 1; }
    sudo flatpak install -y flathub "$flatpak_id" || return 1
    flatpak_refresh_dbus
}

# native_or_flatpak_install FLATPAK_ID PKG
native_or_flatpak_install() {
    local flatpak_id="$1" pkg="$2"
    pkg_refresh
    ensure_epel
    if pkg_in_repo "$pkg"; then
        pkg_install "$pkg"
        return $?
    fi
    info "${pkg} is not in the ${DISTRO_NAME:-system} repositories; installing the Flatpak from Flathub."
    flatpak_install_flathub "$flatpak_id"
}

# User settings and data stay: these apps hold notes, vaults and libraries.
native_or_flatpak_uninstall() {
    local flatpak_id="$1" pkg="$2"
    if flatpak_is_installed "$flatpak_id"; then
        flatpak uninstall -y --user "$flatpak_id" 2>/dev/null || \
            sudo flatpak uninstall -y --system "$flatpak_id"
    else
        pkg_remove "$pkg"
    fi
}

native_or_flatpak_update() {
    local flatpak_id="$1" pkg="$2"
    if flatpak_is_installed "$flatpak_id"; then
        flatpak update -y --user "$flatpak_id" 2>/dev/null || \
            sudo flatpak update -y --system "$flatpak_id"
    else
        pkg_upgrade "$pkg"
    fi
}

# Version from the package manager or Flatpak. The program itself is never run:
# several of these are GUI apps that open a window for --version.
native_or_flatpak_version() {
    _ver_from_pkg "$2" || _ver_from_flatpak "$1" || echo ""
}

# ============================================================================
# Upstream GitHub release downloads, verified
#
# For apps no distro package covers on every release (lazygit, eza, helix,
# starship, zoxide, minikube, Ollama). GitHub publishes a SHA-256 digest for
# every release file next to its download URL in the release API; the download
# is checked against it and refused without one. Used by lazygit, eza, Helix,
# starship, zoxide, minikube and Ollama; do not add another copy of this.
# ============================================================================

declare -A _GH_RELEASE_JSON=()

# Release JSON for REPO, fetched once per run, flattened to one line.
_gh_release_json() {
    local repo="$1"
    if [[ -z "${_GH_RELEASE_JSON[$repo]:-}" ]]; then
        _GH_RELEASE_JSON["$repo"]=$(curl -fsSL --max-time 30 \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | tr -d '\n') || return 1
    fi
    # A rate-limit or error answer is JSON too, but has no release in it.
    if [[ "${_GH_RELEASE_JSON[$repo]}" != *'"tag_name"'* ]]; then
        unset "_GH_RELEASE_JSON[$repo]"
        return 1
    fi
}

# Latest release tag of REPO, e.g. v0.66.3.
github_latest_tag() {
    _gh_release_json "$1" || return 1
    grep -oP '"tag_name":\s*"\K[^"]+' <<<"${_GH_RELEASE_JSON[$1]}" | head -1
}

# github_asset_info REPO NAME_REGEX
# Prints "name url sha256" for the first release file whose name matches the
# extended regex (anchored at both ends), or nothing. A file with no published
# digest is never returned.
github_asset_info() {
    local repo="$1" re="$2" entry name url sha
    _gh_release_json "$repo" || return 1
    while IFS= read -r entry; do
        name=$(grep -oP '"name":\s*"\K[^"]+' <<<"$entry" | head -1)
        [[ "$name" =~ ^(${re})$ ]] || continue
        sha=$(grep -oP '"digest":\s*"sha256:\K[0-9a-f]{64}' <<<"$entry" | head -1)
        url=$(grep -oP '"browser_download_url":\s*"\K[^"]+' <<<"$entry" | head -1)
        [[ -n "$sha" && -n "$url" ]] || continue
        printf '%s %s %s\n' "$name" "$url" "$sha"
        return 0
    done < <(grep -oP '"name":\s*"[^"]+"(?:(?!"name":).)*?"digest":\s*"sha256:[0-9a-f]{64}"(?:(?!"name":).)*?"browser_download_url":\s*"[^"]+"' \
                 <<<"${_GH_RELEASE_JSON[$repo]}")
    return 1
}

# github_asset_download REPO NAME_REGEX DEST_DIR
# Downloads the matching release file into DEST_DIR, checks it against its
# published SHA-256 and prints its path. Returns 1 (with the reason) otherwise.
github_asset_download() {
    local repo="$1" re="$2" dest="$3" name url sha
    _gh_release_json "$repo" || {
        error "Could not read the latest ${repo} release from GitHub (offline, or its rate limit is used up; try again later)."
        return 1
    }
    read -r name url sha < <(github_asset_info "$repo" "$re")
    if [[ -z "$name" ]]; then
        error "No downloadable, checksummed file matching ${re} in the latest ${repo} release."
        return 1
    fi
    # stderr: the caller captures this function's stdout as the file path.
    info "Downloading ${name}..." >&2
    curl -fsSL --max-time 600 "$url" -o "${dest}/${name}" || { error "Could not download ${name}."; return 1; }
    verify_sha256 "${dest}/${name}" "$sha" "$name" || return 1
    printf '%s\n' "${dest}/${name}"
}

# Architecture names upstream release files use. Prints nothing and returns 1
# on a CPU this tool has no builds for.
#   upstream_arch gnu -> x86_64 | aarch64   (Rust target triples)
#   upstream_arch go  -> amd64  | arm64     (Go style)
upstream_arch() {
    case "$(uname -m)-$1" in
        x86_64-gnu)  echo x86_64 ;;
        aarch64-gnu) echo aarch64 ;;
        x86_64-go)   echo amd64 ;;
        aarch64-go)  echo arm64 ;;
        *) error "No upstream build for the $(uname -m) CPU."; return 1 ;;
    esac
}

# ============================================================================
# Shell profile blocks (starship, zoxide, fzf)
#
# These tools do nothing until the shell is told to load them. The block is
# written between two marker lines so it is added once and removed exactly.
# ============================================================================

# shell_rc_block_add RCFILE BEGIN END   (block body on stdin)
shell_rc_block_add() {
    local rcfile="$1" begin="$2" end="$3" body
    body=$(cat)
    grep -qF "$begin" "$rcfile" 2>/dev/null && return 0
    { printf '\n%s\n' "$begin"; printf '%s\n' "$body"; printf '%s\n' "$end"; } >> "$rcfile"
    info "Added a block to ${rcfile}"
}

# shell_rc_block_remove RCFILE BEGIN END
# Exact string matching (awk), avoiding regex-escaping issues with sed.
shell_rc_block_remove() {
    local rcfile="$1" begin="$2" end="$3"
    [[ -f "$rcfile" ]] || return 0
    grep -qF "$begin" "$rcfile" 2>/dev/null || return 0
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { skip=1 }
        skip { if ($0 == end) { skip=0 } next }
        { print }
    ' "$rcfile" > "${rcfile}.tmp" && mv "${rcfile}.tmp" "$rcfile"
    info "Removed a block from ${rcfile}"
}

# shell_init_setup NAME BASH_LINE ZSH_LINE: add NAME's block to ~/.bashrc, and to
# ~/.zshrc when that file exists (zsh may not be set up yet).
shell_init_setup() {
    local name="$1" bash_line="$2" zsh_line="$3"
    shell_rc_block_add "$HOME/.bashrc" "# >>> linux_util ${name} (bash) >>>" "# <<< linux_util ${name} (bash) <<<" <<<"$bash_line"
    [[ -f "$HOME/.zshrc" ]] && shell_rc_block_add "$HOME/.zshrc" "# >>> linux_util ${name} (zsh) >>>" "# <<< linux_util ${name} (zsh) <<<" <<<"$zsh_line"
    return 0
}

shell_init_remove() {
    local name="$1"
    shell_rc_block_remove "$HOME/.bashrc" "# >>> linux_util ${name} (bash) >>>" "# <<< linux_util ${name} (bash) <<<"
    shell_rc_block_remove "$HOME/.zshrc" "# >>> linux_util ${name} (zsh) >>>" "# <<< linux_util ${name} (zsh) <<<"
}

# ============================================================================
# Distro package, else a verified upstream binary
#
# For single-binary tools (lazygit, eza, zoxide, starship, minikube) that most
# distros package but some releases do not: the distro's own package when its
# repositories have one, otherwise the GitHub release file, checked against its
# published SHA-256 and installed to /usr/local/bin. The package manager never
# sees the copy, so uninstall and update follow whichever route is on the
# machine: the /usr/local/bin file counts as the upstream route only while no
# package is installed.
# ============================================================================

# Fill @GNU@ (x86_64|aarch64), @GO@ (amd64|arm64) and @GOX@ (x86_64|arm64) in an
# asset-name regex with this machine's names.
_upstream_expand_regex() {
    local re="$1" gnu go gox
    gnu=$(upstream_arch gnu) || return 1
    go=$(upstream_arch go) || return 1
    gox=$gnu; [[ "$gnu" == aarch64 ]] && gox=arm64
    re="${re//@GNU@/$gnu}"; re="${re//@GO@/$go}"; re="${re//@GOX@/$gox}"
    printf '%s\n' "$re"
}

# github_binary_install REPO ASSET_REGEX BINARY_NAME [DEST_NAME]
# Downloads the matching release file (a .tar.gz holding BINARY_NAME, or the
# bare binary itself), verifies it and installs it as /usr/local/bin/DEST_NAME.
github_binary_install() {
    local repo="$1" re="$2" bin="$3" dest="${4:-$3}" tmp file found
    re=$(_upstream_expand_regex "$re") || return 1
    tmp=$(mktemp -d) || return 1
    CLEANUP_FILES+=("$tmp")
    file=$(github_asset_download "$repo" "$re" "$tmp") || { rm -rf "$tmp"; return 1; }
    if [[ "$file" == *.tar.gz || "$file" == *.tgz ]]; then
        tar -xzf "$file" -C "$tmp" || { error "Could not unpack $(basename "$file")."; rm -rf "$tmp"; return 1; }
        found=$(find "$tmp" -type f -name "$bin" | head -1)
    else
        found="$file"
    fi
    if [[ -z "$found" ]]; then
        error "${bin} was not in the downloaded file."
        rm -rf "$tmp"
        return 1
    fi
    sudo install -Dm755 "$found" "/usr/local/bin/${dest}" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
}

# True when /usr/local/bin/DEST is a copy this route installed (no package owns it).
upstream_binary_present() {
    local dest="$1" pkg="$2"
    [[ -x "/usr/local/bin/${dest}" ]] && ! pkg_check_installed "$pkg"
}

# native_or_github_install PKG REPO ASSET_REGEX BINARY [DEST_NAME]
native_or_github_install() {
    local pkg="$1"
    pkg_refresh
    ensure_epel
    if pkg_in_repo "$pkg"; then
        pkg_install "$pkg"
        return $?
    fi
    info "${pkg} is not in the ${DISTRO_NAME:-system} repositories; installing the verified release from GitHub."
    github_binary_install "${@:2}"
}

# native_or_github_uninstall PKG DEST_NAME
native_or_github_uninstall() {
    local pkg="$1" dest="$2"
    if pkg_check_installed "$pkg"; then
        pkg_remove "$pkg"
    fi
    sudo rm -f "/usr/local/bin/${dest}"
}

# native_or_github_update PKG REPO ASSET_REGEX BINARY DEST_NAME INSTALLED_VERSION
# Reinstalls the release only when it is newer than INSTALLED_VERSION.
native_or_github_update() {
    local pkg="$1" repo="$2" re="$3" bin="$4" dest="$5" cur="$6" tag
    if ! upstream_binary_present "$dest" "$pkg"; then
        pkg_upgrade "$pkg"
        return $?
    fi
    tag=$(github_latest_tag "$repo") || { error "Could not read the latest ${repo} release from GitHub."; return 1; }
    if [[ -n "$cur" && "${tag#v}" == "$cur" ]]; then
        info "${dest} is already at the latest version (${cur})."
        return 0
    fi
    github_binary_install "$repo" "$re" "$bin" "$dest"
}

# rpm_import_key_checked URL FINGERPRINT
# Imports a vendor's RPM signing key only when the downloaded key carries the
# pinned fingerprint. Used by Sublime Text and VirtualBox.
rpm_import_key_checked() {
    local url="$1" fpr="$2" tmp
    ensure_tools
    tmp=$(mktemp) || return 1
    if ! curl -fsSL --max-time 30 "$url" -o "$tmp"; then
        rm -f "$tmp"; error "Could not download the signing key from ${url}."; return 1
    fi
    if ! gpg_key_has_fingerprint "$tmp" "$fpr"; then
        rm -f "$tmp"; error "The key from ${url} does not match fingerprint ${fpr}."; return 1
    fi
    sudo rpm --import "$tmp"
    local rc=$?
    rm -f "$tmp"
    return "$rc"
}
