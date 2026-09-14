# WSL (Windows Subsystem for Linux)

The script runs on WSL distributions (e.g. Ubuntu under WSL2) and detects the
WSL environment automatically. WSL is identified via the `WSL_DISTRO_NAME`
environment variable or the `microsoft`/`-WSL2` marker in `/proc/version`.

When running under WSL:

- A one-line notice is shown at startup, and the menu's **System Details** panel
  includes an `Env: WSL (<distro>)` row.
- The **Reboot** action does not run automatically under WSL. A real reboot is
  not possible from inside a WSL distribution — Windows owns the virtual
  machine lifecycle and there is no bootloader (`sudo systemctl reboot` is
  unreliable, and on distros without systemd it fails outright). Restarting
  just this distribution from the Windows side is possible via the `wsl.exe`
  interop bridge, and the script prints the exact commands for you to run:

  ```powershell
  wsl --terminate <DistroName>
  wsl -d <DistroName>
  ```

  The script used to run `--terminate` for you automatically, but that was
  removed: terminating the distro's init process from inside its own session
  could leave the Windows terminal that launched it in a broken state — a
  wedged `wsl.exe` interop connection, or a garbled input mode requiring the
  window to be closed and reopened — and that happens on the Windows side
  after the script's own process has ended, so it could not be detected or
  recovered from inside the script. Running the two commands above yourself,
  from a terminal window you're prepared to have go stale, avoids that.
- Under WSLg, GTK apps (e.g. Remmina, Nautilus, Files) often launch with only a
  close button — GNOME's default window-manager layout omits minimize/maximize.
  The **Window Button Layout** system task restores all three by setting
  `org.gnome.desktop.wm.preferences button-layout` to `:minimize,maximize,close`.
  Qt/KDE apps such as Konsole are unaffected because they do not read this key.

On a normal Linux host or VM, reboot behavior is unchanged (`sudo systemctl reboot`).
