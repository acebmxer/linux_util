#!/bin/bash
# SponsorBlock Browser Extension installer functions
#
# Installs the SponsorBlock extension via browser policy files so it is
# force-installed on first launch for every detected browser.
#
# Supported browsers:
#   Chromium-family : Brave, Chrome, Chromium, Vivaldi  (ExtensionInstallForcelist policy)
#   Firefox         : package/snap/flatpak              (ExtensionSettings policy)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# SponsorBlock Chrome Web Store extension ID
readonly _SB_EXT_ID="mnjggcdmjocbbbhaepdhchncahnbgone"
readonly _SB_EXT_UPDATE_URL="https://clients2.google.com/service/update2/crx"

# SponsorBlock Firefox extension GUID and AMO download URL
readonly _SB_FF_GUID="sponsorBlocker@ajay.app"
readonly _SB_FF_URL="https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi"

# Policy directories for each Chromium-family browser
declare -A _SB_CHROMIUM_POLICY_DIRS=(
    ["brave"]="/etc/brave/policies/managed"
    ["google-chrome"]="/etc/opt/chrome/policies/managed"
    ["chromium"]="/etc/chromium/policies/managed"
    ["vivaldi"]="/etc/vivaldi/policies/managed"
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _sb_ext_policy_file BROWSER
#   Prints the path to this browser's SponsorBlock policy JSON file.
_sb_ext_policy_file() {
    echo "${_SB_CHROMIUM_POLICY_DIRS[$1]}/sponsorblock_extension.json"
}

# _sb_ext_detected_chromium_browsers
#   Prints one browser key per line for each Chromium-family browser found.
_sb_ext_detected_chromium_browsers() {
    local browser
    for browser in "${!_SB_CHROMIUM_POLICY_DIRS[@]}"; do
        command -v "$browser" &>/dev/null && echo "$browser"
    done
}

# _sb_ext_firefox_policy_path
#   Prints the Firefox policy file path to use, or empty if Firefox not found.
_sb_ext_firefox_policy_path() {
    if command -v firefox &>/dev/null || pkg_check_installed firefox &>/dev/null; then
        echo "/etc/firefox/policies/policies.json"
        return
    fi
    if has_snap && snap list firefox &>/dev/null 2>&1; then
        echo "/etc/firefox/policies/policies.json"
        return
    fi
}

# _sb_ext_apply_chromium BROWSER
#   Creates/merges the force-install policy JSON for a Chromium-family browser.
_sb_ext_apply_chromium() {
    local browser="$1"
    local policy_dir="${_SB_CHROMIUM_POLICY_DIRS[$browser]}"
    local policy_file
    policy_file="$(_sb_ext_policy_file "$browser")"

    sudo mkdir -p "$policy_dir"
    sudo tee "$policy_file" > /dev/null <<EOF
{
    "ExtensionInstallForcelist": [
        "${_SB_EXT_ID};${_SB_EXT_UPDATE_URL}"
    ]
}
EOF
    echo "  → Wrote SponsorBlock extension policy for ${browser}: ${policy_file}"
}

# _sb_ext_apply_firefox POLICY_FILE
#   Creates/merges the ExtensionSettings policy JSON for Firefox.
_sb_ext_apply_firefox() {
    local policy_file="$1"
    local policy_dir
    policy_dir="$(dirname "$policy_file")"

    sudo mkdir -p "$policy_dir"
    sudo tee "$policy_file" > /dev/null <<EOF
{
    "policies": {
        "ExtensionSettings": {
            "${_SB_FF_GUID}": {
                "installation_mode": "force_installed",
                "install_url": "${_SB_FF_URL}"
            }
        }
    }
}
EOF
    echo "  → Wrote SponsorBlock extension policy for Firefox: ${policy_file}"
}

# ---------------------------------------------------------------------------
# Public functions required by the registry
# ---------------------------------------------------------------------------

check_sponsorblock_extension() {
    # Check policy files (installed by this tool)
    local browser
    for browser in "${!_SB_CHROMIUM_POLICY_DIRS[@]}"; do
        [[ -f "$(_sb_ext_policy_file "$browser")" ]] && return 0
    done
    local ff_path
    ff_path="$(_sb_ext_firefox_policy_path)"
    [[ -n "$ff_path" && -f "$ff_path" ]] && return 0
    # Check if the extension is already present in any browser profile directory
    local root
    for root in \
        "$HOME/.config/BraveSoftware/Brave-Browser" \
        "$HOME/.config/google-chrome" \
        "$HOME/.config/chromium" \
        "$HOME/.config/vivaldi"; do
        [[ -d "$root" ]] || continue
        find "$root" -maxdepth 3 -type d \
            -path "*/Extensions/${_SB_EXT_ID}" 2>/dev/null | grep -q . && return 0
    done
    return 1
}

install_sponsorblock_extension() {
    echo "Installing SponsorBlock Browser Extension (policy files)..."

    local installed_count=0

    # --- Chromium-family browsers ---
    local browser
    for browser in $(_sb_ext_detected_chromium_browsers); do
        _sb_ext_apply_chromium "$browser"
        (( installed_count++ ))
    done

    # --- Firefox ---
    local ff_path
    ff_path="$(_sb_ext_firefox_policy_path)"
    if [[ -n "$ff_path" ]]; then
        _sb_ext_apply_firefox "$ff_path"
        (( installed_count++ ))
    fi

    if (( installed_count == 0 )); then
        echo "Warning: No supported browsers detected. No policy files written."
        echo "         Install a browser first, then re-run this installer."
        return 1
    fi

    echo ""
    echo "Done. The SponsorBlock extension will be auto-installed on next browser launch."
    echo "Note: Extensions are force-installed and cannot be removed by the user."
}

uninstall_sponsorblock_extension() {
    echo "Removing SponsorBlock Browser Extension policy files..."

    local browser
    for browser in "${!_SB_CHROMIUM_POLICY_DIRS[@]}"; do
        local pf
        pf="$(_sb_ext_policy_file "$browser")"
        if [[ -f "$pf" ]]; then
            sudo rm -f "$pf"
            echo "  → Removed: ${pf}"
            local pd="${_SB_CHROMIUM_POLICY_DIRS[$browser]}"
            sudo rmdir --ignore-fail-on-non-empty "$pd" 2>/dev/null || true
        fi
    done

    local ff_path
    ff_path="$(_sb_ext_firefox_policy_path)"
    if [[ -n "$ff_path" && -f "$ff_path" ]]; then
        sudo rm -f "$ff_path"
        echo "  → Removed: ${ff_path}"
        sudo rmdir --ignore-fail-on-non-empty "$(dirname "$ff_path")" 2>/dev/null || true
    fi

    echo "SponsorBlock extension policy files removed."
    echo "Note: Already-installed extensions will remain until manually removed in the browser."
}

update_sponsorblock_extension() {
    if check_sponsorblock_extension; then
        echo "Re-applying SponsorBlock extension policies (extensions self-update via browser)..."
        install_sponsorblock_extension
    else
        echo "SponsorBlock extension policies not installed — nothing to update."
    fi
}

get_version_sponsorblock_extension() {
    echo ""
}
