#!/bin/bash
# Feral Gamemode installer functions (build from source)

GAMEMODE_BUILD_DIR="/opt/gamemode-build"
GAMEMODE_REPO="https://github.com/FeralInteractive/gamemode.git"
GAMEMODE_VERSION="1.8.2"

# --- Feral Gamemode ---

check_gamemode() {
    command -v gamemoded &>/dev/null
}

install_gamemode() {
    echo "Installing Feral Gamemode (building from source)..."
    ensure_tools

    # Install per-distro build dependencies
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y meson libsystemd-dev pkg-config ninja-build git \
                dbus-user-session libdbus-1-dev libinih-dev build-essential

            # Debian 13+ and Ubuntu 25.04+ require the additional systemd-dev package
            local need_systemd_dev=false
            if [[ "$DISTRO_ID" == "debian" ]]; then
                local deb_major="${DISTRO_VERSION_ID%%.*}"
                if [[ "$deb_major" =~ ^[0-9]+$ ]] && [[ "$deb_major" -ge 13 ]]; then
                    need_systemd_dev=true
                fi
            elif [[ "$DISTRO_ID" == "ubuntu" ]]; then
                # Compare major version (e.g. 25.04 -> major=25, need >= 25)
                local ubuntu_major="${DISTRO_VERSION_ID%%.*}"
                if [[ "$ubuntu_major" =~ ^[0-9]+$ ]] && [[ "$ubuntu_major" -ge 25 ]]; then
                    need_systemd_dev=true
                fi
            fi

            if [[ "$need_systemd_dev" == "true" ]]; then
                echo "Detected $DISTRO_ID $DISTRO_VERSION_ID: installing additional systemd-dev package..."
                sudo apt install -y systemd-dev
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y meson systemd-devel pkg-config git \
                dbus-devel inih-devel
            ;;
        rhel)
            echo "Warning: RHEL requires EPEL to be enabled for some dependencies."
            echo "Older RHEL versions may fail due to libdbus-1 unavailability in pkg-config."
            sudo "$PKG_MGR" install -y meson systemd-devel pkg-config git \
                dbus-devel inih-devel || {
                echo "Error: Failed to install build dependencies on RHEL."
                echo "Ensure EPEL is enabled: sudo dnf install epel-release"
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm meson systemd git dbus libinih gcc pkgconf
            ;;
        suse)
            sudo zypper install -y meson systemd-devel git dbus-1-devel \
                libgcc_s1 libstdc++-devel libinih-devel
            ;;
        *)
            echo "Error: Unsupported distro family '$DISTRO_FAMILY' for Gamemode installation."
            return 1
            ;;
    esac

    # Clone, checkout, and build (common to all distros)
    sudo rm -rf "$GAMEMODE_BUILD_DIR"
    sudo mkdir -p "$GAMEMODE_BUILD_DIR"
    sudo chown "$USER":"$USER" "$GAMEMODE_BUILD_DIR"

    git clone "$GAMEMODE_REPO" "$GAMEMODE_BUILD_DIR" || {
        echo "Error: Failed to clone Gamemode repository."
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    pushd "$GAMEMODE_BUILD_DIR" >/dev/null || {
        echo "Error: Failed to enter build directory."
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    git checkout "$GAMEMODE_VERSION" || {
        echo "Error: Failed to checkout version $GAMEMODE_VERSION."
        popd >/dev/null
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    ./bootstrap.sh || {
        echo "Error: Build failed. Check the output above for details."
        popd >/dev/null
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    popd >/dev/null

    # Verify the installation
    if gamemoded -t; then
        echo "Feral Gamemode installed and verified successfully."
    else
        echo "Warning: gamemoded -t reported issues. Gamemode may still work."
    fi

    echo ""
    echo "Usage:"
    echo "  Run a game with Gamemode:  gamemoderun ./game"
    echo "  Steam launch option:       gamemoderun %command%"
}

uninstall_gamemode() {
    echo "Uninstalling Feral Gamemode..."

    # Stop the user service
    systemctl --user stop gamemoded.service 2>/dev/null || true

    if [[ -d "$GAMEMODE_BUILD_DIR/builddir" ]]; then
        pushd "$GAMEMODE_BUILD_DIR" >/dev/null || true
        sudo ninja uninstall -C "$GAMEMODE_BUILD_DIR/builddir" || {
            echo "Warning: ninja uninstall reported errors."
        }
        popd >/dev/null 2>/dev/null || true
    else
        echo "Build directory not found at $GAMEMODE_BUILD_DIR/builddir."
        echo "If Gamemode was installed via a package manager, remove it with your package manager instead."
    fi

    # Clean up build directory
    sudo rm -rf "$GAMEMODE_BUILD_DIR"

    # Remove user config
    rm -f ~/.config/gamemode.ini

    echo "Feral Gamemode has been uninstalled."
}

update_gamemode() {
    echo "Updating Feral Gamemode..."

    # Stop the user service
    systemctl --user stop gamemoded.service 2>/dev/null || true

    # Uninstall old version if build directory exists
    if [[ -d "$GAMEMODE_BUILD_DIR/builddir" ]]; then
        echo "Removing previous Gamemode installation..."
        sudo ninja uninstall -C "$GAMEMODE_BUILD_DIR/builddir" 2>/dev/null || true
    fi

    # Clean up old build directory and rebuild
    sudo rm -rf "$GAMEMODE_BUILD_DIR"
    sudo mkdir -p "$GAMEMODE_BUILD_DIR"
    sudo chown "$USER":"$USER" "$GAMEMODE_BUILD_DIR"

    git clone "$GAMEMODE_REPO" "$GAMEMODE_BUILD_DIR" || {
        echo "Error: Failed to clone Gamemode repository."
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    pushd "$GAMEMODE_BUILD_DIR" >/dev/null || {
        echo "Error: Failed to enter build directory."
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    git checkout "$GAMEMODE_VERSION" || {
        echo "Error: Failed to checkout version $GAMEMODE_VERSION."
        popd >/dev/null
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    ./bootstrap.sh || {
        echo "Error: Rebuild failed. Check the output above for details."
        popd >/dev/null
        sudo rm -rf "$GAMEMODE_BUILD_DIR"
        return 1
    }

    popd >/dev/null

    # Verify the updated installation
    if gamemoded -t; then
        echo "Feral Gamemode updated and verified successfully."
    else
        echo "Warning: gamemoded -t reported issues. Gamemode may still work."
    fi
}

get_version_gamemode() {
    local ver
    ver=$(gamemoded --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+[^\s]*' | head -1)
    echo "${ver:-}"
}
