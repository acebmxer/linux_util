#!/bin/bash
# Fix GRUB on BTRFS — sets GRUB_RECORDFAIL_TIMEOUT=0 in /etc/default/grub
# to prevent GRUB from waiting indefinitely on recordfail when using BTRFS.

readonly _GRUB_DEFAULT="/etc/default/grub"
readonly _GRUB_BTRFS_SETTING="GRUB_RECORDFAIL_TIMEOUT=0"

check_fix_grub_btrfs() {
    [[ -f "$_GRUB_DEFAULT" ]] && grep -qx "$_GRUB_BTRFS_SETTING" "$_GRUB_DEFAULT"
}

install_fix_grub_btrfs() {
    info "Applying GRUB BTRFS fix..."

    if [[ ! -f "$_GRUB_DEFAULT" ]]; then
        warn "/etc/default/grub not found — is GRUB installed?"
        return 1
    fi

    if grep -qx "$_GRUB_BTRFS_SETTING" "$_GRUB_DEFAULT"; then
        info "$_GRUB_BTRFS_SETTING already present in $_GRUB_DEFAULT"
    else
        echo "$_GRUB_BTRFS_SETTING" | sudo tee -a "$_GRUB_DEFAULT" > /dev/null
        info "Added $_GRUB_BTRFS_SETTING to $_GRUB_DEFAULT"
    fi

    _update_grub
}

uninstall_fix_grub_btrfs() {
    info "Removing GRUB BTRFS fix..."

    if [[ ! -f "$_GRUB_DEFAULT" ]]; then
        return 0
    fi

    if grep -qx "$_GRUB_BTRFS_SETTING" "$_GRUB_DEFAULT"; then
        sudo sed -i "/^${_GRUB_BTRFS_SETTING}$/d" "$_GRUB_DEFAULT"
        info "Removed $_GRUB_BTRFS_SETTING from $_GRUB_DEFAULT"
        _update_grub
    else
        info "$_GRUB_BTRFS_SETTING not present — nothing to remove"
    fi
}

update_fix_grub_btrfs() {
    install_fix_grub_btrfs
}

get_version_fix_grub_btrfs() {
    if check_fix_grub_btrfs; then
        echo "configured"
    fi
}

_update_grub() {
    info "Regenerating GRUB configuration..."
    if command -v update-grub &>/dev/null; then
        sudo update-grub
    elif command -v grub2-mkconfig &>/dev/null; then
        local grub_cfg
        grub_cfg=$(readlink -f /etc/grub2.cfg 2>/dev/null || echo "/boot/grub2/grub.cfg")
        sudo grub2-mkconfig -o "$grub_cfg"
    elif command -v grub-mkconfig &>/dev/null; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
        warn "Could not find grub update command — please regenerate GRUB config manually."
    fi
}
