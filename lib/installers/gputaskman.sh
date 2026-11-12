#!/bin/bash
# GPU Task Manager (gputaskman) installer functions
# https://github.com/shanselman/gputaskman
#
# A terminal UI that shows per-process GPU memory and engine load, and which
# runtimes and model files (llama.cpp, Ollama, PyTorch...) are using the GPU.
# NVIDIA through NVML (comes with the driver), AMD on amdgpu and Intel on i915
# through the kernel's own sysfs and DRM fdinfo; no extra package is needed.
#
# Upstream's portable Linux build (x64 and arm64, a PyInstaller bundle with
# its own Python) is installed per user, the same on every distro:
#
#   ~/.local/opt/gputaskman/gputaskman             the program (_internal beside it)
#   ~/.local/opt/gputaskman/.linux_util-version    version that was unpacked
#   ~/.local/bin/gputaskman                        symlink to it
#
# The bundle has no --version flag and does not update itself, so the version
# written at install time stays true. It needs glibc 2.35 or newer.

# --- GPU Task Manager ---

_GTM_REPO="shanselman/gputaskman"
_GTM_DIR="$HOME/.local/opt/gputaskman"
_GTM_EXE="$_GTM_DIR/gputaskman"
_GTM_VERSION_FILE="$_GTM_DIR/.linux_util-version"
_GTM_BIN="$HOME/.local/bin/gputaskman"
_GTM_MIN_GLIBC="2.35"

check_gputaskman() {
    [[ -x "$_GTM_EXE" ]]
}

get_version_gputaskman() {
    [[ -r "$_GTM_VERSION_FILE" ]] || { echo ""; return 0; }
    head -1 "$_GTM_VERSION_FILE" | tr -d '[:space:]'
}

# Upstream's architecture name for this machine; fails on anything else.
_gtm_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             return 1 ;;
    esac
}

# Reads a release URL on stdin and prints the bare version of its tag
# (".../releases/tag/v0.4.0" -> "0.4.0").
_gtm_version_from_url() {
    grep -oP '/releases/tag/v\K[0-9]+\.[0-9]+\.[0-9]+(?=$|[/?#])' | head -1
}

# Latest release version. GitHub's /releases/latest redirects to the newest
# tag's page, so the redirect target is read without calling the API (which
# is rate limited) and without downloading anything.
_gtm_latest_version() {
    curl -fsS --max-time 15 -o /dev/null -w '%{redirect_url}' \
        "https://github.com/${_GTM_REPO}/releases/latest" 2>/dev/null | _gtm_version_from_url
}

# The C library version, e.g. "2.39"; empty when it is not glibc (musl).
_gtm_glibc_version() {
    getconf GNU_LIBC_VERSION 2>/dev/null | awk '$1 == "glibc" {print $2}'
}

# True when glibc version $1 is at least $_GTM_MIN_GLIBC.
_gtm_glibc_ok() {
    local have="$1"
    [[ -n "$have" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$_GTM_MIN_GLIBC" "$have" | sort -V | head -1)" == "$_GTM_MIN_GLIBC" ]]
}

# Download version $1 for architecture $2, check it against the .sha256 file
# upstream publishes beside it, and unpack it into a new directory next to the
# install path (same filesystem, so the swap is a rename). Leaves the unpacked
# tree in $_GTM_NEW.
_gtm_download() {
    local version="$1" arch="$2" name base sum expected tmpdir top
    _GTM_NEW=""
    name="gputaskman-${version}-linux-${arch}"
    base="https://github.com/${_GTM_REPO}/releases/download/v${version}"

    sum=$(curl -fsSL --max-time 30 "${base}/${name}.tar.gz.sha256" 2>/dev/null) || {
        error "Could not download the GPU Task Manager ${version} checksum file."
        return 1
    }
    expected=$(printf '%s\n' "$sum" | grep -oE '^[0-9a-fA-F]{64}' | head -1)
    if [[ -z "$expected" ]]; then
        error "The GPU Task Manager ${version} checksum file does not hold a SHA-256."
        return 1
    fi

    mkdir -p "$(dirname "$_GTM_DIR")" || return 1
    tmpdir=$(mktemp -d "$(dirname "$_GTM_DIR")/.gputaskman-XXXXXX") || return 1
    CLEANUP_FILES+=("$tmpdir")

    info "Downloading GPU Task Manager ${version} (about 20 MB)..."
    download_file "${base}/${name}.tar.gz" "$tmpdir/${name}.tar.gz" || {
        rm -rf "$tmpdir"
        error "Failed to download GPU Task Manager ${version}."
        return 1
    }
    verify_download "$tmpdir/${name}.tar.gz" tar.gz "GPU Task Manager" || { rm -rf "$tmpdir"; return 1; }
    verify_sha256 "$tmpdir/${name}.tar.gz" "$expected" "GPU Task Manager ${version}" || {
        rm -rf "$tmpdir"
        error "GPU Task Manager ${version} failed SHA-256 verification; nothing was installed."
        return 1
    }

    if ! tar -xzf "$tmpdir/${name}.tar.gz" -C "$tmpdir"; then
        rm -rf "$tmpdir"
        error "Failed to unpack the GPU Task Manager archive."
        return 1
    fi
    top="$tmpdir/$name"
    # A layout change upstream stops here rather than installing half a bundle.
    if [[ ! -f "$top/gputaskman" || ! -d "$top/_internal" ]]; then
        rm -rf "$tmpdir"
        error "The GPU Task Manager archive has an unexpected layout (no gputaskman and _internal); nothing was installed."
        return 1
    fi
    chmod 0755 "$top/gputaskman"
    printf '%s\n' "$version" > "$top/.linux_util-version"
    rm -f "$tmpdir/${name}.tar.gz"
    _GTM_NEW="$top"
}

install_gputaskman() {
    info "Installing GPU Task Manager..."
    local arch version glibc
    if ! arch=$(_gtm_arch); then
        error "GPU Task Manager is published for x86_64 and aarch64 only (this machine is $(uname -m))."
        return 1
    fi
    glibc=$(_gtm_glibc_version)
    if ! _gtm_glibc_ok "$glibc"; then
        error "GPU Task Manager needs glibc ${_GTM_MIN_GLIBC} or newer; this system has ${glibc:-no glibc}."
        return 1
    fi
    ensure_tools

    version=$(_gtm_latest_version)
    if [[ -z "$version" ]]; then
        error "Could not find the latest GPU Task Manager release on GitHub."
        return 1
    fi

    _gtm_download "$version" "$arch" || return 1

    rm -rf "$_GTM_DIR" || { error "Could not remove the old copy in ${_GTM_DIR}."; return 1; }
    mv "$_GTM_NEW" "$_GTM_DIR" || { error "Failed to install GPU Task Manager to ${_GTM_DIR}."; return 1; }
    rm -rf "$(dirname "$_GTM_NEW")"

    mkdir -p "$(dirname "$_GTM_BIN")" || return 1
    ln -sfn "$_GTM_EXE" "$_GTM_BIN"

    info "GPU Task Manager ${version} installed (command: gputaskman)."
    info "Run gputaskman in a terminal (q quits); sudo gputaskman also lists other users' processes."
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *)
            # shellcheck disable=SC2088  # the literal ~ is the text shown, not a path
            warn "~/.local/bin is not on your PATH; run ${_GTM_BIN} or add ~/.local/bin to PATH."
            ;;
    esac
}

uninstall_gputaskman() {
    info "Uninstalling GPU Task Manager..."
    if [[ ! -e "$_GTM_DIR" ]]; then
        echo "GPU Task Manager installation not found."
        return 0
    fi
    rm -rf "$_GTM_DIR" || return 1
    [[ -L "$_GTM_BIN" && "$(readlink "$_GTM_BIN")" == "$_GTM_EXE" ]] && rm -f "$_GTM_BIN"
    info "GPU Task Manager has been uninstalled."
}

update_gputaskman() {
    info "Updating GPU Task Manager..."
    local installed latest
    installed=$(get_version_gputaskman)
    latest=$(_gtm_latest_version)
    # An unknown version on either side falls through and reinstalls rather than
    # risk skipping a real update.
    if [[ -n "$installed" && "$installed" == "$latest" ]]; then
        info "GPU Task Manager is already at the latest version (${installed})."
        return 0
    fi
    install_gputaskman
}
