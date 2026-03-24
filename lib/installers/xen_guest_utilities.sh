#!/bin/bash
# XEN Guest Utilities installer functions

# --- XEN Guest Utilities ---
check_xen_guest_utilities() {
    pkg_check_installed xe-guest-utilities || pkg_check_installed xen-guest-agent || pkg_check_installed xe-guest-utilities-latest
}

uninstall_xen_guest_utilities() {
    echo "Uninstalling XEN Guest Utilities..."

    # Stop and disable the service
    sudo systemctl stop xe-linux-distribution 2>/dev/null || true
    sudo systemctl disable xe-linux-distribution 2>/dev/null || true

    # Remove all known package variants
    if pkg_check_installed xe-guest-utilities; then
        pkg_remove xe-guest-utilities
    fi
    if pkg_check_installed xen-guest-agent; then
        pkg_remove xen-guest-agent
    fi
    if pkg_check_installed xe-guest-utilities-latest; then
        pkg_remove xe-guest-utilities-latest
    fi

    rm -rf ~/.config/xen
    rm -rf ~/.xen
    echo "XEN Guest Utilities have been uninstalled."
}

get_version_xen_guest_utilities() {
    local ver=""
    if pkg_check_installed xe-guest-utilities; then
        ver=$(pkg_get_version xe-guest-utilities)
    elif pkg_check_installed xen-guest-agent; then
        ver=$(pkg_get_version xen-guest-agent)
    elif pkg_check_installed xe-guest-utilities-latest; then
        ver=$(pkg_get_version xe-guest-utilities-latest)
    fi
    # Strip epoch and distro suffix
    [[ -n "$ver" ]] && echo "$ver" | sed 's/^[0-9]*://; s/-.*//'
}

setup_xen_guest_utilities() {
    info "Installing/Updating XEN Guest Utilities..."

    # Primary method: ISO installation (per XCP-NG docs)
    # https://docs.xcp-ng.org/vms/#linux-guest-tools

    # Check for existing installations and optionally remove them
    if pkg_check_installed xe-guest-utilities; then
        local ver
        ver=$(pkg_get_version xe-guest-utilities)
        info "xe-guest-utilities is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xe-guest-utilities (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y)
                info "Uninstalling existing xe-guest-utilities..."
                pkg_remove xe-guest-utilities || warn "Failed to remove xe-guest-utilities."
                ;;
            *)
                info "Keeping existing xe-guest-utilities."
                ;;
        esac
    fi

    if pkg_check_installed xen-guest-agent; then
        local ver
        ver=$(pkg_get_version xen-guest-agent)
        info "xen-guest-agent is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xen-guest-agent (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y)
                info "Uninstalling existing xen-guest-agent..."
                pkg_remove xen-guest-agent || warn "Failed to remove xen-guest-agent."
                ;;
            *)
                info "Keeping existing xen-guest-agent."
                ;;
        esac
    fi

    # Mount the guest tools ISO (per XCP-NG docs: mount /dev/cdrom /mnt)
    local MOUNT_POINT="/mnt"
    if ! mountpoint -q "${MOUNT_POINT}"; then
        info "Attempting to mount guest tools ISO..."
        if ! sudo mount /dev/cdrom "${MOUNT_POINT}"; then
            warn "Could not mount /dev/cdrom to ${MOUNT_POINT}."
            warn "Please ensure the XCP-NG guest tools ISO is inserted in the VM's CD drive."
            echo ""
            read -n 1 -rp "Would you like to retry mounting? [y/N] " retry_ans
            echo
            if [[ "$retry_ans" =~ ^[Yy]$ ]]; then
                if ! sudo mount /dev/cdrom "${MOUNT_POINT}"; then
                    warn "Mount failed again. Falling back to repository installation..."
                    _install_from_repository
                    return $?
                fi
            else
                info "Falling back to repository installation..."
                _install_from_repository
                return $?
            fi
        fi
    fi

    if [[ -f "${MOUNT_POINT}/Linux/install.sh" ]]; then
        info "Running XCP-NG installer script from ISO..."

        # The install.sh script auto-detects Debian, CentOS, RHEL, SLES, and Ubuntu.
        # For derived distros, force detection with: -d $DISTRO -m $MAJOR_VERSION
        # See: https://docs.xcp-ng.org/vms/#linux-guest-tools
        local install_flags=""
        local major_ver="${DISTRO_VERSION_ID%%.*}"

        case "$DISTRO_FAMILY" in
            debian)
                # The ISO installer only recognises "ubuntu" and "debian" by name.
                # Ubuntu derivatives (KDE Neon, Kubuntu, etc.) must be forced to
                # install as ubuntu so the installer doesn't reject them.
                case "$DISTRO_ID" in
                    ubuntu|debian)
                        install_flags=""
                        ;;
                    *)
                        install_flags="-d ubuntu -m ${major_ver}"
                        ;;
                esac
                ;;
            rhel)
                # RHEL derivatives need explicit distro flags
                install_flags="-d rhel -m ${major_ver}"
                ;;
            fedora)
                install_flags="-d fedora -m ${major_ver}"
                ;;
            *)
                # For unsupported distros, try without flags first
                warn "Distro '${DISTRO_NAME}' may not be recognized by the ISO installer."
                warn "Attempting install without distro flags. If it fails, manual extraction may be needed."
                ;;
        esac

        [[ -n "$install_flags" ]] && info "Using installer flags: ${install_flags}"

        # Run the installer (per docs: bash /mnt/Linux/install.sh)
        if sudo bash "${MOUNT_POINT}/Linux/install.sh" ${install_flags}; then
            # Per XCP-NG docs: no reboot needed (old message from kernel module era)
            sudo umount /dev/cdrom 2>/dev/null || warn "Failed to unmount ${MOUNT_POINT}"
            if _verify_xen_services; then
                info "XCP-NG Guest Tools installed and services are running."
            else
                warn "XCP-NG Guest Tools installed but services may not be running correctly."
            fi
            return 0
        else
            warn "ISO installer failed. Attempting manual extraction..."
            # For unsupported distros: extract xe-guest-utilities tgz from ISO
            _install_from_iso_tgz "${MOUNT_POINT}"
            local result=$?
            sudo umount /dev/cdrom 2>/dev/null || warn "Failed to unmount ${MOUNT_POINT}"
            if [[ $result -ne 0 ]]; then
                warn "Manual extraction failed. Falling back to repository installation..."
                _install_from_repository
                return $?
            fi
            return 0
        fi
    else
        warn "Installer script not found at ${MOUNT_POINT}/Linux/install.sh."
        sudo umount /dev/cdrom 2>/dev/null || true
        info "Falling back to repository installation..."
        _install_from_repository
        return $?
    fi
}

# Extract xe-guest-utilities tgz from the ISO for unsupported distros.
# Per XCP-NG docs: extract the xe-guest-utilities_*_all.tgz archive,
# copy contents to /etc and /usr, and use the included systemd unit file.
_install_from_iso_tgz() {
    local mount_point="$1"
    local tgz_file
    tgz_file=$(find "${mount_point}/Linux/" -name 'xe-guest-utilities_*_all.tgz' 2>/dev/null | head -1)

    if [[ -z "$tgz_file" ]]; then
        warn "No xe-guest-utilities tgz archive found on ISO."
        return 1
    fi

    info "Extracting ${tgz_file}..."
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/xen-guest-tools-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")

    if ! tar -xzf "$tgz_file" -C "$tmp_dir"; then
        warn "Failed to extract tgz archive."
        return 1
    fi

    # Copy extracted files to system directories
    if [[ -d "${tmp_dir}/etc" ]]; then
        sudo cp -a "${tmp_dir}/etc/." /etc/ || warn "Failed to copy /etc files"
    fi
    if [[ -d "${tmp_dir}/usr" ]]; then
        sudo cp -a "${tmp_dir}/usr/." /usr/ || warn "Failed to copy /usr files"
    fi

    # Enable and start the service
    if [[ -f /etc/systemd/system/xe-linux-distribution.service ]] || \
       [[ -f /usr/lib/systemd/system/xe-linux-distribution.service ]]; then
        sudo systemctl daemon-reload
        sudo systemctl enable xe-linux-distribution || warn "Failed to enable xe-linux-distribution"
        sudo systemctl start xe-linux-distribution || warn "Failed to start xe-linux-distribution"
        if _verify_xen_services; then
            info "XEN Guest Utilities installed via manual extraction and services are running."
        else
            warn "XEN Guest Utilities installed via manual extraction but services may not be running correctly."
        fi
    elif [[ -f /etc/init.d/xe-linux-distribution ]]; then
        sudo /etc/init.d/xe-linux-distribution start || warn "Failed to start xe-linux-distribution"
        info "XEN Guest Utilities installed via manual extraction (init.d)."
        warn "Cannot verify init.d service status automatically."
    else
        warn "No systemd unit or init script found. Service may need manual configuration."
    fi

    return 0
}

# Verify that the xe-linux-distribution service is running after installation.
_verify_xen_services() {
    local svc="xe-linux-distribution"
    local max_attempts=6
    local wait_seconds=5

    info "Verifying ${svc} service started..."
    local attempt=0
    while (( attempt < max_attempts )); do
        if systemctl is-active --quiet "${svc}"; then
            info "${svc} service is running."
            return 0
        fi
        (( attempt++ ))
        if (( attempt < max_attempts )); then
            sleep "$wait_seconds"
        fi
    done

    warn "${svc} service failed to start within $(( max_attempts * wait_seconds )) seconds."
    warn "Service status:"
    systemctl status "${svc}" --no-pager 2>&1 | head -20
    return 1
}

# Helper function: Install XEN utilities from repository (fallback method)
_install_from_repository() {
    info "Attempting repository installation..."

    case "$DISTRO_FAMILY" in
        debian)
            info "Installing xe-guest-utilities via apt..."
            if run_as_root "apt-get update && apt-get install -y xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        fedora|rhel)
            run_as_root "yum install -y epel-release" 2>/dev/null || true
            info "Installing xe-guest-utilities via yum..."
            if run_as_root "yum install -y xe-guest-utilities-latest" 2>/dev/null || \
               run_as_root "yum install -y xe-guest-utilities"; then
                run_as_root "systemctl enable xe-linux-distribution" || warn "Failed to enable xe-linux-distribution"
                run_as_root "systemctl start xe-linux-distribution" || warn "Failed to start xe-linux-distribution"
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        arch)
            info "Installing xe-guest-utilities via pacman..."
            if run_as_root "pacman -S --noconfirm xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        suse)
            info "Installing xe-guest-utilities via zypper..."
            if run_as_root "zypper install -y xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        alpine)
            info "Installing xe-guest-utilities via apk..."
            if run_as_root "apk add -X http://dl-cdn.alpinelinux.org/alpine/edge/community xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        *)
            error "Repository installation not supported for ${DISTRO_NAME}"
            return 1
            ;;
    esac
}
