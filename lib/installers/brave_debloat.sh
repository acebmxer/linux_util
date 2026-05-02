#!/bin/bash
# Brave Browser debloat — disables Rewards, Wallet, VPN, Leo AI, telemetry,
# News, Talk, and Tor via enterprise policy JSON.

readonly _BD_POLICY_DIR="/etc/brave/policies/managed"
readonly _BD_POLICY_FILE="${_BD_POLICY_DIR}/linux_util_brave_debloat.json"

_bd_write_policy() {
    sudo mkdir -p "$_BD_POLICY_DIR"
    sudo tee "$_BD_POLICY_FILE" > /dev/null <<'EOF'
{
    "BraveRewardsDisabled": true,
    "BraveWalletDisabled": true,
    "BraveVPNDisabled": true,
    "BraveAIChatEnabled": false,
    "BraveStatsPingEnabled": false,
    "BraveNewsDisabled": true,
    "BraveTalkDisabled": true,
    "TorDisabled": true,
    "BraveP3AEnabled": false,
    "UrlKeyedAnonymizedDataCollectionEnabled": false,
    "SafeBrowsingExtendedReportingEnabled": false,
    "MetricsReportingEnabled": false
}
EOF
}

check_brave_debloat() {
    [[ -f "$_BD_POLICY_FILE" ]]
}

install_brave_debloat() {
    echo "Applying Brave Browser debloat policy..."
    _bd_write_policy
    echo "Done. Restart Brave for policies to take effect."
}

uninstall_brave_debloat() {
    echo "Removing Brave Browser debloat policy..."
    sudo rm -f "$_BD_POLICY_FILE"
    sudo rmdir --ignore-fail-on-non-empty "$_BD_POLICY_DIR" 2>/dev/null || true
    echo "Brave debloat policy removed. Restart Brave to restore defaults."
}

update_brave_debloat() {
    echo "Re-applying Brave Browser debloat policy..."
    _bd_write_policy
    echo "Done."
}

get_version_brave_debloat() {
    echo ""
}
