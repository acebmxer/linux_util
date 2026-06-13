#!/bin/bash
# CachyOS Kernel Manager — GUI to install, build, swap, and remove kernels on
# Arch-family systems (a front-end over pacman; it also configures sched-ext
# schedulers from the same window).
#
# The 'cachyos-kernel-manager' package ships only in the CachyOS binary
# repository — it is NOT in the AUR. So it installs out of the box on CachyOS,
# and on any Arch system that already has the CachyOS repo enabled. We
# deliberately do NOT add the CachyOS repo here (that rewrites pacman.conf and
# the mirrorlist system-wide and pulls in the CachyOS keyring); if the package
# is not in a configured repository we warn and link the upstream setup guide.

# --- CachyOS Kernel Manager ---

CACHYOS_KM_PKG="cachyos-kernel-manager"
CACHYOS_KM_SETUP_URL="https://wiki.cachyos.org/features/kernel_manager/"

check_cachyos_kernel_manager() {
    _check_standard "$CACHYOS_KM_PKG" "$CACHYOS_KM_PKG" ""
}

get_version_cachyos_kernel_manager() {
    _ver_from_pkg "$CACHYOS_KM_PKG" || echo ""
}

install_cachyos_kernel_manager() {
    info "Installing CachyOS Kernel Manager..."

    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        warn "CachyOS Kernel Manager is an Arch-family tool."
        warn "On Debian/Ubuntu use 'Mainline'; on Fedora use 'Fedora Mainline Kernel'."
        return 1
    fi

    # The package lives in the CachyOS repo, not the AUR, so an AUR helper cannot
    # fetch it. Only proceed when pacman can already see it in a configured repo.
    if ! pacman -Si "$CACHYOS_KM_PKG" &>/dev/null; then
        error "'${CACHYOS_KM_PKG}' was not found in any configured pacman repository."
        warn  "It ships only in the CachyOS repo (not the AUR). Enable the CachyOS"
        warn  "repository first, then re-run this task. Setup guide: ${CACHYOS_KM_SETUP_URL}"
        return 1
    fi

    pkg_install "$CACHYOS_KM_PKG" || { error "Failed to install ${CACHYOS_KM_PKG}."; return 1; }
    info "CachyOS Kernel Manager installed. Launch it from your application menu or run '${CACHYOS_KM_PKG}'."
}

uninstall_cachyos_kernel_manager() {
    info "Uninstalling CachyOS Kernel Manager..."
    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        info "CachyOS Kernel Manager is only installed on Arch-family systems — nothing to do."
        return 0
    fi
    pkg_remove "$CACHYOS_KM_PKG" 2>/dev/null || true
    # Cached/built kernel packages the GUI produced are left for the user to manage.
    info "Built-kernel cache (if any) remains under ~/.cache/cachyos-km — remove it manually if unwanted."
}

update_cachyos_kernel_manager() {
    info "Updating CachyOS Kernel Manager..."
    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        warn "CachyOS Kernel Manager is an Arch-family tool."
        return 1
    fi
    pkg_upgrade "$CACHYOS_KM_PKG"
}
