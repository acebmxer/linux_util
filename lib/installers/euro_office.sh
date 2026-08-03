#!/bin/bash
# Euro-Office Desktop Editors — a community fork of ONLYOFFICE, BUILT FROM SOURCE.
#
# Upstream publishes no desktop binaries: the DesktopEditors repository carries
# tags but no releases, nothing is on Flathub/Snap/AppImage, there is no apt or
# rpm repository, and the ghcr.io images for the desktop build are private (only
# the Document Server — the server component — ships packages). The only
# supported way to obtain the desktop client is upstream's own containerised
# build, 'build/linux/build.sh', which drives 'docker buildx bake' and emits a
# .deb, an .rpm and a .tar.xz into build/linux/deploy/packages.
#
# So this task compiles the suite. Docker with the Buildx plugin is a hard
# prerequisite, the build takes hours, and it needs tens of GB of disk between
# the source tree, the container layers and the build cache. Everything here is
# gated behind an explicit confirmation for that reason.
#
# Arch goes through the AUR package instead: its PKGBUILD runs this same Docker
# build under makepkg, and pacman ends up tracking the result — better than
# unpacking upstream's tarball over /usr and /opt untracked.
#
# When upstream starts publishing releases (their CI is already wired to upload
# these packages to a GitHub Release), this file collapses to a plain download.

# --- Euro-Office ---

_EUROOFFICE_REPO="https://github.com/Euro-Office/DesktopEditors.git"
_EUROOFFICE_SRC="${XDG_CACHE_HOME:-$HOME/.cache}/linux_util/euro-office"
_EUROOFFICE_PKG="euro-office-desktopeditors"
_EUROOFFICE_AUR_PKG="euro-office-desktopeditors-git"
# Our own buildx builder, so removing it on uninstall cannot take anyone else's
# build cache with it.
_EUROOFFICE_BUILDER="linux-util-euro-office"
# Where upstream's bake file exports its local cache. Fixed in their HCL, so it
# is not something TMPDIR can move.
_EUROOFFICE_BAKE_CACHE="/tmp/ghcr.io/euro-office"
# A floor, not a measurement: the checkout with submodules, the container
# layers, vcpkg's dependencies and the compiler cache all land on disk.
_EUROOFFICE_MIN_GB=40

check_euro_office() { _check_standard "$_EUROOFFICE_PKG" "$_EUROOFFICE_PKG" ""; }

get_version_euro_office() {
    _ver_from_pkg "$_EUROOFFICE_PKG" && return 0
    # The AUR build is a -git package and provides= the real name, which pacman
    # will not answer version queries for.
    [[ "$DISTRO_FAMILY" == "arch" ]] && _ver_from_pkg "$_EUROOFFICE_AUR_PKG" && return 0
    return 1
}

# Can we actually ask the user something? Open /dev/tty rather than testing the
# device node — it exists and looks readable in a session with no controlling
# terminal, where opening it fails.
_euroffice_have_tty() {
    { : < /dev/tty; } 2>/dev/null
}

# Everything the build needs from Docker, checked before anything is downloaded.
_euroffice_require_docker() {
    if ! command -v docker &>/dev/null; then
        error "Euro-Office is built in containers and Docker is not installed."
        error "Install Docker from the Development tab first, then re-run this task."
        return 1
    fi
    if ! docker buildx version &>/dev/null; then
        error "The Docker Buildx plugin is missing — upstream's build is a 'docker buildx bake'."
        error "Install it ('docker-buildx-plugin' on Debian/Ubuntu and Fedora, 'docker-buildx' on Arch)."
        return 1
    fi
    if ! docker info &>/dev/null; then
        error "Cannot talk to the Docker daemon."
        error "Start it with 'sudo systemctl enable --now docker', and add yourself to the docker group"
        error "with 'sudo usermod -aG docker \"\$USER\"' — then log out and back in."
        return 1
    fi
    return 0
}

# The packaging Makefile maps only x86_64 and aarch64 to a package architecture;
# anything else builds into a package that is named wrong and installs nowhere.
_euroffice_require_arch() {
    case "$(uname -m)" in
        x86_64|aarch64|arm64) return 0 ;;
    esac
    error "Euro-Office builds for x86_64 and aarch64 only — this machine is $(uname -m)."
    return 1
}

# Free space in whole GB on the filesystem holding a path, walking up to the
# nearest directory that exists (the source dir has not been created yet).
_euroffice_free_gb() {
    local _path="$1"
    while [[ -n "$_path" && "$_path" != "/" && ! -d "$_path" ]]; do
        _path=$(dirname "$_path")
    done
    df -PBG "$_path" 2>/dev/null | awk 'NR==2 { gsub(/[^0-9]/, "", $4); print $4 }'
}

# Report anywhere the build is likely to run out of room. Advisory only — the
# user decides at the confirmation prompt, with these warnings already printed.
_euroffice_report_space() {
    local _where _free _docker_root
    _docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)

    for _where in "$_EUROOFFICE_SRC" "${_docker_root:-/var/lib/docker}" /tmp; do
        _free=$(_euroffice_free_gb "$_where")
        [[ -n "$_free" ]] || continue
        (( _free < _EUROOFFICE_MIN_GB )) && \
            warn "Only ${_free} GB free on the filesystem holding $_where — the build wants ${_EUROOFFICE_MIN_GB} GB or more."
    done

    # Fedora and friends mount /tmp as tmpfs, so the several GB of build cache
    # upstream's bake file exports there is charged to RAM, not disk.
    if [[ "$(stat -f -c %T /tmp 2>/dev/null)" == "tmpfs" ]]; then
        warn "/tmp is a tmpfs (RAM-backed) and the build exports its cache to $_EUROOFFICE_BAKE_CACHE."
        warn "On a machine with little RAM, that cache can fill /tmp and fail the build."
    fi
    return 0
}

# Nobody should wait hours for a compile they did not ask for. EUROOFFICE_BUILD
# decides in advance for scripted runs, profile imports and cron.
_euroffice_confirm_build() {
    local _what="$1" _ans=""

    case "${EUROOFFICE_BUILD:-}" in
        1|y|yes|true)  return 0 ;;
        0|n|no|false)  info "EUROOFFICE_BUILD is set to no — skipping the Euro-Office build."; return 1 ;;
    esac

    if ! _euroffice_have_tty; then
        error "Euro-Office has to be compiled from source — upstream ships no binaries — and there is"
        error "no terminal here to confirm an hours-long build. Set EUROOFFICE_BUILD=yes to allow it."
        return 1
    fi

    echo ""
    info "Euro-Office publishes no prebuilt desktop packages, so this builds $_what."
    info "Expect an hours-long compile and tens of GB of disk use. It runs in containers,"
    info "so nothing but Docker is installed on the host to make it happen."

    read -rp "Start the build now? [y/N]: " _ans < /dev/tty
    [[ "${_ans,,}" == y* ]] && return 0

    info "Skipping the Euro-Office build. Re-run this task when you have time to spare."
    return 1
}

# Clone the superrepo, or fetch into the existing checkout. Submodules are left
# alone here: which ones matter depends on the ref we are about to check out.
_euroffice_clone_or_fetch() {
    if [[ -d "$_EUROOFFICE_SRC/.git" ]]; then
        info "Fetching Euro-Office sources in $_EUROOFFICE_SRC..."
        git -C "$_EUROOFFICE_SRC" fetch --tags --prune origin && return 0
        error "Could not fetch into the existing checkout at $_EUROOFFICE_SRC."
        error "Delete that directory to start from a clean clone, then re-run this task."
        return 1
    fi

    mkdir -p "$(dirname "$_EUROOFFICE_SRC")"
    info "Cloning Euro-Office into $_EUROOFFICE_SRC (this is a large repository)..."
    git clone "$_EUROOFFICE_REPO" "$_EUROOFFICE_SRC" || {
        error "Failed to clone $_EUROOFFICE_REPO."
        return 1
    }
}

# Newest stable tag from a list of refs on stdin. Kept separate from git so the
# selection is testable: upstream tags pre-releases (v9.3.1-rc.1, -beta.1, -tp.3)
# alongside real ones, and only the plain vX.Y.Z form should ever be built.
_euroffice_pick_tag() {
    grep -E '^v[0-9]+(\.[0-9]+)*$' | sort -V -r | head -1
}

# What to build: the newest release tag, so an install is a release build rather
# than whatever main happened to be at the time. EUROOFFICE_REF overrides it
# (a tag, a branch such as 'main', or a commit).
_euroffice_target_ref() {
    if [[ -n "${EUROOFFICE_REF:-}" ]]; then
        printf '%s\n' "$EUROOFFICE_REF"
        return 0
    fi
    local _tag
    _tag=$(git -C "$_EUROOFFICE_SRC" tag --list 'v[0-9]*' 2>/dev/null | _euroffice_pick_tag)
    printf '%s\n' "${_tag:-main}"
}

# Check out a ref and sync the submodules to it. Almost none of the source lives
# in the superrepo — without this the build has nothing to compile.
_euroffice_checkout() {
    local _ref="$1"
    info "Checking out $_ref..."
    # The remote-tracking ref is tried first so that EUROOFFICE_REF=main builds
    # the tip that was just fetched. Checking out the local branch instead would
    # quietly rebuild whatever it pointed at last time, since nothing here ever
    # fast-forwards it. Tags have no origin/ form, so they fall through.
    git -C "$_EUROOFFICE_SRC" checkout --quiet "origin/$_ref" 2>/dev/null || \
    git -C "$_EUROOFFICE_SRC" checkout --quiet "$_ref" 2>/dev/null || {
        error "Could not check out '$_ref' in $_EUROOFFICE_SRC."
        return 1
    }
    info "Syncing submodules (core, sdkjs, web-apps and the rest — several GB on a first run)..."
    git -C "$_EUROOFFICE_SRC" submodule update --init --recursive || {
        error "Failed to check out the submodules; the build would have nothing to compile."
        return 1
    }
}

# The bake file exports the finished packages to a local directory and reuses a
# local cache, neither of which the default 'docker' driver can do. Upstream's
# own AUR packaging creates a container builder for the same reason.
_euroffice_ensure_builder() {
    docker buildx inspect "$_EUROOFFICE_BUILDER" &>/dev/null && return 0
    info "Creating the '$_EUROOFFICE_BUILDER' buildx builder (docker-container driver)..."
    docker buildx create --name "$_EUROOFFICE_BUILDER" --driver docker-container >/dev/null || {
        error "Could not create a buildx builder — the packages cannot be exported without one."
        return 1
    }
}

_euroffice_out_dir() { printf '%s\n' "$_EUROOFFICE_SRC/build/linux/deploy/packages"; }

# Run upstream's build script from the directory it expects. Output is streamed
# rather than hidden behind a spinner: this runs for hours, and the compile log
# is the only sign it is still alive.
_euroffice_build() {
    local _ref="$1"

    # Start from an empty output directory so a stale package from an earlier
    # build can never be the one that gets installed.
    rm -rf "$(_euroffice_out_dir)"

    info "Building Euro-Office $_ref — go and do something else, this takes hours."
    (
        cd "$_EUROOFFICE_SRC/build/linux" || exit 1
        # The bake writes outside its context (the exported packages and the
        # cache under /tmp). Without this, buildx stops to ask for confirmation
        # and an unattended run hangs there.
        BUILDX_BAKE_ENTITLEMENTS_FS=0 BUILDX_BUILDER="$_EUROOFFICE_BUILDER" ./build.sh
    ) || {
        error "The Euro-Office build failed. The checkout and the build cache are kept at"
        error "$_EUROOFFICE_SRC, so re-running this task resumes rather than starting over."
        return 1
    }
}

# Pick the package this distribution can install out of the build output. The
# build emits a .deb, an .rpm and a .tar.xz side by side, for the host
# architecture only.
_euroffice_artifact() {
    local _dir="$1" _pattern="" _file=""
    case "$DISTRO_FAMILY" in
        debian)           _pattern='*.deb' ;;
        fedora|rhel|suse) _pattern='*.rpm' ;;
        *)                return 1 ;;
    esac
    _file=$(find "$_dir" -maxdepth 1 -type f -name "$_pattern" -printf '%T@\t%p\n' 2>/dev/null |
            sort -rn | head -1 | cut -f2-)
    [[ -n "$_file" ]] || return 1
    printf '%s\n' "$_file"
}

# Build, then install what came out. Shared by install and update.
_euroffice_build_and_install() {
    local _ref="$1" _artifact=""

    _euroffice_ensure_builder || return 1
    _euroffice_build "$_ref" || return 1

    _artifact=$(_euroffice_artifact "$(_euroffice_out_dir)") || {
        error "The build finished but produced no installable package in $(_euroffice_out_dir)."
        return 1
    }

    # openSUSE has its own packaging target upstream that the container build
    # does not produce; the generic rpm installs, but it is not their SUSE build.
    [[ "$DISTRO_FAMILY" == "suse" ]] && \
        warn "Installing the generic rpm — upstream's openSUSE-specific package is not built by this route."

    pkg_install_local "$_artifact" || {
        error "Failed to install $(basename "$_artifact")."
        return 1
    }
    info "Installed $(basename "$_artifact")."
}

# Arch has a packaged path to the same build, so use it: the AUR PKGBUILD runs
# upstream's Docker build under makepkg and hands pacman a real package, which
# means a real uninstall later.
_euroffice_install_arch() {
    _euroffice_require_docker || return 1
    _euroffice_confirm_build "the AUR package '$_EUROOFFICE_AUR_PKG', which runs the same containerised build" || return 1
    _euroffice_report_space
    aur_ensure "$_EUROOFFICE_AUR_PKG" || {
        error "Failed to build $_EUROOFFICE_AUR_PKG from the AUR."
        return 1
    }
}

install_euro_office() {
    info "Installing Euro-Office Desktop Editors (compiled from source)..."

    case "$DISTRO_FAMILY" in
        arch)
            _euroffice_require_arch || return 1
            _euroffice_install_arch || return 1
            info "Euro-Office installed. Launch it from your application menu or run '$_EUROOFFICE_PKG'."
            return 0
            ;;
        debian|fedora|rhel|suse) : ;;
        *)
            error "Euro-Office builds are not supported on this distribution (${DISTRO_ID})."
            return 1
            ;;
    esac

    _euroffice_require_arch   || return 1
    _euroffice_require_docker || return 1

    command -v git &>/dev/null || pkg_install git || {
        error "git is required to fetch the Euro-Office sources."
        return 1
    }
    check_internet

    # Confirm before the clone, not just before the compile — the checkout with
    # its submodules is itself several GB.
    _euroffice_report_space
    _euroffice_confirm_build "Euro-Office Desktop Editors from source" || return 1

    _euroffice_clone_or_fetch || return 1

    local _ref
    _ref=$(_euroffice_target_ref)
    _euroffice_checkout "$_ref" || return 1
    _euroffice_build_and_install "$_ref" || return 1

    info "Euro-Office installed. Launch it from your application menu or run '$_EUROOFFICE_PKG'."
    info "The sources and build cache are kept in $_EUROOFFICE_SRC so later updates rebuild incrementally."
}

update_euro_office() {
    info "Updating Euro-Office Desktop Editors..."

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        _euroffice_require_docker || return 1
        _euroffice_confirm_build "the newest $_EUROOFFICE_AUR_PKG from the AUR" || return 1
        aur_ensure "$_EUROOFFICE_AUR_PKG" || {
            error "Failed to rebuild $_EUROOFFICE_AUR_PKG from the AUR."
            return 1
        }
        return 0
    fi

    if [[ ! -d "$_EUROOFFICE_SRC/.git" ]]; then
        warn "No Euro-Office checkout in $_EUROOFFICE_SRC — nothing to update."
        warn "Run the install task instead; updating means rebuilding from source."
        return 0
    fi

    _euroffice_require_docker || return 1
    _euroffice_clone_or_fetch || return 1

    local _ref _installed
    _ref=$(_euroffice_target_ref)
    _installed=$(get_version_euro_office)

    # Rebuilding takes hours, so never do it just because the task was selected.
    if [[ -n "$_installed" && "v${_installed}" == "$_ref" ]]; then
        info "Euro-Office $_installed is already the newest release ($_ref) — nothing to rebuild."
        return 0
    fi

    [[ -n "$_installed" ]] && info "Installed: $_installed. Newest release: $_ref."
    _euroffice_report_space
    _euroffice_confirm_build "Euro-Office $_ref from source" || return 1

    _euroffice_checkout "$_ref" || return 1
    _euroffice_build_and_install "$_ref" || return 1

    info "Euro-Office updated to $_ref."
}

uninstall_euro_office() {
    info "Uninstalling Euro-Office Desktop Editors..."

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        if pkg_check_installed "$_EUROOFFICE_AUR_PKG"; then
            aur_remove "$_EUROOFFICE_AUR_PKG" 2>/dev/null || pkg_remove "$_EUROOFFICE_AUR_PKG" 2>/dev/null || true
        else
            pkg_remove "$_EUROOFFICE_PKG" 2>/dev/null || true
        fi
    else
        pkg_check_installed "$_EUROOFFICE_PKG" && { pkg_remove "$_EUROOFFICE_PKG" || true; }
    fi

    # The checkout is ours and rebuildable, but it is many GB — leaving it behind
    # after an uninstall would be its own surprise.
    if [[ -d "$_EUROOFFICE_SRC" ]]; then
        rm -rf "$_EUROOFFICE_SRC"
        info "Removed the source checkout and build cache at $_EUROOFFICE_SRC."
    fi
    [[ -d "$_EUROOFFICE_BAKE_CACHE" ]] && rm -rf "$_EUROOFFICE_BAKE_CACHE"

    # Only ever created by this task, and it holds the bulk of the build cache.
    if command -v docker &>/dev/null && docker buildx inspect "$_EUROOFFICE_BUILDER" &>/dev/null; then
        docker buildx rm "$_EUROOFFICE_BUILDER" &>/dev/null && \
            info "Removed the '$_EUROOFFICE_BUILDER' buildx builder and its cache volume."
    fi

    # Application settings, under the Qt organisation name upstream brands with.
    rm -rf "$HOME/.config/Euro-Office" "$HOME/.local/share/Euro-Office"

    # The intermediate images are several GB but are shared with nothing else, so
    # name them rather than deciding for the user.
    if command -v docker &>/dev/null && \
       docker image ls --format '{{.Repository}}' 2>/dev/null | grep -q '^ghcr\.io/euro-office/'; then
        warn "The Euro-Office build images are still in Docker. Remove them with:"
        warn "  docker image ls --filter reference='ghcr.io/euro-office/*' -q | xargs -r docker image rm"
    fi

    echo "Euro-Office Desktop Editors has been uninstalled."
}
