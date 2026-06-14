#!/bin/bash
# Bootloader management tasks — detect active bootloader, switch, and configure

# ── internal helpers ──────────────────────────────────────────────────────────

_detect_current_bootloader() {
    # UEFI: match the currently-booted EFI entry by name
    if [[ -d /sys/firmware/efi ]] && command -v efibootmgr &>/dev/null; then
        local current entry
        current=$(efibootmgr 2>/dev/null | awk '/^BootCurrent:/{print $2}')
        if [[ -n "$current" ]]; then
            entry=$(efibootmgr 2>/dev/null | grep -i "^Boot${current}\*" | tr '[:upper:]' '[:lower:]')
            [[ "$entry" == *"grub"* ]]   && { echo "grub";         return; }
            [[ "$entry" == *"limine"* ]] && { echo "limine";       return; }
            [[ "$entry" == *"linux boot manager"* || "$entry" == *"systemd-boot"* ]] && \
                                            { echo "systemd-boot"; return; }
        fi
    fi
    # Fall back to checking what is installed / responding
    bootctl is-installed &>/dev/null 2>&1 && { echo "systemd-boot"; return; }
    { command -v grub-install &>/dev/null || command -v grub2-install &>/dev/null; } \
        && { echo "grub"; return; }
    { [[ -f "${_LIMINE_INSTALL_DIR}/limine" ]]      ||
      command -v limine &>/dev/null                ||
      [[ -f "${_LIMINE_INSTALL_DIR}/BOOTX64.EFI" ]] ||
      [[ -f "${_LIMINE_INSTALL_DIR}/limine-uefi-cd.bin" ]]; } \
        && { echo "limine"; return; }
    echo "unknown"
}

_bl_display_name() {
    case "$1" in
        grub)         echo "GRUB" ;;
        limine)       echo "Limine" ;;
        systemd-boot) echo "systemd-boot" ;;
        *)            echo "Unknown" ;;
    esac
}

_regenerate_grub_config() {
    if command -v update-grub &>/dev/null; then
        sudo update-grub
    elif command -v grub2-mkconfig &>/dev/null; then
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    elif command -v grub-mkconfig &>/dev/null; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
        warn "No GRUB config generator found."
    fi
}

# ── config-generation helpers (shared) ───────────────────────────────────────
#
# When switching bootloaders we must give the newly-activated one a working
# menu, otherwise it boots into an empty config. Bootloader config formats are
# not interchangeable, so instead of copying the old config we synthesise a
# native one from the system's actual state: installed kernels in /boot plus the
# currently-booted kernel command line (/proc/cmdline), which already contains a
# known-good root= and the rest of the boot args.

# _kernel_cmdline echoes the active kernel cmdline with the bootloader-injected
# BOOT_IMAGE= and initrd= tokens removed (those are loader-specific).
_kernel_cmdline() {
    tr ' ' '\n' < /proc/cmdline \
        | grep -vE '^(BOOT_IMAGE|initrd)=' \
        | tr '\n' ' ' \
        | sed 's/ *$//'
}

# _fs_uuid_for echoes the filesystem UUID of the partition backing a path.
_fs_uuid_for() { findmnt -no UUID --target "$1" 2>/dev/null; }

# _rel_to_mount echoes a path relative to the mountpoint of the fs holding it,
# e.g. /boot/vmlinuz-linux on a separate /boot -> /vmlinuz-linux.
_rel_to_mount() {
    local _p="$1" _mp
    _mp=$(findmnt -no TARGET --target "$_p" 2>/dev/null)
    if [[ -z "$_mp" || "$_mp" == "/" ]]; then
        echo "$_p"
    else
        echo "/${_p#"$_mp"/}"
    fi
}

# _vol_path echoes a path as a loader sees it from the volume's top level.
# Limine resolves uuid(...) to the filesystem's top-level subvolume (subvolid 5
# on btrfs), not the subvolume currently mounted. Ubuntu/Kubuntu mount root from
# the "@" subvolume, so the kernel that lives at /boot/vmlinuz is really at
# /@/boot/vmlinuz from the volume root. We reconstruct that by joining FSROOT
# (the subvolume path, "/@" etc.; "/" for a plain fs/partition) with the path
# relative to the mountpoint. On ext4 this is identical to _rel_to_mount.
_vol_path() {
    local _p="$1" _fsroot _rel
    _fsroot=$(findmnt -no FSROOT --target "$_p" 2>/dev/null)
    _rel=$(_rel_to_mount "$_p")
    if [[ -z "$_fsroot" || "$_fsroot" == "/" ]]; then
        echo "$_rel"
    else
        echo "${_fsroot%/}${_rel}"
    fi
}

# _discover_kernels emits "vmlinuz_path|initrd_path|label" lines for each kernel
# image found in /boot, matching the distro's initramfs naming.
_discover_kernels() {
    local _k _base _suffix _initrd _cand _label
    for _k in /boot/vmlinuz-* /boot/vmlinuz; do
        [[ -f "$_k" ]] || continue
        _base=$(basename "$_k")
        _suffix="${_base#vmlinuz-}"
        [[ "$_suffix" == "vmlinuz" ]] && _suffix=""
        _initrd=""
        for _cand in \
            "/boot/initramfs-${_suffix}.img" \
            "/boot/initrd.img-${_suffix}" \
            "/boot/initramfs-${_suffix}" \
            "/boot/initrd-${_suffix}.img"; do
            [[ -f "$_cand" ]] && { _initrd="$_cand"; break; }
        done
        _label="${_suffix:-Linux}"
        printf '%s|%s|%s\n' "$_k" "$_initrd" "$_label"
    done
}

# _rebuild_initramfs builds an initramfs/initramdisk for one kernel version using
# the distro's native generator. The version string is the module directory name
# (the suffix after vmlinuz-, e.g. 7.1.0-070100rc7-generic).
_rebuild_initramfs() {
    local _ver="$1"
    case "$DISTRO_FAMILY" in
        debian)
            sudo update-initramfs -c -k "$_ver" ;;
        fedora|rhel|suse)
            sudo dracut --force "/boot/initramfs-${_ver}.img" "$_ver" ;;
        arch)
            if command -v mkinitcpio &>/dev/null; then
                sudo mkinitcpio -g "/boot/initramfs-${_ver}.img" -k "$_ver"
            elif command -v dracut &>/dev/null; then
                sudo dracut --force "/boot/initramfs-${_ver}.img" "$_ver"
            else
                warn "No initramfs generator (mkinitcpio or dracut) found."; return 1
            fi ;;
        *)
            warn "Unknown distro family; cannot rebuild initramfs automatically."; return 1 ;;
    esac
}

# _repair_missing_initramfs finds installed kernels in /boot that have no matching
# initramfs and rebuilds it, then regenerates the active bootloader's config so
# the recovered kernels reappear in the menu. This fixes kernels installed without
# an initramfs (e.g. some mainline .deb packages), which a bootloader otherwise
# silently drops — exactly the case where a freshly installed kernel never shows.
_repair_missing_initramfs() {
    local _vmlinuz _initrd _label
    local -a _to_fix=()
    while IFS='|' read -r _vmlinuz _initrd _label; do
        [[ -f "$_vmlinuz" ]] || continue
        # Skip the bare /boot/vmlinuz symlink (no version → can't name an initramfs).
        [[ "$_label" == "Linux" ]] && continue
        [[ -z "$_initrd" ]] && _to_fix+=("$_label")
    done < <(_discover_kernels)

    if (( ${#_to_fix[@]} == 0 )); then
        info "All installed kernels already have a matching initramfs."
        return 0
    fi

    warn "Found ${#_to_fix[@]} kernel(s) in /boot with no initramfs:"
    local _ver
    for _ver in "${_to_fix[@]}"; do echo "    - ${_ver}"; done
    echo ""
    warn "Without an initramfs the bootloader silently drops these kernels from its menu."
    echo ""

    local _go
    while true; do
        read -n 1 -rp "  Rebuild initramfs for the above kernel(s)? (Y/n) " _go < /dev/tty; echo ""
        [[ $'\e' == "$_go" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
        _go="${_go:-Y}"
        case "$_go" in
            y|Y) break ;;
            n|N) info "No changes made."; return 0 ;;
            *) echo "  Please press Y or N." ;;
        esac
    done

    local _fixed=0
    for _ver in "${_to_fix[@]}"; do
        info "Rebuilding initramfs for ${_ver}..."
        if _rebuild_initramfs "$_ver"; then
            ((_fixed++))
        else
            warn "Failed to build initramfs for ${_ver}."
        fi
    done
    info "Rebuilt ${_fixed}/${#_to_fix[@]} initramfs image(s)."

    if (( _fixed > 0 )); then
        info "Regenerating the active bootloader's config..."
        case "$(_detect_current_bootloader)" in
            grub)         _regenerate_grub_config ;;
            limine)       _generate_limine_config ;;
            systemd-boot) _generate_systemd_boot_config ;;
            *)            warn "Could not detect the active bootloader; regenerate its config manually." ;;
        esac
    fi
}

# _generate_limine_config gives a freshly-deployed Limine a working menu.
_generate_limine_config() {
    # Prefer a distro-native generator when one is installed.
    if command -v limine-update &>/dev/null; then
        info "Generating Limine config via limine-update..."
        sudo limine-update && return 0
        warn "limine-update failed; falling back to a generated config."
    elif command -v limine-mkconfig &>/dev/null; then
        info "Generating Limine config via limine-mkconfig..."
        sudo limine-mkconfig -o /boot/limine.conf && return 0
        warn "limine-mkconfig failed; falling back to a generated config."
    fi

    local _conf_path
    if [[ -d /sys/firmware/efi ]]; then
        local _esp="" _dir
        for _dir in /boot/efi /efi /boot; do
            mountpoint -q "$_dir" 2>/dev/null && { _esp="$_dir"; break; }
        done
        [[ -z "$_esp" ]] && { warn "Could not detect ESP; skipping Limine config generation."; return 1; }
        _conf_path="${_esp}/limine.conf"
    else
        _conf_path="/boot/limine.conf"
    fi

    if [[ -f "$_conf_path" ]]; then
        info "Existing Limine config at ${_conf_path}; leaving it untouched."
        return 0
    fi

    local _cmdline _tmp _count=0
    _cmdline=$(_kernel_cmdline)
    _tmp=$(mktemp)
    printf 'timeout: 5\n\n' > "$_tmp"

    local _vmlinuz _initrd _label _kuuid _kpath _iuuid _ipath
    while IFS='|' read -r _vmlinuz _initrd _label; do
        [[ -f "$_vmlinuz" ]] || continue
        _kuuid=$(_fs_uuid_for "$_vmlinuz"); _kpath=$(_vol_path "$_vmlinuz")
        {
            echo "/${_label}"
            echo "    protocol: linux"
            if [[ -n "$_kuuid" ]]; then
                echo "    kernel_path: uuid(${_kuuid}):${_kpath}"
            else
                echo "    kernel_path: boot():${_kpath}"
            fi
            echo "    cmdline: ${_cmdline}"
            if [[ -n "$_initrd" ]]; then
                _iuuid=$(_fs_uuid_for "$_initrd"); _ipath=$(_vol_path "$_initrd")
                if [[ -n "$_iuuid" ]]; then
                    echo "    module_path: uuid(${_iuuid}):${_ipath}"
                else
                    echo "    module_path: boot():${_ipath}"
                fi
            fi
            echo ""
        } >> "$_tmp"
        ((_count++))
    done < <(_discover_kernels)

    if (( _count == 0 )); then
        warn "No kernels found in /boot; could not generate a Limine config."
        rm -f "$_tmp"; return 1
    fi

    sudo cp "$_tmp" "$_conf_path"; rm -f "$_tmp"
    info "Generated Limine config at ${_conf_path} (${_count} entries)."
    warn "Review it and confirm it boots before removing your old bootloader."
}

# _ensure_loader_conf writes a minimal systemd-boot loader.conf if none exists.
_ensure_loader_conf() {
    local _conf="$1"
    [[ -f "$_conf" ]] && return 0
    sudo mkdir -p "$(dirname "$_conf")"
    printf 'timeout 5\nconsole-mode keep\n' | sudo tee "$_conf" > /dev/null
    info "Created ${_conf}."
}

# _generate_systemd_boot_config gives a freshly-installed systemd-boot a menu.
_generate_systemd_boot_config() {
    local _esp="" _dir
    for _dir in /boot/efi /efi /boot; do
        mountpoint -q "$_dir" 2>/dev/null && { _esp="$_dir"; break; }
    done
    [[ -z "$_esp" ]] && { warn "Could not detect ESP; skipping systemd-boot config generation."; return 1; }

    # Prefer kernel-install: it understands XBOOTLDR, the distro's initramfs
    # generator, and the correct ESP layout.
    if command -v kernel-install &>/dev/null; then
        info "Generating systemd-boot entries via kernel-install..."
        local _ok=false _ver _img
        for _img in /lib/modules/*/vmlinuz /usr/lib/modules/*/vmlinuz; do
            [[ -f "$_img" ]] || continue
            _ver=$(basename "$(dirname "$_img")")
            sudo kernel-install add "$_ver" "$_img" &>/dev/null && _ok=true
        done
        if [[ "$_ok" == true ]]; then
            _ensure_loader_conf "${_esp}/loader/loader.conf"
            info "systemd-boot entries generated via kernel-install."
            return 0
        fi
        warn "kernel-install produced no entries; falling back to manual generation."
    fi

    # Fallback: write loader entries by hand. systemd-boot can only read kernels
    # from the ESP (or an XBOOTLDR partition), so skip kernels living elsewhere.
    local _entries_dir="${_esp}/loader/entries" _esp_src _cmdline _count=0
    sudo mkdir -p "$_entries_dir"
    _esp_src=$(findmnt -no SOURCE "$_esp" 2>/dev/null)
    _cmdline=$(_kernel_cmdline)

    local _vmlinuz _initrd _label _ksrc _id _krel _irel
    while IFS='|' read -r _vmlinuz _initrd _label; do
        [[ -f "$_vmlinuz" ]] || continue
        _ksrc=$(findmnt -no SOURCE --target "$_vmlinuz" 2>/dev/null)
        if [[ "$_ksrc" != "$_esp_src" ]]; then
            warn "Kernel ${_vmlinuz} is not on the ESP; systemd-boot needs XBOOTLDR for it. Skipping."
            continue
        fi
        _id="linux-${_label}"; _id="${_id//[^A-Za-z0-9_.-]/_}"
        _krel=$(_rel_to_mount "$_vmlinuz")
        {
            echo "title ${_label}"
            echo "linux ${_krel}"
            [[ -n "$_initrd" ]] && { _irel=$(_rel_to_mount "$_initrd"); echo "initrd ${_irel}"; }
            echo "options ${_cmdline}"
        } | sudo tee "${_entries_dir}/${_id}.conf" > /dev/null
        ((_count++))
    done < <(_discover_kernels)

    if (( _count == 0 )); then
        warn "No bootable kernels found on the ESP; no systemd-boot entries were generated."
        warn "Put kernels on ${_esp} (or set up XBOOTLDR / use kernel-install) and retry."
        return 1
    fi

    _ensure_loader_conf "${_esp}/loader/loader.conf"
    info "Generated ${_count} systemd-boot entries in ${_entries_dir}."
    warn "Review them and confirm they boot before removing your old bootloader."
}

_deploy_grub() {
    local _tool
    command -v grub-install &>/dev/null && _tool="grub-install" || _tool="grub2-install"
    if [[ -d /sys/firmware/efi ]]; then
        sudo "$_tool" --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    else
        echo ""
        echo "  BIOS system detected. Enter the target disk (e.g. /dev/sda):"
        local _disk
        read -rp "  Disk: " _disk < /dev/tty
        if [[ ! -b "$_disk" ]]; then
            error "${_disk} is not a valid block device."; return 1
        fi
        sudo "$_tool" "$_disk"
    fi
    _regenerate_grub_config
}

_deploy_limine() {
    local _limine_bin="${_LIMINE_INSTALL_DIR}/limine"
    command -v limine &>/dev/null && _limine_bin="limine"

    if [[ ! -d /sys/firmware/efi ]]; then
        echo ""
        echo "  BIOS system detected. Enter the target disk (e.g. /dev/sda):"
        local _disk
        read -rp "  Disk: " _disk < /dev/tty
        if [[ ! -b "$_disk" ]]; then
            error "${_disk} is not a valid block device."; return 1
        fi
        if [[ ! -x "$_limine_bin" && ! -x "${_LIMINE_INSTALL_DIR}/limine" ]]; then
            error "Limine host utility not built (needs gcc/make). Reinstall Limine from the Bootloaders menu first."
            return 1
        fi
        [[ ! -x "$_limine_bin" ]] && _limine_bin="${_LIMINE_INSTALL_DIR}/limine"

        # BIOS Limine reads limine-bios.sys and limine.conf from a filesystem at
        # boot. _generate_limine_config writes /boot/limine.conf, so stage the
        # BIOS blob in /boot too (one of Limine's search directories).
        local _stage="${_LIMINE_INSTALL_DIR}/limine-bios.sys"
        if [[ ! -f "$_stage" ]]; then
            error "limine-bios.sys missing from ${_LIMINE_INSTALL_DIR}; reinstall Limine."
            return 1
        fi
        if ! sudo cp "$_stage" /boot/limine-bios.sys; then
            error "Failed to copy limine-bios.sys to /boot."; return 1
        fi

        # On a GPT disk, bios-install needs the 1-based number of a BIOS-boot
        # partition (type ef02). Detect it; warn if the disk is GPT without one.
        local _pttype _biospart="" _pn _pt
        _pttype=$(sudo blkid -o value -s PTTYPE "$_disk" 2>/dev/null)
        if [[ "$_pttype" == "gpt" ]]; then
            while read -r _pn _pt; do
                [[ "${_pt,,}" == "21686148-6449-6e6f-744e-656564454649" ]] && { _biospart="$_pn"; break; }
            done < <(lsblk -rno PARTN,PARTTYPE "$_disk" 2>/dev/null)
            if [[ -z "$_biospart" ]]; then
                warn "${_disk} is GPT but has no BIOS-boot partition (type ef02)."
                warn "Create a ~1MiB ef02 partition first, or Limine BIOS install will fail."
            fi
        fi

        if ! sudo "$_limine_bin" bios-install "$_disk" ${_biospart:+"$_biospart"}; then
            error "limine bios-install failed on ${_disk}."; return 1
        fi
        info "Limine deployed to ${_disk}."
        _generate_limine_config
    else
        local _esp=""
        for _dir in /boot/efi /efi /boot; do
            mountpoint -q "$_dir" 2>/dev/null && { _esp="$_dir"; break; }
        done
        if [[ -z "$_esp" ]]; then
            warn "Could not detect ESP. Copy Limine EFI files from ${_LIMINE_INSTALL_DIR}/ to your ESP manually."
            return 1
        fi
        local _src_efi="${_LIMINE_INSTALL_DIR}/BOOTX64.EFI"
        if [[ ! -f "$_src_efi" ]]; then
            error "Limine EFI binary not found at ${_src_efi}. Install Limine from the Bootloaders menu first."
            return 1
        fi

        sudo mkdir -p "${_esp}/EFI/LIMINE" || { error "Could not create ${_esp}/EFI/LIMINE."; return 1; }
        if ! sudo cp "$_src_efi" "${_esp}/EFI/LIMINE/"; then
            error "Failed to copy Limine EFI binary to the ESP."; return 1
        fi
        sudo cp "${_LIMINE_INSTALL_DIR}/limine-uefi-cd.bin" "${_esp}/EFI/LIMINE/" 2>/dev/null || true

        if ! command -v efibootmgr &>/dev/null; then
            warn "efibootmgr not found — Limine files copied but no EFI boot entry was created."
            return 1
        fi

        # Derive the ESP's parent disk and partition number robustly. The old
        # sed/grep approach broke on NVMe (/dev/nvme0n1p1 -> /dev/nvme0n1p),
        # which made efibootmgr fail and silently skip creating the entry.
        local _esp_src _esp_disk _esp_part
        _esp_src=$(findmnt -n -o SOURCE "$_esp")
        _esp_disk="/dev/$(lsblk -no PKNAME "$_esp_src" 2>/dev/null | tr -d '[:space:]')"
        _esp_part=$(lsblk -no PARTN "$_esp_src" 2>/dev/null | tr -d '[:space:]')
        if [[ "$_esp_disk" == "/dev/" || -z "$_esp_part" ]]; then
            error "Could not determine ESP disk/partition for ${_esp_src}."; return 1
        fi

        # Remove stale Limine entries so repeated switches don't stack duplicates.
        local _old
        for _old in $(efibootmgr | awk '$2 == "Limine" {gsub(/[^0-9]/,"",$1); print $1}'); do
            sudo efibootmgr --delete-bootnum --bootnum "$_old" &>/dev/null || true
        done

        if ! sudo efibootmgr --create --disk "$_esp_disk" --part "$_esp_part" \
                --label "Limine" --loader "\\EFI\\LIMINE\\BOOTX64.EFI"; then
            error "Failed to register Limine in the EFI boot menu (efibootmgr)."
            return 1
        fi
        info "Limine EFI files installed to ${_esp}/EFI/LIMINE/ and registered in the EFI boot menu."
        _generate_limine_config
    fi
}

_deploy_systemd_boot() {
    if [[ ! -d /sys/firmware/efi ]]; then
        error "systemd-boot only supports UEFI systems."; return 1
    fi
    sudo bootctl install 2>/dev/null || sudo bootctl update 2>/dev/null || true
    info "systemd-boot installed as the EFI default."
    _generate_systemd_boot_config
}

# ── Switch Bootloader ─────────────────────────────────────────────────────────
# Registered with check_always_false: it's a run-action, never "installed", so it
# is never offered for uninstall/update. Its current state ("GRUB active", etc.) is
# surfaced via get_version_switch_bootloader instead.

setup_switch_bootloader() {
    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Switch Bootloader                                             ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    local _current
    _current=$(_detect_current_bootloader)
    echo "  Current bootloader: ${BOLD}$(_bl_display_name "$_current")${RESET}"
    echo ""

    # Limine and systemd-boot are not offered on Debian/Ubuntu: neither gets its
    # menu regenerated on kernel updates there, so entries would silently go
    # stale. GRUB is the only integrated choice on the Debian family.
    local -a _names=("GRUB")
    local -a _keys=("grub")
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        _names+=("Limine" "systemd-boot")
        _keys+=("limine" "systemd-boot")
    fi

    echo "  Available bootloaders:"
    echo ""
    local _i
    for ((_i = 0; _i < ${#_names[@]}; _i++)); do
        local _tag=""
        [[ "${_keys[$_i]}" == "$_current" ]] && _tag=" ${GREEN}(current)${RESET}"
        echo "    $((_i + 1))) ${_names[$_i]}${_tag}"
    done
    echo ""
    echo "    0) Cancel"
    echo ""

    local _choice
    while true; do
        read -rp "  Select bootloader to switch to [0-${#_names[@]}]: " _choice < /dev/tty
        [[ "$_choice" == "0" ]] && { echo "${YELLOW}  Cancelled.${RESET}"; return 2; }
        if [[ "$_choice" =~ ^[1-9]$ ]] && (( _choice <= ${#_names[@]} )); then break; fi
        echo "${RED}  Invalid selection.${RESET}"
    done

    local _target_key="${_keys[$((_choice - 1))]}"
    local _target_name="${_names[$((_choice - 1))]}"

    if [[ "$_target_key" == "$_current" ]]; then
        echo ""
        warn "${_target_name} is already your active bootloader."
        return 0
    fi

    echo ""
    echo "${YELLOW}  Warning: switching bootloaders can leave your system unbootable if${RESET}"
    echo "${YELLOW}  done incorrectly. Take a snapshot before proceeding.${RESET}"
    echo ""

    local _confirm
    while true; do
        read -n 1 -rp "  Switch to ${_target_name}? (y/N) " _confirm < /dev/tty; echo ""
        [[ $'\e' == "$_confirm" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
        _confirm="${_confirm:-N}"
        case "$_confirm" in
            y|Y) break ;;
            n|N) echo "${YELLOW}  Cancelled.${RESET}"; return 2 ;;
            *) echo "  Please press Y or N." ;;
        esac
    done

    echo ""
    case "$_target_key" in
        grub)
            check_grub || { info "Installing GRUB..."; install_grub || { error "GRUB installation failed."; return 1; }; }
            _deploy_grub || return 1
            ;;
        limine)
            check_limine || { info "Installing Limine..."; install_limine || { error "Limine installation failed."; return 1; }; }
            _deploy_limine || return 1
            ;;
        systemd-boot)
            check_systemd_boot || { info "Installing systemd-boot..."; install_systemd_boot || { error "systemd-boot installation failed."; return 1; }; }
            _deploy_systemd_boot || return 1
            ;;
    esac

    if [[ "$_current" != "unknown" ]]; then
        echo ""
        local _rm _do_remove=false
        while true; do
            read -n 1 -rp "  Remove the old bootloader ($(_bl_display_name "$_current"))? (y/N) " _rm < /dev/tty; echo ""
            [[ $'\e' == "$_rm" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
            _rm="${_rm:-N}"
            case "$_rm" in
                y|Y) _do_remove=true; break ;;
                n|N) info "Old bootloader kept. Remove it later from the Bootloaders menu."; break ;;
                *) echo "  Please press Y or N." ;;
            esac
        done
        if [[ "$_do_remove" == "true" ]]; then
            case "$_current" in
                grub)         uninstall_grub ;;
                limine)       uninstall_limine ;;
                systemd-boot) uninstall_systemd_boot ;;
            esac
        fi
    fi

    echo ""
    info "${_target_name} is now your active bootloader."
    info "The bootloader display will update after reboot (current session still shows the old entry)."
    echo ""
    local _reboot
    while true; do
        read -n 1 -rp "  Reboot now to activate ${_target_name}? (y/N) " _reboot < /dev/tty; echo ""
        [[ $'\e' == "$_reboot" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
        _reboot="${_reboot:-N}"
        case "$_reboot" in
            y|Y) sudo reboot; return 0 ;;
            n|N) info "Reboot when ready to activate ${_target_name}."; break ;;
            *) echo "  Please press Y or N." ;;
        esac
    done
}

noop_switch_bootloader()    { return 0; }
update_switch_bootloader()  { setup_switch_bootloader; }

get_version_switch_bootloader() {
    local _cur
    _cur=$(_detect_current_bootloader)
    [[ "$_cur" == "unknown" ]] && echo "" || echo "$(_bl_display_name "$_cur") active"
}

# ── Configure Bootloader ──────────────────────────────────────────────────────

check_configure_bootloader() { return 1; }

setup_configure_bootloader() {
    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Configure Bootloader                                          ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    local _current
    _current=$(_detect_current_bootloader)

    if [[ "$_current" == "unknown" ]]; then
        warn "No recognised bootloader detected. Install one from the Bootloaders menu first."
        return 1
    fi

    echo "  Detected bootloader: ${BOLD}$(_bl_display_name "$_current")${RESET}"
    echo ""

    case "$_current" in
        grub)         _configure_grub_menu ;;
        limine)       _configure_limine_menu ;;
        systemd-boot) _configure_systemd_boot_menu ;;
    esac
}

noop_configure_bootloader()    { return 0; }
update_configure_bootloader()  { setup_configure_bootloader; }

get_version_configure_bootloader() {
    local _cur
    _cur=$(_detect_current_bootloader)
    [[ "$_cur" == "unknown" ]] && echo "" || echo "$(_bl_display_name "$_cur")"
}

# ── GRUB configuration menu ───────────────────────────────────────────────────

_configure_grub_menu() {
    local _grub_defaults="/etc/default/grub"

    while true; do
        echo "  GRUB options:"
        echo ""
        echo "    1) Regenerate GRUB config"
        echo "    2) Set boot timeout"
        echo "    3) Edit kernel parameters"
        echo "    4) Edit ${_grub_defaults}"
        echo "    5) Reinstall / redeploy GRUB to disk"
        echo "    6) Rebuild missing initramfs images"
        echo ""
        echo "    0) Done"
        echo ""

        local _c
        read -rp "  Select option: " _c < /dev/tty; echo ""

        case "$_c" in
            1)
                _regenerate_grub_config
                ;;
            2)
                local _cur_t
                _cur_t=$(grep -oP '(?<=^GRUB_TIMEOUT=)\d+' "$_grub_defaults" 2>/dev/null || echo "5")
                echo "  Current timeout: ${_cur_t}s"
                local _new_t
                read -rp "  New timeout in seconds (0 for immediate boot): " _new_t < /dev/tty
                if [[ "$_new_t" =~ ^[0-9]+$ ]]; then
                    sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${_new_t}/" "$_grub_defaults"
                    if ! grep -q "^GRUB_TIMEOUT_STYLE=" "$_grub_defaults"; then
                        echo 'GRUB_TIMEOUT_STYLE=menu' | sudo tee -a "$_grub_defaults" > /dev/null
                    else
                        sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' "$_grub_defaults"
                    fi
                    info "Timeout set to ${_new_t}s. Regenerating GRUB config..."
                    _regenerate_grub_config
                else
                    warn "Invalid value — enter a number of seconds."
                fi
                ;;
            3)
                local _cur_p
                _cur_p=$(grep -oP '(?<=^GRUB_CMDLINE_LINUX_DEFAULT=")[^"]+' "$_grub_defaults" 2>/dev/null \
                         || echo "quiet splash")
                echo "  Current parameters: ${BOLD}${_cur_p}${RESET}"
                echo "  Enter new parameters (leave blank to keep current):"
                local _new_p
                read -rp "  > " _new_p < /dev/tty
                if [[ -n "$_new_p" ]]; then
                    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${_new_p}\"|" \
                        "$_grub_defaults"
                    info "Kernel parameters updated. Regenerating GRUB config..."
                    _regenerate_grub_config
                else
                    info "No changes made."
                fi
                ;;
            4)
                sudo "${EDITOR:-nano}" "$_grub_defaults" < /dev/tty > /dev/tty 2>&1
                local _regen
                while true; do
                    read -n 1 -rp "  Regenerate GRUB config now? (Y/n) " _regen < /dev/tty; echo ""
                    [[ $'\e' == "$_regen" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
                    _regen="${_regen:-Y}"
                    case "$_regen" in
                        y|Y) _regenerate_grub_config; break ;;
                        n|N) break ;;
                        *) echo "  Please press Y or N." ;;
                    esac
                done
                ;;
            5)
                _deploy_grub
                ;;
            6)
                _repair_missing_initramfs
                ;;
            0)
                return 0 ;;
            *)
                echo "${RED}  Invalid selection.${RESET}"
                ;;
        esac
        echo ""
    done
}

# ── Limine configuration menu ─────────────────────────────────────────────────

_configure_limine_menu() {
    local _limine_conf=""
    for _f in "/boot/limine.conf" "/boot/efi/limine.conf" "/efi/limine.conf" "${_LIMINE_INSTALL_DIR}/limine.conf"; do
        [[ -f "$_f" ]] && { _limine_conf="$_f"; break; }
    done

    while true; do
        local _conf_label="${_limine_conf:-not found}"
        echo "  Limine options:"
        echo ""
        echo "    1) Edit limine.conf (${_conf_label})"
        echo "    2) Redeploy to disk (BIOS: limine bios-install)"
        echo "    3) Show installed Limine files"
        echo "    4) Rebuild missing initramfs images"
        echo ""
        echo "    0) Done"
        echo ""

        local _c
        read -rp "  Select option: " _c < /dev/tty; echo ""

        case "$_c" in
            1)
                if [[ -z "$_limine_conf" ]]; then
                    echo "  limine.conf not found in standard locations."
                    read -rp "  Enter full path: " _limine_conf < /dev/tty
                fi
                if [[ -f "$_limine_conf" ]]; then
                    sudo "${EDITOR:-nano}" "$_limine_conf" < /dev/tty > /dev/tty 2>&1
                else
                    warn "File not found: ${_limine_conf}"
                    _limine_conf=""
                fi
                ;;
            2)
                _deploy_limine
                ;;
            3)
                echo "  Files in ${_LIMINE_INSTALL_DIR}:"
                ls -lh "$_LIMINE_INSTALL_DIR" 2>/dev/null || warn "Directory not found: ${_LIMINE_INSTALL_DIR}"
                ;;
            4)
                _repair_missing_initramfs
                ;;
            0)
                return 0 ;;
            *)
                echo "${RED}  Invalid selection.${RESET}"
                ;;
        esac
        echo ""
    done
}

# ── systemd-boot configuration menu ──────────────────────────────────────────

_configure_systemd_boot_menu() {
    local _esp=""
    for _dir in /boot/efi /efi /boot; do
        mountpoint -q "$_dir" 2>/dev/null && { _esp="$_dir"; break; }
    done
    local _loader_conf="${_esp}/loader/loader.conf"
    local _entries_dir="${_esp}/loader/entries"

    while true; do
        echo "  systemd-boot options:"
        echo ""
        echo "    1) Show boot status (bootctl status)"
        echo "    2) Edit loader.conf"
        echo "    3) Set default boot entry"
        echo "    4) Set boot timeout"
        echo "    5) List boot entries"
        echo "    6) Update systemd-boot (bootctl update)"
        echo "    7) Rebuild missing initramfs images"
        echo ""
        echo "    0) Done"
        echo ""

        local _c
        read -rp "  Select option: " _c < /dev/tty; echo ""

        case "$_c" in
            1)
                sudo bootctl status 2>/dev/null | head -60 || warn "bootctl not available."
                ;;
            2)
                if [[ -f "$_loader_conf" ]]; then
                    sudo "${EDITOR:-nano}" "$_loader_conf" < /dev/tty > /dev/tty 2>&1
                else
                    warn "loader.conf not found at ${_loader_conf}."
                fi
                ;;
            3)
                local -a _entries=()
                if [[ -d "$_entries_dir" ]]; then
                    while IFS= read -r _f; do
                        _entries+=("$(basename "${_f%.conf}")")
                    done < <(find "$_entries_dir" -name "*.conf" | sort)
                fi
                if [[ ${#_entries[@]} -eq 0 ]]; then
                    warn "No boot entries found in ${_entries_dir}."
                else
                    local _i=1
                    for _e in "${_entries[@]}"; do
                        echo "    ${_i}) ${_e}"; ((_i++))
                    done
                    echo ""
                    local _echoice
                    read -rp "  Select default entry [1-${#_entries[@]}]: " _echoice < /dev/tty
                    if [[ "$_echoice" =~ ^[0-9]+$ ]] && (( _echoice >= 1 && _echoice <= ${#_entries[@]} )); then
                        local _sel="${_entries[$((_echoice - 1))]}"
                        if grep -q "^default " "$_loader_conf" 2>/dev/null; then
                            sudo sed -i "s|^default .*|default ${_sel}.conf|" "$_loader_conf"
                        else
                            echo "default ${_sel}.conf" | sudo tee -a "$_loader_conf" > /dev/null
                        fi
                        info "Default entry set to: ${_sel}"
                    else
                        warn "Invalid selection."
                    fi
                fi
                ;;
            4)
                local _cur_t
                _cur_t=$(grep -oP '(?<=^timeout )\S+' "$_loader_conf" 2>/dev/null || echo "not set")
                echo "  Current timeout: ${_cur_t}"
                local _new_t
                read -rp "  New timeout (seconds, 0 for immediate, 'menu' to always show): " _new_t < /dev/tty
                if [[ -n "$_new_t" ]]; then
                    if grep -q "^timeout " "$_loader_conf" 2>/dev/null; then
                        sudo sed -i "s|^timeout .*|timeout ${_new_t}|" "$_loader_conf"
                    else
                        echo "timeout ${_new_t}" | sudo tee -a "$_loader_conf" > /dev/null
                    fi
                    info "Timeout set to: ${_new_t}"
                fi
                ;;
            5)
                if [[ -d "$_entries_dir" ]]; then
                    for _f in "${_entries_dir}"/*.conf; do
                        [[ -f "$_f" ]] || continue
                        echo "  ── $(basename "$_f") ──"
                        grep -E "^(title|linux|initrd|options|efi)" "$_f" 2>/dev/null | sed 's/^/    /'
                        echo ""
                    done
                else
                    warn "Entries directory not found: ${_entries_dir}"
                fi
                ;;
            6)
                sudo bootctl update && info "systemd-boot updated." || warn "bootctl update failed."
                ;;
            7)
                _repair_missing_initramfs
                ;;
            0)
                return 0 ;;
            *)
                echo "${RED}  Invalid selection.${RESET}"
                ;;
        esac
        echo ""
    done
}
