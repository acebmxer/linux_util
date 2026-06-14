#!/bin/bash
# Limine bootloader installer functions

# --- Limine ---
# Limine is a modern, portable bootloader supporting BIOS, UEFI (x86_64, aarch64),
# and Limine Boot Protocol. Installed from the official GitHub releases.

_LIMINE_INSTALL_DIR="/opt/limine"

check_limine() {
    [[ -f "$_LIMINE_INSTALL_DIR/limine" ]] || command -v limine &>/dev/null
}

install_limine() {
    info "Installing Limine bootloader..."
    ensure_tools

    local version arch tmpdir
    version=$(curl -fsSL https://api.github.com/repos/limine-bootloader/limine/releases/latest \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$version" ]] && { error "Could not determine latest Limine version."; return 1; }
    local ver_num="${version#v}"

    case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    # Install build dependencies needed to compile the deployment tool
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y gcc make nasm mtools xorriso wget 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y gcc make nasm mtools xorriso wget 2>/dev/null || true
            ;;
        arch)
            sudo pacman -S --noconfirm gcc make nasm mtools xorriso 2>/dev/null || true
            ;;
        suse)
            sudo zypper install -y gcc make nasm mtools xorriso 2>/dev/null || true
            ;;
    esac

    tmpdir=$(mktemp -d /tmp/limine-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")

    local tarball_url="https://github.com/limine-bootloader/limine/releases/download/${version}/limine-${ver_num}-binary.tar.xz"
    info "Downloading Limine ${ver_num}..."
    if ! wget -qO "$tmpdir/limine.tar.xz" "$tarball_url"; then
        error "Failed to download Limine from $tarball_url"
        return 1
    fi

    tar -xf "$tmpdir/limine.tar.xz" -C "$tmpdir" --strip-components=1

    sudo mkdir -p "$_LIMINE_INSTALL_DIR"
    sudo cp -r "$tmpdir"/. "$_LIMINE_INSTALL_DIR/"

    # Build the limine deployment tool from source if the binary is not present
    if [[ ! -f "$_LIMINE_INSTALL_DIR/limine" ]]; then
        info "Building the Limine deployment utility..."
        local src_url="https://github.com/limine-bootloader/limine/releases/download/${version}/limine-${ver_num}.tar.xz"
        wget -qO "$tmpdir/limine-src.tar.xz" "$src_url" && \
        mkdir -p "$tmpdir/src" && \
        tar -xf "$tmpdir/limine-src.tar.xz" -C "$tmpdir/src" --strip-components=1 && \
        (cd "$tmpdir/src" && make) && \
        sudo cp "$tmpdir/src/limine" "$_LIMINE_INSTALL_DIR/limine"
    fi

    # Symlink into PATH if the binary exists
    if [[ -f "$_LIMINE_INSTALL_DIR/limine" ]]; then
        sudo ln -sf "$_LIMINE_INSTALL_DIR/limine" /usr/local/bin/limine
        info "Limine ${ver_num} installed to $_LIMINE_INSTALL_DIR."
        info "Use 'sudo limine bios-install /dev/sdX' to deploy to a BIOS disk."
        info "Copy EFI binaries from $_LIMINE_INSTALL_DIR to your ESP for UEFI boot."
    else
        info "Limine binary files installed to $_LIMINE_INSTALL_DIR."
        info "The deployment utility could not be built — install gcc/make and re-run."
    fi
}

uninstall_limine() {
    info "Uninstalling Limine..."
    sudo rm -rf "$_LIMINE_INSTALL_DIR"
    sudo rm -f /usr/local/bin/limine
    info "Limine removed."
}

update_limine() {
    info "Updating Limine..."
    install_limine
}

get_version_limine() {
    limine --version 2>/dev/null | grep -oP '[\d.]+' | head -1 \
        || ls "$_LIMINE_INSTALL_DIR" 2>/dev/null \
             | grep -oP 'limine-[\d.]+' | grep -oP '[\d.]+' | head -1 \
        || echo ""
}
