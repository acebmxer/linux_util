#!/bin/bash
# Claude Desktop installer functions

# --- Claude Desktop ---
# Anthropic's Linux build is a beta for Debian-based distributions only
# (Ubuntu 22.04+, Debian 12+, amd64/arm64). Reference:
# https://code.claude.com/docs/en/desktop-linux
#
# Debian family: installed natively from Anthropic's apt repository.
# Every other family: installed the same way inside an Ubuntu distrobox, with
# the app exported to the host's application menu. Distrobox is installed
# first when it is missing.

_CLAUDE_DESKTOP_KEYRING="/usr/share/keyrings/claude-desktop.gpg"
_CLAUDE_DESKTOP_LIST="/etc/apt/sources.list.d/claude-desktop.list"

_CLAUDE_DESKTOP_BOX="claude-desktop"
_CLAUDE_DESKTOP_BOX_IMAGE="docker.io/library/ubuntu:26.04"
# Written after every install/update inside the box. Its presence is what marks
# the box install (check, and System Updates via mark_upstream_binary), and its
# content is the installed version, so the menu never has to start the box to
# read it.
_CLAUDE_DESKTOP_BOX_VERSION_FILE="$HOME/.local/share/linux_util/claude-desktop-box.version"
# The box shares the host's home directory, so its fontconfig (and the copy
# bundled in Claude's Electron) wrote font caches into the host's
# ~/.cache/fontconfig. Host Electron apps such as Termius then found no usable
# fonts there and crashed on launch. A conf.d entry inside the box gives it its
# own cache directory; conf.d is included ahead of the stock <cachedir> lines,
# so it is the first writable one and every write lands there.
_CLAUDE_DESKTOP_BOX_FONT_CACHE="fontconfig-claude-desktop-box"

# Register Anthropic's apt repository. Called on a Debian host, and shipped into
# the distrobox with declare -f so both routes add the repo identically.
_claude_desktop_add_repo() {
    # The package installs its own armored key at
    # claude-desktop-archive-keyring.asc, but leaves an existing
    # claude-desktop.list alone, so the dearmored keyring written here stays
    # the one apt uses.
    _add_apt_repo \
        "https://downloads.claude.ai/claude-desktop/key.asc" \
        "$_CLAUDE_DESKTOP_KEYRING" \
        "deb [arch=amd64,arm64 signed-by=${_CLAUDE_DESKTOP_KEYRING}] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        "$_CLAUDE_DESKTOP_LIST" \
        "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
}

_claude_desktop_uses_box() { [[ "$DISTRO_FAMILY" != "debian" ]]; }

# Runs inside the box (shipped with declare -f). Idempotent.
_claude_desktop_box_font_cache() {
    sudo mkdir -p /etc/fonts/conf.d &&
    printf '%s\n' \
        '<?xml version="1.0"?>' \
        '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">' \
        '<fontconfig>' \
        "  <cachedir prefix=\"xdg\">${_CLAUDE_DESKTOP_BOX_FONT_CACHE}</cachedir>" \
        '</fontconfig>' |
        sudo tee /etc/fonts/conf.d/00-linux-util-cachedir.conf >/dev/null
}

# Every distrobox call goes through here with the script's lock fd (9) closed.
# Starting a box leaves its conmon process running after this script exits; it
# inherited fd 9, so it kept the lock held and every later linux_util run
# reported "Another instance of this script is already running" until the box
# stopped.
_claude_desktop_dbx() { distrobox "$@" 9>&-; }

# Run a bash snippet inside the box, with the helpers it may call defined.
_claude_desktop_box_run() {
    _claude_desktop_dbx enter "$_CLAUDE_DESKTOP_BOX" -- bash -c "
$(declare -p _CLAUDE_DESKTOP_KEYRING _CLAUDE_DESKTOP_LIST _CLAUDE_DESKTOP_BOX_FONT_CACHE)
$(declare -f _claude_desktop_box_font_cache)
$(declare -f error _add_apt_repo _claude_desktop_add_repo)
$1"
}

# Record the version installed in the box (same normalisation as _ver_from_pkg).
_claude_desktop_box_record_version() {
    local v
    # shellcheck disable=SC2016  # ${Version} is dpkg-query's format field, not a shell variable
    v=$(_claude_desktop_dbx enter "$_CLAUDE_DESKTOP_BOX" -- dpkg-query -W -f='${Version}' claude-desktop 2>/dev/null |
        tr -d '\r' | sed 's/^[0-9]*://; s/-.*//')
    if [[ -z "$v" ]]; then
        error "Claude Desktop is not installed inside the '${_CLAUDE_DESKTOP_BOX}' distrobox."
        return 1
    fi
    mkdir -p "$(dirname "$_CLAUDE_DESKTOP_BOX_VERSION_FILE")"
    printf '%s\n' "$v" > "$_CLAUDE_DESKTOP_BOX_VERSION_FILE"
}

# Newest version in Anthropic's repository for this machine's architecture.
_claude_desktop_latest_version() {
    local arch
    case "$(uname -m)" in
        x86_64)  arch=amd64 ;;
        aarch64) arch=arm64 ;;
        *)       return 1 ;;
    esac
    curl -fsSL --max-time 15 \
        "https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-${arch}/Packages" 2>/dev/null |
        awk '$1 == "Package:" { p = $2 } p == "claude-desktop" && $1 == "Version:" { print $2 }' |
        sed 's/^[0-9]*://; s/-.*//' | sort -V | tail -n 1
}

_claude_desktop_install_box() {
    case "$(uname -m)" in
        x86_64|aarch64) ;;
        *)
            error "Claude Desktop is only published for x86_64 and arm64 (this system is $(uname -m))."
            return 1
            ;;
    esac
    # Podman goes in before Distrobox when no engine is present: Fedora's
    # distrobox package depends on "podman or docker", and on a system with
    # neither, dnf satisfied it with Docker, whose daemon is not running after
    # install, so creating the box failed.
    if ! _have_cmd podman && ! _have_cmd docker; then
        info "Claude Desktop runs in a distrobox on this distro; installing Podman for it..."
        install_podman || return 1
        if ! _have_cmd podman; then
            error "Podman did not install; Claude Desktop needs it for its distrobox."
            return 1
        fi
    fi
    if ! _have_cmd distrobox; then
        info "Claude Desktop runs in a distrobox on this distro; installing Distrobox first..."
        install_distrobox || return 1
    fi

    if ! _claude_desktop_dbx list 2>/dev/null | awk -F'|' '{ gsub(/ /, "", $2); print $2 }' | grep -qx "$_CLAUDE_DESKTOP_BOX"; then
        info "Creating the '${_CLAUDE_DESKTOP_BOX}' distrobox (${_CLAUDE_DESKTOP_BOX_IMAGE})..."
        _claude_desktop_dbx create --yes --name "$_CLAUDE_DESKTOP_BOX" --image "$_CLAUDE_DESKTOP_BOX_IMAGE" || {
            error "Could not create the '${_CLAUDE_DESKTOP_BOX}' distrobox."
            return 1
        }
    fi

    info "Installing Claude Desktop inside the distrobox (the first start takes a few minutes)..."
    _claude_desktop_box_run '
sudo env DEBIAN_FRONTEND=noninteractive apt-get update &&
_claude_desktop_box_font_cache &&
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg &&
_claude_desktop_add_repo &&
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y claude-desktop &&
distrobox-export --app claude-desktop' || {
        error "Installing Claude Desktop inside the distrobox failed (see output above)."
        return 1
    }
    _claude_desktop_box_record_version || return 1
    info "Claude Desktop installed in the '${_CLAUDE_DESKTOP_BOX}' distrobox and added to the application menu."
}

check_claude_desktop() {
    if _claude_desktop_uses_box; then
        [[ -f "$_CLAUDE_DESKTOP_BOX_VERSION_FILE" ]]
    else
        _check_standard claude-desktop claude-desktop ""
    fi
}

install_claude_desktop() {
    info "Installing Claude Desktop..."
    if _claude_desktop_uses_box; then
        _claude_desktop_install_box
        return
    fi
    local _arch
    _arch=$(dpkg --print-architecture)
    if [[ "$_arch" != "amd64" && "$_arch" != "arm64" ]]; then
        error "Claude Desktop is only published for amd64 and arm64 (this system is $_arch)."
        return 1
    fi
    ensure_tools
    _claude_desktop_add_repo || return 1
    pkg_install claude-desktop || return 1
    info "Claude Desktop installed. Launch it as a regular user, not root."
}

uninstall_claude_desktop() {
    info "Uninstalling Claude Desktop..."
    if _claude_desktop_uses_box; then
        if _have_cmd distrobox; then
            # Remove the menu entry while the box still exists, then the whole box.
            _claude_desktop_dbx enter "$_CLAUDE_DESKTOP_BOX" -- distrobox-export --app claude-desktop --delete 2>/dev/null || true
            _claude_desktop_dbx rm --force "$_CLAUDE_DESKTOP_BOX" || {
                error "Could not remove the '${_CLAUDE_DESKTOP_BOX}' distrobox."
                return 1
            }
        fi
        rm -f "$_CLAUDE_DESKTOP_BOX_VERSION_FILE"
        rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/${_CLAUDE_DESKTOP_BOX_FONT_CACHE}"
        return 0
    fi
    pkg_remove claude-desktop
    sudo rm -f "$_CLAUDE_DESKTOP_LIST" "$_CLAUDE_DESKTOP_KEYRING" \
        /usr/share/keyrings/claude-desktop-archive-keyring.asc
}

update_claude_desktop() {
    info "Updating Claude Desktop..."
    if _claude_desktop_uses_box; then
        _claude_desktop_box_run '_claude_desktop_box_font_cache && sudo env DEBIAN_FRONTEND=noninteractive apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade claude-desktop' || return 1
        _claude_desktop_box_record_version
        return
    fi
    pkg_upgrade claude-desktop
}

get_version_claude_desktop() {
    # Do NOT run claude-desktop --version — Electron apps launch a full GUI window.
    if _claude_desktop_uses_box; then
        head -n 1 "$_CLAUDE_DESKTOP_BOX_VERSION_FILE" 2>/dev/null || echo ""
        return 0
    fi
    _ver_from_pkg claude-desktop || echo ""
}
