# WSL (Windows Subsystem for Linux)

The script runs on WSL distributions (e.g. Ubuntu under WSL2) and detects the
WSL environment automatically. WSL is identified via the `WSL_DISTRO_NAME`
environment variable or the `microsoft`/`-WSL2` marker in `/proc/version`.

When running under WSL:

- A one-line notice is shown at startup, and the menu's **System Details** panel
  includes an `Env: WSL (<distro>)` row.
- The **Reboot** action behaves differently. A real reboot is not possible from
  inside a WSL distribution — Windows owns the virtual machine lifecycle and
  there is no bootloader (`sudo systemctl reboot` is unreliable, and on
  distros without systemd it fails outright). Instead, choosing to reboot
  **restarts only the current distribution** (Windows itself is never affected)
  by terminating it from the Windows side via the `wsl.exe` interop bridge:

  ```powershell
  wsl --terminate <DistroName>
  wsl -d <DistroName>
  ```

  The script performs the `--terminate` step for you. Your session ends
  immediately (expected) and the distro auto-starts the next time you open a
  terminal or run `wsl -d <DistroName>`. If the `wsl.exe` bridge is unavailable,
  the script prints the exact PowerShell commands above for you to run manually.
- Under WSLg, GTK apps (e.g. Remmina, Nautilus, Files) often launch with only a
  close button — GNOME's default window-manager layout omits minimize/maximize.
  The **Window Button Layout** system task restores all three by setting
  `org.gnome.desktop.wm.preferences button-layout` to `:minimize,maximize,close`.
  Qt/KDE apps such as Konsole are unaffected because they do not read this key.

On a normal Linux host or VM, reboot behavior is unchanged (`sudo systemctl reboot`).
