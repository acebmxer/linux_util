#!/bin/bash
# linux-tkg — Frogging-Family custom-kernel builder.
#
# Unlike the other kernel managers (which fetch prebuilt kernels), linux-tkg
# BUILDS a customised kernel FROM SOURCE: you pick the CPU scheduler (BORE,
# EEVDF, PDS, …), compiler, and config, and it compiles and installs the result.
# Cross-distro:
#   Arch & derivatives       → makepkg -si       (base-devel auto-resolves the rest)
#   Debian/Ubuntu, Fedora,   → ./install.sh install (produces a .deb/.rpm, installs it)
#   openSUSE, generic
#
# The build is interactive and can take 20–60+ minutes. Kernels carry "tkg" in
# their name; uninstalling a built kernel is manual (./install.sh uninstall-help).

# --- linux-tkg ---

LINUX_TKG_REPO="https://github.com/Frogging-Family/linux-tkg.git"
LINUX_TKG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/linux_util/linux-tkg"

# Installed if we're booted into a tkg kernel, or a tkg kernel package is present.
check_linux_tkg() {
    uname -r 2>/dev/null | grep -qi 'tkg' && return 0
    case "$PKG_MGR" in
        pacman)         pacman -Qq 2>/dev/null         | grep -qiE 'linux.*tkg'       && return 0 ;;
        apt)            dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -qi 'linux-image.*tkg' && return 0 ;;
        dnf|yum|zypper) rpm -qa 2>/dev/null             | grep -qi 'kernel.*tkg'       && return 0 ;;
    esac
    return 1
}

# Report the running tkg release when booted into one (best-effort).
get_version_linux_tkg() {
    local r
    r="$(uname -r 2>/dev/null)"
    [[ "$r" == *tkg* ]] && printf '%s\n' "$r"
}

# Install the build toolchain. On Arch, makepkg -s pulls the PKGBUILD makedepends
# itself, so only base-devel + git are needed. On other distros upstream leaves
# dependency installation to the user, so install a solid core set best-effort
# (linux-tkg may still prompt for extras).
_linux_tkg_install_build_deps() {
    case "$DISTRO_FAMILY" in
        arch)
            pkg_install base-devel git
            ;;
        debian)
            pkg_install build-essential git bc bison flex libssl-dev libelf-dev \
                libncurses-dev rsync cpio kmod zstd lz4 ccache fakeroot wget
            ;;
        fedora|rhel)
            run_as_root "$PKG_MGR" -y group install "Development Tools" 2>/dev/null \
                || run_as_root "$PKG_MGR" -y groupinstall "Development Tools" 2>/dev/null || true
            pkg_install git wget bc bison flex openssl-devel elfutils-libelf-devel \
                ncurses-devel rsync cpio kmod zstd lz4 ccache fakeroot dwarves rpm-build grubby
            ;;
        suse)
            run_as_root zypper -n install -t pattern devel_basis 2>/dev/null || true
            pkg_install git wget bc bison flex libopenssl-devel libelf-devel \
                ncurses-devel rsync cpio kmod zstd lz4 ccache fakeroot dwarves rpm-build
            ;;
        *)
            return 1
            ;;
    esac
}

# Clone the linux-tkg scripts (or fast-forward an existing checkout) into a
# stable cache dir so rebuilds and uninstall-help keep working.
_linux_tkg_sync_repo() {
    if [[ -d "$LINUX_TKG_DIR/.git" ]]; then
        info "Updating the existing linux-tkg checkout in ${LINUX_TKG_DIR}..."
        git -C "$LINUX_TKG_DIR" pull --ff-only 2>/dev/null && return 0
        warn "Could not fast-forward the existing checkout — re-cloning."
        rm -rf "$LINUX_TKG_DIR"
    fi
    mkdir -p "$(dirname "$LINUX_TKG_DIR")"
    info "Cloning linux-tkg into ${LINUX_TKG_DIR}..."
    git clone "$LINUX_TKG_REPO" "$LINUX_TKG_DIR" \
        || { error "Failed to clone linux-tkg from ${LINUX_TKG_REPO}."; return 1; }
}

install_linux_tkg() {
    info "Installing linux-tkg — a custom kernel BUILT FROM SOURCE."
    warn "This is interactive (you choose scheduler, config, etc.) and the compile can take 20-60+ minutes."

    case "$DISTRO_FAMILY" in
        arch|debian|fedora|rhel|suse) : ;;
        *) error "linux-tkg builds are not supported on this distribution (${DISTRO_ID})."; return 1 ;;
    esac

    if [[ "$EUID" -eq 0 ]]; then
        error "Do not run linux-tkg as root — makepkg/install.sh must build as a normal user."
        return 1
    fi

    _linux_tkg_install_build_deps || { error "Failed to install build dependencies for linux-tkg."; return 1; }
    _linux_tkg_sync_repo || return 1

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        info "Building with 'makepkg -si' (linux-tkg will prompt for options, then sudo for install)..."
        ( cd "$LINUX_TKG_DIR" && makepkg -si ) \
            || { error "linux-tkg build/install failed."; return 1; }
    else
        info "Building with './install.sh install' (creates a .deb/.rpm and installs it)..."
        ( cd "$LINUX_TKG_DIR" && ./install.sh install ) \
            || { error "linux-tkg build/install failed."; return 1; }
    fi

    info "linux-tkg installed. Reboot and select the -tkg kernel from your boot menu."
    info "To rebuild later or tweak options, edit customization.cfg in ${LINUX_TKG_DIR} and re-run this task."
}

uninstall_linux_tkg() {
    info "Uninstalling linux-tkg..."
    warn "Removing a built tkg kernel is manual — this prints upstream guidance and clears the build checkout,"
    warn "but it does NOT remove an already-installed tkg kernel."
    if [[ -d "$LINUX_TKG_DIR" ]]; then
        ( cd "$LINUX_TKG_DIR" && ./install.sh uninstall-help ) 2>/dev/null || true
    fi
    info "Remove the kernel with your package manager (its package carries 'tkg' in the name), after booting a stock kernel."
    rm -rf "$LINUX_TKG_DIR"
}

update_linux_tkg() {
    info "Updating linux-tkg (re-syncs the build scripts and rebuilds the latest)..."
    install_linux_tkg
}
