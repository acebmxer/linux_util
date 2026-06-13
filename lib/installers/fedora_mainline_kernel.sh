#!/bin/bash
# Fedora Mainline Kernel — enables the community @kernel-vanilla/mainline Copr and
# installs the latest upstream (vanilla) mainline kernel on Fedora.
#
# Fedora ships no dedicated GUI kernel manager; the kernel-vanilla Copr is the
# standard way to run an upstream mainline kernel. Fedora only (RHEL is a
# separate family and the Copr targets Fedora releases).
#
# Note: Copr mainline kernels are unsigned, so Secure Boot must be disabled to
# boot them. The stock Fedora kernel is left installed as a fallback.

# --- Fedora Mainline Kernel ---

FEDORA_KV_COPR="@kernel-vanilla/mainline"

# "Installed" == the kernel-vanilla mainline Copr is enabled on this system.
# dnf writes a repo file named like
# _copr:copr.fedorainfracloud.org:group_kernel-vanilla:mainline.repo
check_fedora_mainline_kernel() {
    compgen -G "/etc/yum.repos.d/*kernel-vanilla*mainline*.repo" >/dev/null 2>&1
}

get_version_fedora_mainline_kernel() {
    check_fedora_mainline_kernel && echo "Copr enabled"
}

# The 'copr' subcommand comes from dnf-plugins-core; make sure it is present.
_fedora_ensure_copr_plugin() {
    dnf copr --help &>/dev/null && return 0
    info "Installing prerequisite 'dnf-plugins-core' (provides 'dnf copr')..."
    pkg_install dnf-plugins-core
    dnf copr --help &>/dev/null || { error "'dnf copr' is unavailable even after installing dnf-plugins-core."; return 1; }
}

install_fedora_mainline_kernel() {
    info "Installing the latest mainline kernel via the kernel-vanilla Copr..."

    if [[ "$DISTRO_FAMILY" != "fedora" ]]; then
        warn "Fedora Mainline Kernel uses a Fedora Copr and only works on Fedora."
        warn "On Debian/Ubuntu use 'Mainline'; on Arch use 'CachyOS Kernel Manager'."
        return 1
    fi

    _fedora_ensure_copr_plugin || return 1

    info "Enabling Copr ${FEDORA_KV_COPR}..."
    run_as_root dnf -y copr enable "$FEDORA_KV_COPR" \
        || { error "Failed to enable the kernel-vanilla Copr."; return 1; }

    info "Installing the latest mainline kernel (kernel + kernel-core + kernel-modules)..."
    run_as_root dnf -y --refresh install kernel kernel-core kernel-modules \
        || { error "Failed to install the mainline kernel from the Copr."; return 1; }

    warn "Mainline kernels are unsigned — disable Secure Boot if enabled."
    info "Reboot and pick the new kernel from the GRUB boot menu. The stock Fedora kernel remains as a fallback."
}

uninstall_fedora_mainline_kernel() {
    info "Disabling the kernel-vanilla mainline Copr..."
    if [[ "$DISTRO_FAMILY" != "fedora" ]]; then
        info "Not a Fedora system — nothing to do."
        return 0
    fi
    run_as_root dnf -y copr disable "$FEDORA_KV_COPR" 2>/dev/null || true
    warn "The Copr is disabled, but any already-installed mainline kernel stays until you remove it."
    warn "Boot into a stock Fedora kernel first, then remove the unwanted kernel with 'dnf remove'."
}

update_fedora_mainline_kernel() {
    info "Updating to the latest mainline kernel from the kernel-vanilla Copr..."
    if [[ "$DISTRO_FAMILY" != "fedora" ]]; then
        warn "Fedora Mainline Kernel only works on Fedora."
        return 1
    fi
    if ! check_fedora_mainline_kernel; then
        install_fedora_mainline_kernel
        return
    fi
    run_as_root dnf -y --refresh upgrade kernel kernel-core kernel-modules || true
}
