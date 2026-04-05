#!/bin/bash
# WireGuard Server installer functions

# --- WireGuard Server ---

readonly _WG_SERVER_DIR="/etc/wireguard"
readonly _WG_SERVER_IFACE="wg0"

check_wireguard_server() {
    command -v wg &>/dev/null && [[ -f "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf" ]]
}

install_wireguard_server() {
    info "Installing WireGuard Server..."
    ensure_tools

    # Install WireGuard packages
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y wireguard wireguard-tools qrencode
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y wireguard-tools qrencode
            ;;
        arch)
            sudo pacman -S --noconfirm wireguard-tools qrencode
            ;;
        suse)
            sudo zypper install -y wireguard-tools qrencode
            ;;
        *)
            error "Unsupported distribution family: $DISTRO_FAMILY"
            return 1
            ;;
    esac

    # Generate server keys
    local server_privkey server_pubkey
    umask 077
    server_privkey=$(wg genkey)
    server_pubkey=$(echo "$server_privkey" | wg pubkey)

    # Determine the default network interface and public IP
    local default_iface public_ip listen_port server_network
    default_iface=$(ip -4 route show default | awk '{print $5}' | head -1)
    if [[ -z "$default_iface" ]]; then
        error "Could not detect default network interface."
        return 1
    fi

    # Prompt for configuration
    echo ""
    read -rp "Public IP or hostname for this server [auto-detect]: " public_ip
    if [[ -z "$public_ip" ]]; then
        public_ip=$(curl -fsSL --max-time 10 https://api.ipify.org 2>/dev/null || \
                    curl -fsSL --max-time 10 https://ifconfig.me 2>/dev/null || echo "")
        if [[ -z "$public_ip" ]]; then
            error "Could not auto-detect public IP. Please provide it manually."
            read -rp "Public IP or hostname: " public_ip
            [[ -z "$public_ip" ]] && { error "No public IP provided. Aborting."; return 1; }
        fi
        info "Detected public IP: $public_ip"
    fi

    read -rp "Listen port [51820]: " listen_port
    listen_port="${listen_port:-51820}"

    read -rp "Server VPN subnet [10.0.0.0/24]: " server_network
    server_network="${server_network:-10.0.0.0/24}"

    # Extract the server address (first usable IP in the subnet)
    local server_addr
    server_addr=$(echo "$server_network" | sed 's|\.[0-9]*/|.1/|')

    # Write server configuration
    sudo mkdir -p "$_WG_SERVER_DIR"
    sudo tee "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf" > /dev/null <<EOF
[Interface]
Address = ${server_addr}
ListenPort = ${listen_port}
PrivateKey = ${server_privkey}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${default_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${default_iface} -j MASQUERADE
EOF
    sudo chmod 600 "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf"

    # Enable IP forwarding
    if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
    fi
    sudo sysctl -p > /dev/null 2>&1

    # Enable and start the WireGuard interface
    sudo systemctl enable "wg-quick@${_WG_SERVER_IFACE}"
    sudo systemctl start "wg-quick@${_WG_SERVER_IFACE}"

    info "WireGuard Server is running on port ${listen_port}."

    # Offer to generate a client configuration
    echo ""
    read -rp "Generate a client configuration now? [Y/n]: " gen_client
    gen_client="${gen_client:-Y}"
    if [[ "${gen_client,,}" =~ ^y ]]; then
        _wg_server_generate_client_config "$server_pubkey" "$public_ip" "$listen_port" "$server_network"
    else
        info "You can generate client configs later by re-running this installer."
    fi

    info "WireGuard Server installed successfully."
}

# Generate a client configuration and add the peer to the server
_wg_server_generate_client_config() {
    local server_pubkey="$1" server_endpoint="$2" listen_port="$3" server_network="$4"

    read -rp "Client name [client1]: " client_name
    client_name="${client_name:-client1}"
    # Sanitize client name — allow only alphanumeric, hyphen, underscore
    client_name="${client_name//[^a-zA-Z0-9_-]/}"
    [[ -z "$client_name" ]] && client_name="client1"

    # Determine next available client IP in the subnet
    local subnet_base
    subnet_base=$(echo "$server_network" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')
    local cidr
    cidr=$(echo "$server_network" | cut -d'/' -f2)

    # Find used IPs from existing peers
    local next_ip=2
    if [[ -f "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf" ]]; then
        local used_ips
        used_ips=$(sudo grep -oP 'AllowedIPs\s*=\s*\K[0-9.]+' "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf" 2>/dev/null || true)
        while echo "$used_ips" | grep -q "^${subnet_base}\.${next_ip}$"; do
            (( next_ip++ ))
            if (( next_ip > 254 )); then
                error "No available IPs in the subnet."
                return 1
            fi
        done
    fi

    local client_ip="${subnet_base}.${next_ip}/32"
    local client_addr="${subnet_base}.${next_ip}/${cidr}"

    # Generate client keys
    local client_privkey client_pubkey client_psk
    client_privkey=$(wg genkey)
    client_pubkey=$(echo "$client_privkey" | wg pubkey)
    client_psk=$(wg genpsk)

    # Add client as peer to server config
    sudo tee -a "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf" > /dev/null <<EOF

# ${client_name}
[Peer]
PublicKey = ${client_pubkey}
PresharedKey = ${client_psk}
AllowedIPs = ${client_ip}
EOF

    # Reload the server interface to pick up the new peer
    sudo systemctl restart "wg-quick@${_WG_SERVER_IFACE}" 2>/dev/null || \
        sudo wg syncconf "$_WG_SERVER_IFACE" <(sudo wg-quick strip "$_WG_SERVER_IFACE") 2>/dev/null || true

    # Build client config
    local dns_servers
    read -rp "DNS servers for client [1.1.1.1, 1.0.0.1]: " dns_servers
    dns_servers="${dns_servers:-1.1.1.1, 1.0.0.1}"

    local client_conf_dir="${HOME}/wireguard-clients"
    mkdir -p "$client_conf_dir"
    chmod 700 "$client_conf_dir"

    local client_conf="${client_conf_dir}/${client_name}.conf"
    cat > "$client_conf" <<EOF
[Interface]
PrivateKey = ${client_privkey}
Address = ${client_addr}
DNS = ${dns_servers}

[Peer]
PublicKey = ${server_pubkey}
PresharedKey = ${client_psk}
Endpoint = ${server_endpoint}:${listen_port}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    chmod 600 "$client_conf"

    info "Client config saved to: ${client_conf}"

    # Show QR code if terminal supports it
    if command -v qrencode &>/dev/null; then
        echo ""
        info "QR code for mobile clients:"
        qrencode -t ansiutf8 < "$client_conf"
        echo ""
    fi

    info "Transfer ${client_conf} to the client securely."
}

uninstall_wireguard_server() {
    info "Uninstalling WireGuard Server..."

    # Stop and disable the interface
    sudo systemctl stop "wg-quick@${_WG_SERVER_IFACE}" 2>/dev/null || true
    sudo systemctl disable "wg-quick@${_WG_SERVER_IFACE}" 2>/dev/null || true

    # Remove server configuration (preserve client configs in ~/wireguard-clients)
    sudo rm -f "${_WG_SERVER_DIR}/${_WG_SERVER_IFACE}.conf"

    # Only remove WireGuard packages if no other configs remain
    local remaining_confs
    remaining_confs=$(find "$_WG_SERVER_DIR" -name '*.conf' 2>/dev/null | wc -l)
    if (( remaining_confs == 0 )); then
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y wireguard wireguard-tools qrencode 2>/dev/null || true
                ;;
            fedora|rhel)
                sudo "$PKG_MGR" remove -y wireguard-tools qrencode 2>/dev/null || true
                ;;
            arch)
                sudo pacman -Rs --noconfirm wireguard-tools qrencode 2>/dev/null || true
                ;;
            suse)
                sudo zypper remove -y wireguard-tools qrencode 2>/dev/null || true
                ;;
        esac
        sudo rmdir "$_WG_SERVER_DIR" 2>/dev/null || true
    else
        info "Other WireGuard configs exist — keeping packages installed."
    fi

    info "WireGuard Server uninstalled."
}

update_wireguard_server() {
    info "Updating WireGuard Server..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt update && sudo apt upgrade -y wireguard wireguard-tools ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y wireguard-tools ;;
        arch)    sudo pacman -S --noconfirm wireguard-tools ;;
        suse)    sudo zypper update -y wireguard-tools ;;
    esac
}

get_version_wireguard_server() {
    wg --version 2>/dev/null | grep -oP 'wireguard-tools v\K[\d.]+' || echo ""
}
