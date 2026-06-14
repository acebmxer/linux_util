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
        if [[ ! -x "$_limine_bin" ]]; then
            error "Limine binary not found. Install Limine from the Bootloaders menu first."
            return 1
        fi
        sudo "$_limine_bin" bios-install "$_disk"
        info "Limine deployed to ${_disk}."
    else
        local _esp=""
        for _dir in /boot/efi /efi /boot; do
            mountpoint -q "$_dir" 2>/dev/null && { _esp="$_dir"; break; }
        done
        if [[ -z "$_esp" ]]; then
            warn "Could not detect ESP. Copy Limine EFI files from ${_LIMINE_INSTALL_DIR}/ to your ESP manually."
            return 1
        fi
        sudo mkdir -p "${_esp}/EFI/LIMINE"
        sudo cp "${_LIMINE_INSTALL_DIR}/BOOTX64.EFI"        "${_esp}/EFI/LIMINE/" 2>/dev/null || true
        sudo cp "${_LIMINE_INSTALL_DIR}/limine-uefi-cd.bin" "${_esp}/EFI/LIMINE/" 2>/dev/null || true
        if command -v efibootmgr &>/dev/null; then
            local _esp_disk _esp_part
            _esp_disk=$(findmnt -n -o SOURCE "$_esp" | sed 's/[0-9]*$//')
            _esp_part=$(findmnt -n -o SOURCE "$_esp" | grep -oP '[0-9]+$')
            sudo efibootmgr --create --disk "$_esp_disk" --part "$_esp_part" \
                --label "Limine" --loader "\\EFI\\LIMINE\\BOOTX64.EFI" 2>/dev/null || true
        fi
        info "Limine EFI files installed to ${_esp}/EFI/LIMINE/."
    fi
}

_deploy_systemd_boot() {
    if [[ ! -d /sys/firmware/efi ]]; then
        error "systemd-boot only supports UEFI systems."; return 1
    fi
    sudo bootctl install 2>/dev/null || sudo bootctl update 2>/dev/null || true
    info "systemd-boot installed as the EFI default."
}

# ── Switch Bootloader ─────────────────────────────────────────────────────────

check_switch_bootloader() { return 0; }

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

    local -a _names=("GRUB" "Limine" "systemd-boot")
    local -a _keys=("grub" "limine" "systemd-boot")

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
    for _f in "/boot/limine.conf" "/boot/efi/limine.conf" "${_LIMINE_INSTALL_DIR}/limine.conf"; do
        [[ -f "$_f" ]] && { _limine_conf="$_f"; break; }
    done

    while true; do
        local _conf_label="${_limine_conf:-not found}"
        echo "  Limine options:"
        echo ""
        echo "    1) Edit limine.conf (${_conf_label})"
        echo "    2) Redeploy to disk (BIOS: limine bios-install)"
        echo "    3) Show installed Limine files"
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
            0)
                return 0 ;;
            *)
                echo "${RED}  Invalid selection.${RESET}"
                ;;
        esac
        echo ""
    done
}
