#!/bin/bash
# Bitwarden Browser Extension installer functions
#
# Installs the Bitwarden extension via browser policy files so it is
# force-installed on first launch for every detected browser.
#
# Supported browsers:
#   Chromium-family : Brave, Chrome, Chromium, Vivaldi  (ExtensionInstallForcelist policy)
#   Firefox         : package/snap/flatpak              (ExtensionSettings policy)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Bitwarden Web Store extension ID (Chrome Web Store)
readonly _BW_EXT_ID="nngceckbapebfimnlniiiahkandclblb"
readonly _BW_EXT_UPDATE_URL="https://clients2.google.com/service/update2/crx"

# Bitwarden Firefox extension GUID and AMO download URL
readonly _BW_FF_GUID="{446900e4-71c2-419f-a6a7-df9c091e268b}"
readonly _BW_FF_URL="https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"

# Policy directories for each Chromium-family browser
declare -A _BW_CHROMIUM_POLICY_DIRS=(
    ["brave"]="/etc/brave/policies/managed"
    ["google-chrome"]="/etc/opt/chrome/policies/managed"
    ["chromium"]="/etc/chromium/policies/managed"
    ["vivaldi"]="/etc/vivaldi/policies/managed"
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _bw_chromium_policy_file BROWSER
#   Prints the path to this browser's Bitwarden policy JSON file.
_bw_ext_policy_file() {
    echo "${_BW_CHROMIUM_POLICY_DIRS[$1]}/bitwarden_extension.json"
}

# _bw_ext_detected_chromium_browsers
#   Prints one browser key per line for each Chromium-family browser found.
_bw_ext_detected_chromium_browsers() {
    local browser
    for browser in "${!_BW_CHROMIUM_POLICY_DIRS[@]}"; do
        command -v "$browser" &>/dev/null && echo "$browser"
    done
}

# _bw_ext_firefox_policy_path
#   Prints the Firefox policy file path to use, or empty if Firefox not found.
_bw_ext_firefox_policy_path() {
    # Regular package/binary install
    if command -v firefox &>/dev/null || pkg_check_installed firefox &>/dev/null; then
        # Prefer /etc/firefox/policies (works for both deb pkg and snap)
        echo "/etc/firefox/policies/policies.json"
        return
    fi
    # Snap install (Ubuntu/Debian)
    if has_snap && snap list firefox &>/dev/null 2>&1; then
        echo "/etc/firefox/policies/policies.json"
        return
    fi
}

# _bw_ext_apply_chromium BROWSER POLICY_DIR
#   Creates/merges the force-install policy JSON for a Chromium-family browser.
_bw_ext_apply_chromium() {
    local browser="$1"
    local policy_dir="${_BW_CHROMIUM_POLICY_DIRS[$browser]}"
    local policy_file
    policy_file="$(_bw_ext_policy_file "$browser")"

    sudo mkdir -p "$policy_dir"
    sudo tee "$policy_file" > /dev/null <<EOF
{
    "ExtensionInstallForcelist": [
        "${_BW_EXT_ID};${_BW_EXT_UPDATE_URL}"
    ]
}
EOF
    echo "  → Wrote Bitwarden extension policy for ${browser}: ${policy_file}"
}

# _bw_ext_apply_firefox POLICY_FILE
#   Creates/merges the ExtensionSettings policy JSON for Firefox.
_bw_ext_apply_firefox() {
    local policy_file="$1"
    local policy_dir
    policy_dir="$(dirname "$policy_file")"

    sudo mkdir -p "$policy_dir"
    sudo tee "$policy_file" > /dev/null <<EOF
{
    "policies": {
        "ExtensionSettings": {
            "${_BW_FF_GUID}": {
                "installation_mode": "force_installed",
                "install_url": "${_BW_FF_URL}"
            }
        }
    }
}
EOF
    echo "  → Wrote Bitwarden extension policy for Firefox: ${policy_file}"
}

# ---------------------------------------------------------------------------
# Public functions required by the registry
# ---------------------------------------------------------------------------

check_bitwarden_extension() {
    # Check policy files (installed by this tool)
    local browser
    for browser in "${!_BW_CHROMIUM_POLICY_DIRS[@]}"; do
        [[ -f "$(_bw_ext_policy_file "$browser")" ]] && return 0
    done
    local ff_path
    ff_path="$(_bw_ext_firefox_policy_path)"
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
            -path "*/Extensions/${_BW_EXT_ID}" 2>/dev/null | grep -q . && return 0
    done
    return 1
}

install_bitwarden_extension() {
    echo "Installing Bitwarden Browser Extension (policy files)..."

    local installed_count=0

    # --- Chromium-family browsers ---
    local browser
    for browser in $(_bw_ext_detected_chromium_browsers); do
        _bw_ext_apply_chromium "$browser"
        (( installed_count++ ))
    done

    # --- Firefox ---
    local ff_path
    ff_path="$(_bw_ext_firefox_policy_path)"
    if [[ -n "$ff_path" ]]; then
        _bw_ext_apply_firefox "$ff_path"
        (( installed_count++ ))
    fi

    if (( installed_count == 0 )); then
        echo "Warning: No supported browsers detected. No policy files written."
        echo "         Install a browser first, then re-run this installer."
        return 1
    fi

    echo ""
    echo "Done. The Bitwarden extension will be auto-installed on next browser launch."
    echo "Note: Extensions are force-installed and cannot be removed by the user."
}

uninstall_bitwarden_extension() {
    echo "Removing Bitwarden Browser Extension policy files..."

    local browser
    for browser in "${!_BW_CHROMIUM_POLICY_DIRS[@]}"; do
        local pf
        pf="$(_bw_ext_policy_file "$browser")"
        if [[ -f "$pf" ]]; then
            sudo rm -f "$pf"
            echo "  → Removed: ${pf}"
            # Remove the managed dir if now empty
            local pd="${_BW_CHROMIUM_POLICY_DIRS[$browser]}"
            sudo rmdir --ignore-fail-on-non-empty "$pd" 2>/dev/null || true
        fi
    done

    local ff_path
    ff_path="$(_bw_ext_firefox_policy_path)"
    if [[ -n "$ff_path" && -f "$ff_path" ]]; then
        sudo rm -f "$ff_path"
        echo "  → Removed: ${ff_path}"
        sudo rmdir --ignore-fail-on-non-empty "$(dirname "$ff_path")" 2>/dev/null || true
    fi

    echo "Bitwarden extension policy files removed."
    echo "Note: Already-installed extensions will remain until manually removed in the browser."
}

update_bitwarden_extension() {
    # Policy files contain only the extension ID; the browser auto-updates
    # the extension itself. Re-applying the policies is sufficient.
    if check_bitwarden_extension; then
        echo "Re-applying Bitwarden extension policies (extensions self-update via browser)..."
        install_bitwarden_extension
    else
        echo "Bitwarden extension policies not installed — nothing to update."
    fi
}

get_version_bitwarden_extension() {
    echo ""
}
