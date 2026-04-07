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
#   Prints the path to this browser's shared Chromium extension policy JSON file.
_bw_ext_policy_file() {
    echo "${_BW_CHROMIUM_POLICY_DIRS[$1]}/linux_util_chromium_extensions.json"
}

# _bw_ext_write_chromium_forcelist POLICY_FILE ENTRY...
#   Writes ExtensionInstallForcelist policy JSON with the provided entries.
_bw_ext_write_chromium_forcelist() {
    local policy_file="$1"
    shift
    local entries=("$@")

    {
        echo "{"
        echo "    \"ExtensionInstallForcelist\": ["
        local i
        for i in "${!entries[@]}"; do
            local suffix="," 
            (( i == ${#entries[@]} - 1 )) && suffix=""
            printf '        "%s"%s\n' "${entries[$i]}" "$suffix"
        done
        echo "    ]"
        echo "}"
    } | sudo tee "$policy_file" > /dev/null
}

# _bw_ext_apply_chromium_entry POLICY_FILE ENTRY
#   Adds this extension entry to the shared Chromium force-install list.
_bw_ext_apply_chromium_entry() {
    local policy_file="$1"
    local entry="$2"
    local entries=()
    local seen=0
    local line

    if [[ -f "$policy_file" ]]; then
        while IFS= read -r line; do
            line="${line#\"}"
            line="${line%\"}"
            [[ -n "$line" ]] && entries+=("$line")
        done < <(sudo grep -oE '"[a-z0-9]{32};https://clients2\.google\.com/service/update2/crx"' "$policy_file" 2>/dev/null)
    fi

    for line in "${entries[@]}"; do
        if [[ "$line" == "$entry" ]]; then
            seen=1
            break
        fi
    done
    (( seen == 0 )) && entries+=("$entry")

    _bw_ext_write_chromium_forcelist "$policy_file" "${entries[@]}"
}

# _bw_ext_remove_chromium_entry POLICY_FILE ENTRY
#   Removes this extension entry from the shared Chromium force-install list.
_bw_ext_remove_chromium_entry() {
    local policy_file="$1"
    local entry="$2"
    local kept=()
    local line

    [[ -f "$policy_file" ]] || return 0

    while IFS= read -r line; do
        line="${line#\"}"
        line="${line%\"}"
        [[ -n "$line" && "$line" != "$entry" ]] && kept+=("$line")
    done < <(sudo grep -oE '"[a-z0-9]{32};https://clients2\.google\.com/service/update2/crx"' "$policy_file" 2>/dev/null)

    if (( ${#kept[@]} == 0 )); then
        sudo rm -f "$policy_file"
    else
        _bw_ext_write_chromium_forcelist "$policy_file" "${kept[@]}"
    fi
}

# _bw_ext_detected_chromium_browsers
#   Prints one browser key per line for each Chromium-family browser found.
_bw_ext_detected_chromium_browsers() {
    local browser
    for browser in "${!_BW_CHROMIUM_POLICY_DIRS[@]}"; do
        if [[ "$browser" == "brave" ]]; then
            (command -v brave &>/dev/null || command -v brave-browser &>/dev/null) && echo "$browser"
        else
            command -v "$browser" &>/dev/null && echo "$browser"
        fi
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

# _bw_ext_extract_firefox_entries POLICY_FILE
#   Prints existing Firefox ExtensionSettings entries as GUID|URL.
_bw_ext_extract_firefox_entries() {
    local policy_file="$1"
    [[ -f "$policy_file" ]] || return 0

    sudo awk '
        BEGIN { in_settings=0; depth=0; guid="" }
        /"ExtensionSettings"[[:space:]]*:[[:space:]]*\{/ {
            in_settings=1
            depth=1
            next
        }
        in_settings {
            if (match($0, /^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*\{/, m)) {
                guid=m[1]
            }
            if (guid != "" && match($0, /"install_url"[[:space:]]*:[[:space:]]*"([^"]+)"/, u)) {
                print guid "|" u[1]
                guid=""
            }
            open_count = gsub(/\{/, "{", $0)
            close_count = gsub(/\}/, "}", $0)
            depth += open_count - close_count
            if (depth <= 0) {
                in_settings=0
            }
        }
    ' "$policy_file" 2>/dev/null
}

# _bw_ext_write_firefox_entries POLICY_FILE ENTRY...
#   Writes Firefox ExtensionSettings policy JSON with the provided entries.
_bw_ext_write_firefox_entries() {
    local policy_file="$1"
    shift
    local entries=("$@")

    {
        echo "{"
        echo "    \"policies\": {"
        echo "        \"ExtensionSettings\": {"
        local i
        for i in "${!entries[@]}"; do
            local guid="${entries[$i]%%|*}"
            local url="${entries[$i]#*|}"
            local suffix=","
            (( i == ${#entries[@]} - 1 )) && suffix=""
            echo "            \"${guid}\": {"
            echo "                \"installation_mode\": \"force_installed\"," 
            echo "                \"install_url\": \"${url}\""
            echo "            }${suffix}"
        done
        echo "        }"
        echo "    }"
        echo "}"
    } | sudo tee "$policy_file" > /dev/null
}

# _bw_ext_apply_firefox_entry POLICY_FILE GUID URL
#   Adds or updates this extension in Firefox ExtensionSettings.
_bw_ext_apply_firefox_entry() {
    local policy_file="$1"
    local guid="$2"
    local url="$3"
    local line
    local -A settings=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        settings["${line%%|*}"]="${line#*|}"
    done < <(_bw_ext_extract_firefox_entries "$policy_file")

    settings["$guid"]="$url"

    local entries=()
    local k
    for k in "${!settings[@]}"; do
        entries+=("$k|${settings[$k]}")
    done

    _bw_ext_write_firefox_entries "$policy_file" "${entries[@]}"
}

# _bw_ext_remove_firefox_entry POLICY_FILE GUID
#   Removes this extension from Firefox ExtensionSettings.
_bw_ext_remove_firefox_entry() {
    local policy_file="$1"
    local guid="$2"
    local line
    local -A settings=()

    [[ -f "$policy_file" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        settings["${line%%|*}"]="${line#*|}"
    done < <(_bw_ext_extract_firefox_entries "$policy_file")

    unset 'settings[$guid]'

    if (( ${#settings[@]} == 0 )); then
        sudo rm -f "$policy_file"
        return 0
    fi

    local entries=()
    local k
    for k in "${!settings[@]}"; do
        entries+=("$k|${settings[$k]}")
    done

    _bw_ext_write_firefox_entries "$policy_file" "${entries[@]}"
}

# _bw_ext_apply_chromium BROWSER POLICY_DIR
#   Creates/merges the force-install policy JSON for a Chromium-family browser.
_bw_ext_apply_chromium() {
    local browser="$1"
    local policy_dir="${_BW_CHROMIUM_POLICY_DIRS[$browser]}"
    local policy_file
    policy_file="$(_bw_ext_policy_file "$browser")"
    local legacy_policy_file="${policy_dir}/bitwarden_extension.json"
    local entry="${_BW_EXT_ID};${_BW_EXT_UPDATE_URL}"

    sudo mkdir -p "$policy_dir"
    # Cleanup legacy per-extension file to avoid policy key conflicts.
    sudo rm -f "$legacy_policy_file"
    _bw_ext_apply_chromium_entry "$policy_file" "$entry"
    echo "  → Ensured Bitwarden extension policy for ${browser}: ${policy_file}"
}

# _bw_ext_apply_firefox POLICY_FILE
#   Creates/merges the ExtensionSettings policy JSON for Firefox.
_bw_ext_apply_firefox() {
    local policy_file="$1"
    local policy_dir
    policy_dir="$(dirname "$policy_file")"

    sudo mkdir -p "$policy_dir"
    _bw_ext_apply_firefox_entry "$policy_file" "${_BW_FF_GUID}" "${_BW_FF_URL}"
    echo "  → Ensured Bitwarden extension policy for Firefox: ${policy_file}"
}

# ---------------------------------------------------------------------------
# Public functions required by the registry
# ---------------------------------------------------------------------------

check_bitwarden_extension() {
    # Check policy files (installed by this tool)
    local browser
    for browser in "${!_BW_CHROMIUM_POLICY_DIRS[@]}"; do
        local pf
        pf="$(_bw_ext_policy_file "$browser")"
        [[ -f "$pf" ]] && sudo grep -q "${_BW_EXT_ID};${_BW_EXT_UPDATE_URL}" "$pf" 2>/dev/null && return 0
    done
    local ff_path
    ff_path="$(_bw_ext_firefox_policy_path)"
    [[ -n "$ff_path" && -f "$ff_path" ]] && sudo grep -q "\"${_BW_FF_GUID}\"" "$ff_path" 2>/dev/null && return 0
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
        local legacy_pf="${_BW_CHROMIUM_POLICY_DIRS[$browser]}/bitwarden_extension.json"
        if [[ -f "$pf" ]]; then
            _bw_ext_remove_chromium_entry "$pf" "${_BW_EXT_ID};${_BW_EXT_UPDATE_URL}"
            echo "  → Removed Bitwarden entry from: ${pf}"
            # Remove the managed dir if now empty
            local pd="${_BW_CHROMIUM_POLICY_DIRS[$browser]}"
            sudo rmdir --ignore-fail-on-non-empty "$pd" 2>/dev/null || true
        fi
        sudo rm -f "$legacy_pf"
    done

    local ff_path
    ff_path="$(_bw_ext_firefox_policy_path)"
    if [[ -n "$ff_path" && -f "$ff_path" ]]; then
        _bw_ext_remove_firefox_entry "$ff_path" "${_BW_FF_GUID}"
        echo "  → Removed Bitwarden Firefox entry from: ${ff_path}"
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
    else
        echo "Bitwarden extension policies not found — installing now."
    fi
    install_bitwarden_extension
}

get_version_bitwarden_extension() {
    echo ""
}
