#!/bin/bash
# VeraCrypt disk encryption installer functions
# Arch: the veracrypt package in the official repositories. Elsewhere VeraCrypt
# is in no distro repository, so the installer takes the package upstream
# attaches to its GitHub release: a per-release .deb (Debian, Ubuntu) or .rpm
# (Fedora, RHEL clones, openSUSE), whose detached signature is checked against
# VeraCrypt's published signing key (fingerprint pinned below). VeraCrypt builds
# only for the releases it lists, and says so when yours is not one of them.
# Alpine has no package, so it is not offered there.

# --- VeraCrypt ---

_VC_API="https://api.github.com/repos/veracrypt/VeraCrypt/releases/latest"
_VC_KEY_URL="https://veracrypt.io/VeraCrypt_PGP_public_key.asc"
# Primary fingerprint of the VeraCrypt Team signing key (key ID 821ACD02680D16DE).
_VC_KEY_FPR="5069A233D55A0EEB174A5FC3821ACD02680D16DE"

check_veracrypt() { _check_standard veracrypt veracrypt ""; }

_VC_JSON=""

# Latest release version, e.g. 1.26.31.
_veracrypt_latest_version() {
    curl -fsSL --max-time 15 "$_VC_API" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"VeraCrypt_\K[0-9.]+' | head -1
}

# Print the download URL of the release file named $1, or nothing.
_veracrypt_asset_url() {
    [[ -n "$_VC_JSON" ]] || _VC_JSON=$(curl -fsSL --max-time 30 "$_VC_API" 2>/dev/null) || return 1
    grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' <<<"$_VC_JSON" | grep -E "/${1//./\\.}\$" | head -1
}

# Print the file name of the release package that fits this system, or nothing.
# $1 is the version. The names are fixed by upstream: veracrypt-VER-OS-RELEASE-ARCH.
_veracrypt_package_name() {
    local ver="$1" os rel dpkg_arch names deb_rel
    [[ -n "$_VC_JSON" ]] || _VC_JSON=$(curl -fsSL --max-time 30 "$_VC_API" 2>/dev/null) || return 1
    names=$(grep -oP '"name"\s*:\s*"\Kveracrypt-'"${ver//./\\.}"'-[^"]+\.(deb|rpm)(?=")' <<<"$_VC_JSON")
    case "$DISTRO_FAMILY" in
        debian)
            # DISTRO_VERSION_ID carries the point release (13.7, 24.04.4); the
            # file names use the release only (13, 24.04).
            case "$DISTRO_ID" in
                debian)         os=Debian; deb_rel=${DISTRO_VERSION_ID%%.*} ;;
                ubuntu|kubuntu) os=Ubuntu; deb_rel=$(cut -d. -f1,2 <<<"$DISTRO_VERSION_ID") ;;
                *)              return 1 ;;
            esac
            dpkg_arch=$(dpkg --print-architecture)
            grep -x "veracrypt-${ver//./\\.}-${os}-${deb_rel//./\\.}-${dpkg_arch}\.deb" <<<"$names"
            ;;
        fedora)
            rel=${DISTRO_VERSION_ID%%.*}
            # No build for this exact release (Fedora is ahead of upstream): the
            # newest Fedora build upstream publishes.
            grep -x "veracrypt-${ver//./\\.}-Fedora-${rel}-x86_64\.rpm" <<<"$names" \
                || grep -E "^veracrypt-${ver//./\\.}-Fedora-[0-9]+-x86_64\.rpm$" <<<"$names" | sort -V | tail -1
            ;;
        rhel)
            grep -x "veracrypt-${ver//./\\.}-CentOS-8-x86_64\.rpm" <<<"$names"
            ;;
        suse)
            grep -x "veracrypt-${ver//./\\.}-openSUSE-15-x86_64\.rpm" <<<"$names"
            ;;
    esac
}

# Check the detached signature $2 (a URL) of file $1 against VeraCrypt's signing
# key. The key is downloaded, its fingerprint compared with the pinned one, and
# only then used, in a throwaway keyring so nothing is added to the user's own.
# On openSUSE the key is also imported into rpm, which otherwise refuses the
# package as "NOKEY".
_veracrypt_verify_signature() {
    local file="$1" sig_url="$2" tmp keyfile sigfile status primary fprs
    [[ -n "$sig_url" ]] || { error "The VeraCrypt release has no signature for $(basename "$file")."; return 1; }
    tmp=$(mktemp -d /tmp/veracrypt-key-XXXXXX) || return 1
    keyfile="$tmp/key.asc"; sigfile="$tmp/sig"
    curl -fsSL --max-time 30 -o "$keyfile" "$_VC_KEY_URL" && download_file "$sig_url" "$sigfile" || {
        rm -rf "$tmp"; error "Could not download the VeraCrypt signing key or signature."; return 1
    }
    fprs=$(GNUPGHOME="$tmp" gpg --show-keys --with-colons "$keyfile" 2>/dev/null | awk -F: '$1 == "fpr" { print $10 }')
    if ! grep -qx "$_VC_KEY_FPR" <<<"$fprs"; then
        rm -rf "$tmp"; error "The downloaded VeraCrypt key does not match fingerprint ${_VC_KEY_FPR}."; return 1
    fi
    GNUPGHOME="$tmp" gpg --batch --import "$keyfile" &>/dev/null
    status=$(GNUPGHOME="$tmp" gpg --batch --status-fd 1 --verify "$sigfile" "$file" 2>/dev/null)
    # VALIDSIG's last field is the primary key fingerprint, whichever subkey signed.
    primary=$(awk '$2 == "VALIDSIG" { print $NF }' <<<"$status")
    if [[ "$primary" != "$_VC_KEY_FPR" ]]; then
        rm -rf "$tmp"; error "The signature on $(basename "$file") is not a valid VeraCrypt signature."; return 1
    fi
    if [[ "$DISTRO_FAMILY" == "suse" ]] && ! sudo rpm --import "$keyfile"; then
        rm -rf "$tmp"; error "Could not import the VeraCrypt signing key into rpm."; return 1
    fi
    rm -rf "$tmp"
    return 0
}

install_veracrypt() {
    info "Installing VeraCrypt..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            pkg_install veracrypt
            info "VeraCrypt installed."
            return $?
            ;;
        debian|fedora|rhel|suse) ;;
        *)
            error "VeraCrypt publishes no package for ${DISTRO_NAME}."
            return 1
            ;;
    esac

    local ver name url ext tmpdir pkgfile
    ver=$(_veracrypt_latest_version)
    [[ -n "$ver" ]] || { error "Could not read the latest VeraCrypt release from GitHub."; return 1; }
    name=$(_veracrypt_package_name "$ver")
    if [[ -z "$name" ]]; then
        error "VeraCrypt ${ver} has no build for ${DISTRO_NAME} ${DISTRO_VERSION_ID} (Debian 12/13, Ubuntu 22.04+, Fedora, CentOS 8 and openSUSE 15 only)."
        return 1
    fi
    if [[ "$DISTRO_FAMILY" == "fedora" && "$name" != *"-Fedora-${DISTRO_VERSION_ID%%.*}-"* ]]; then
        warn "VeraCrypt has no Fedora ${DISTRO_VERSION_ID} build yet; using the newest one it publishes (${name})."
    fi
    url=$(_veracrypt_asset_url "$name")
    [[ -n "$url" ]] || { error "Could not find ${name} in the VeraCrypt release."; return 1; }

    ext="${name##*.}"
    tmpdir=$(mktemp -d /tmp/veracrypt-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    pkgfile="$tmpdir/$name"
    download_file "$url" "$pkgfile" || { error "Failed to download ${name}."; return 1; }
    verify_download "$pkgfile" "$ext" "VeraCrypt" || return 1

    _veracrypt_verify_signature "$pkgfile" "$(_veracrypt_asset_url "${name}.sig")" || return 1

    pkg_install_local "$pkgfile" || { error "Installing ${name} failed."; return 1; }
    info "VeraCrypt installed."
}

uninstall_veracrypt() {
    info "Uninstalling VeraCrypt..."
    pkg_remove veracrypt
}

update_veracrypt() {
    info "Updating VeraCrypt..."
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        pkg_upgrade veracrypt
        return $?
    fi
    local installed latest
    installed=$(get_version_veracrypt)
    latest=$(_veracrypt_latest_version)
    if [[ -n "$installed" && "$installed" == "$latest" ]]; then
        info "VeraCrypt is already at ${installed}."
        return 0
    fi
    install_veracrypt
}

get_version_veracrypt() { _ver_from_pkg veracrypt || echo ""; }
