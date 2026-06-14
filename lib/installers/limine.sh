#!/bin/bash
# Limine bootloader installer functions

# --- Limine ---
# Limine is a modern, portable bootloader supporting BIOS, UEFI (x86_64, aarch64),
# and Limine Boot Protocol. Installed from the official GitHub releases.

_LIMINE_INSTALL_DIR="/opt/limine"

check_limine() {
    [[ -f "$_LIMINE_INSTALL_DIR/limine" ]]      ||
    command -v limine &>/dev/null                ||
    [[ -f "$_LIMINE_INSTALL_DIR/BOOTX64.EFI" ]] ||
    [[ -f "$_LIMINE_INSTALL_DIR/limine-uefi-cd.bin" ]]
}

install_limine() {
    info "Installing Limine bootloader..."

    # Not supported on Debian/Ubuntu: those distros maintain GRUB entries
    # automatically on kernel updates (apt hooks), but have no equivalent hook to
    # keep a Limine config in sync, so its menu would silently go stale after the
    # next kernel install. Stick with GRUB there.
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        warn "Limine is not supported on Debian/Ubuntu by this tool."
        warn "Debian/Ubuntu don't regenerate a Limine config on kernel updates, so its"
        warn "menu would go stale. Use GRUB on Debian/Ubuntu."
        return 1
    fi

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

    # The limine host utility (used for BIOS installs) is a single C file shipped
    # in the binary tarball with a Makefile; it only needs a C compiler and make.
    # We use the prebuilt BIOS/EFI stages, so nasm/mtools/xorriso aren't required.
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y gcc make wget 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" install -y gcc make wget 2>/dev/null || true ;;
        arch)        sudo pacman -S --noconfirm gcc make 2>/dev/null || true ;;
        suse)        sudo zypper install -y gcc make wget 2>/dev/null || true ;;
    esac

    tmpdir=$(mktemp -d /tmp/limine-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")

    local tarball_url="https://github.com/limine-bootloader/limine/releases/download/${version}/limine-binary.tar.xz"
    info "Downloading Limine ${ver_num}..."
    if ! wget -qO "$tmpdir/limine.tar.xz" "$tarball_url"; then
        error "Failed to download Limine from $tarball_url"
        return 1
    fi

    tar -xf "$tmpdir/limine.tar.xz" -C "$tmpdir" --strip-components=1

    sudo mkdir -p "$_LIMINE_INSTALL_DIR"
    sudo cp -r "$tmpdir"/. "$_LIMINE_INSTALL_DIR/"

    # Build the limine host utility in place. The binary tarball ships limine.c
    # plus a Makefile whose default target compiles it with cc — no ./configure
    # and no extra toolchain. This utility is only needed for BIOS deployment;
    # UEFI boots directly from the prebuilt BOOTX64.EFI.
    if [[ ! -x "$_LIMINE_INSTALL_DIR/limine" && -f "$_LIMINE_INSTALL_DIR/limine.c" ]]; then
        info "Building the Limine host utility..."
        sudo make -C "$_LIMINE_INSTALL_DIR" >/dev/null 2>&1 || true
    fi

    if [[ -x "$_LIMINE_INSTALL_DIR/limine" ]]; then
        sudo ln -sf "$_LIMINE_INSTALL_DIR/limine" /usr/local/bin/limine
        info "Limine ${ver_num} installed to $_LIMINE_INSTALL_DIR (BIOS + UEFI ready)."
    elif [[ -f "$_LIMINE_INSTALL_DIR/BOOTX64.EFI" ]]; then
        info "Limine ${ver_num} installed to $_LIMINE_INSTALL_DIR."
        warn "Host utility not built — UEFI boot works, but BIOS installs need gcc/make. Re-run after installing them."
    else
        error "Limine installation incomplete: no usable binaries in $_LIMINE_INSTALL_DIR."
        return 1
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
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        warn "Limine is not supported on Debian/Ubuntu by this tool."
        return 1
    fi
    install_limine
}

get_version_limine() {
    limine --version 2>/dev/null | grep -oP '[\d.]+' | head -1 \
        || ls "$_LIMINE_INSTALL_DIR" 2>/dev/null \
             | grep -oP 'limine-[\d.]+' | grep -oP '[\d.]+' | head -1 \
        || echo ""
}
