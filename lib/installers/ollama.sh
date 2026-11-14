#!/bin/bash
# Ollama installer functions
#
# Runs large language models locally. The distro package where the repositories
# have one (Fedora, Arch, openSUSE, Alpine), started as a service; otherwise
# the release from GitHub, checked against its published SHA-256, unpacked into
# /usr/local, with an `ollama` system user and a systemd service, the setup
# Ollama documents for a manual install. It uses the CPU and NVIDIA GPUs; AMD
# GPUs need Ollama's separate ROCm add-on, which this does not install.
# Uninstalling keeps the downloaded models in /usr/share/ollama and the user.

# --- Ollama ---

_OLLAMA_REPO="ollama/ollama"
_OLLAMA_LIB="/usr/local/lib/ollama"
_OLLAMA_UNIT="/etc/systemd/system/ollama.service"

# Latest upstream version, for System Updates.
_ollama_latest_version() { github_latest_tag "$_OLLAMA_REPO" | sed 's/^v//'; }

check_ollama() { _check_standard ollama ollama "" || [[ -x /usr/local/bin/ollama ]]; }

_ollama_install_release() {
    local tmp file
    has_systemd || { error "The Ollama release install needs systemd."; return 1; }
    command -v zstd &>/dev/null || pkg_install zstd || return 1
    tmp=$(mktemp -d) || return 1
    CLEANUP_FILES+=("$tmp")
    file=$(github_asset_download "$_OLLAMA_REPO" "ollama-linux-$(upstream_arch go)\.tar\.zst" "$tmp") || { rm -rf "$tmp"; return 1; }
    sudo rm -rf "$_OLLAMA_LIB"
    zstd -dc "$file" | sudo tar -xf - -C /usr/local || { error "Could not unpack the Ollama download."; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    id ollama &>/dev/null || sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama || return 1
    sudo usermod -aG ollama "${SUDO_USER:-$USER}" 2>/dev/null || true
    printf '%s\n' \
        '[Unit]' \
        'Description=Ollama Service' \
        'After=network-online.target' \
        '' \
        '[Service]' \
        'ExecStart=/usr/local/bin/ollama serve' \
        'User=ollama' \
        'Group=ollama' \
        'Restart=always' \
        'RestartSec=3' \
        '' \
        '[Install]' \
        'WantedBy=multi-user.target' | sudo tee "$_OLLAMA_UNIT" >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable ollama >/dev/null 2>&1
    sudo systemctl restart ollama || warn "Could not start the ollama service; it will start at the next boot."
}

install_ollama() {
    info "Installing Ollama..."
    pkg_refresh
    if pkg_in_repo ollama; then
        pkg_install ollama || return 1
        svc_enable_now ollama || warn "Could not start the ollama service; it will start at the next boot."
    else
        info "ollama is not in the ${DISTRO_NAME:-system} repositories; installing the verified release from GitHub."
        _ollama_install_release || return 1
    fi
    info "Ollama installed. Try: ollama run llama3.2"
}

uninstall_ollama() {
    info "Uninstalling Ollama..."
    svc_disable_now ollama 2>/dev/null || true
    pkg_check_installed ollama && pkg_remove ollama
    if [[ -x /usr/local/bin/ollama ]] && ! pkg_check_installed ollama; then
        sudo rm -f "$_OLLAMA_UNIT" /usr/local/bin/ollama
        sudo rm -rf "$_OLLAMA_LIB"
        has_systemd && sudo systemctl daemon-reload
    fi
    return 0
}

update_ollama() {
    info "Updating Ollama..."
    if ! upstream_binary_present ollama ollama; then
        pkg_upgrade ollama
        return $?
    fi
    local tag cur
    tag=$(github_latest_tag "$_OLLAMA_REPO") || { error "Could not read the latest Ollama release from GitHub."; return 1; }
    cur=$(get_version_ollama)
    if [[ -n "$cur" && "${tag#v}" == "$cur" ]]; then
        info "Ollama is already at the latest version (${cur})."
        return 0
    fi
    _ollama_install_release
}

get_version_ollama() { _ver_from_pkg ollama || _ver_from_cmd ollama || echo ""; }
