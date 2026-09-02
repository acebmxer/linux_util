# Troubleshooting

**Script won't run** — ensure it is executable (`chmod +x linux_util.sh`) and you are not running as root.

**Package installation fails** — verify internet access and that repositories are reachable. Steam on Fedora requires RPM Fusion; the script offers to enable it automatically.

**AUR packages on Arch** — **AUR support is currently disabled by default**, pending review of AUR-related security concerns (see the KDE Linux project's decision to drop AUR support). Utilities whose only Arch install path is the AUR (no `pacman`/Flatpak fallback) are hidden from the menu's install listing while disabled — they reappear automatically once installed (so they can still be uninstalled) or once AUR support is re-enabled. Installers that do try to reach the AUR directly (CLI `--install`, scripted use) fail with a message telling you how to re-enable it, rather than being hidden. Set `AUR_ENABLED=true` in the environment to restore the previous behavior: install `yay` or `paru` first (the script can fall back to building from AUR directly, but an AUR helper is recommended). The AUR is only used where it is the sole option: anything carried in `core`/`extra` is installed with `pacman`, and where a utility has a vendor-published Flathub build it is preferred over the AUR if Flatpak is already installed.

**No colours / piped output** — use `--no-color`, set the `NO_COLOR` environment variable, or pipe output to a file; ANSI colours are automatically disabled in non-interactive terminals.

**Password prompts inside an xrdp session** — an RDP login has no local seat, so polkit skips the `allow_active`/`allow_inactive` tiers of an action's defaults and falls through to `allow_any`, turning silent actions into password prompts. The most visible case is the KDE network applet asking for a password at every login. **Enable RDP** installs `/etc/polkit-1/rules.d/50-xrdp-networkmanager.rules` to fix it, scoped to `subject.active` and to `netdev` (Debian) or `wheel` (Fedora/RHEL/Arch/openSUSE). On the `wheel` families the rule only applies to users already in `wheel` — the installer will not add anyone, because `wheel` also grants sudo.

**KDE Wallet asks for a password at every RDP login** — there is no display manager in an xrdp session to unlock the wallet. The first app to want a secret triggers the prompt; on a KDE desktop that is usually Visual Studio Code or a browser, because Chromium and Electron open the wallet at startup to fetch the key they encrypt saved credentials with. On Fedora/RHEL/Arch/openSUSE, **Enable RDP** offers to add `pam_kwallet5` to `/etc/pam.d/xrdp-sesman` (backing the file up first); Debian handles this itself via `libpam-kwallet5`.

Adding the module is only half the job: the stack's own `auth include password-auth` has to become `auth substack password-auth` at the same time. An `include` adopts the included stack's jumps, so when `password-auth` grants with `auth sufficient pam_unix.so`, a successful login returns from the whole auth stack and every line below the include — `pam_kwallet5` among them — is never reached. `substack` confines the jump. Fedora's own `plasmalogin` and `kde` stacks use `substack` for this reason, which is why a local login unlocks the wallet where an RDP login does not. **Enable RDP** now makes that conversion, and repairs stacks left half-configured by earlier versions.

If it still prompts after that, check `journalctl -b | grep pam_kwallet`:

- `open_session called without kwallet5_key` — the module is still not being reached during the auth phase; confirm the `auth include` above it became a `substack`.
- No `pam_kwallet` lines at all — the module never loaded; confirm `pam-kwallet` (Fedora/RHEL) or `kwallet-pam` (Arch/openSUSE) is installed.
- Otherwise the wallet password does not match the login password — change it in KWalletManager, or set the wallet to have no password.

To undo the PAM change, restore the `xrdp-sesman.bak.<timestamp>` file the installer left beside it.
