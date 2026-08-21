# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).
`linux_util.sh --version` reports the release tag via `git describe`. Sections
below 1.0.0 predate tagging and are grouped by month, newest first. Add new
entries under **[Unreleased]** as work lands; move them into a versioned section
when a release is cut.

## [1.2.0] - 2026-08-20

### Changed

- **AUR support disabled by default**, pending review of AUR-related security
  concerns (following the KDE Linux project's decision to drop AUR support).
  `aur_install` and `aur_build` — the two functions everything else in
  `lib/aur.sh` (and every Arch installer) routes through — now refuse to run
  and print how to re-enable them, instead of installing/building from the
  AUR. Set `AUR_ENABLED=true` to restore the previous behavior.
  `pkg_full_upgrade`'s yay/paru system-upgrade path is gated the same way,
  falling back to a pacman-only upgrade with a warning (same as when no AUR
  helper is present). Removing an already-installed AUR package
  (`aur_remove`) is unaffected — that's cleanup, not new AUR usage.

  The menu's install listing now hides any utility whose only Arch install
  path is the AUR (no `pacman`/Flatpak fallback — e.g. AnyDesk, Google
  Chrome, Visual Studio Code, PowerShell, Trojitá, Zotero) while AUR support
  is disabled, via a new `mark_aur_only_arch` registry populated in
  `lib/installers.sh` and a `_utility_hidden_aur_only` check wired into
  `lib/menu.sh`'s filtering. An already-installed copy stays listed so it can
  still be uninstalled, and everything reappears once `AUR_ENABLED=true`.
  DBeaver and Bottles, which do have a real `pacman` fallback, were switched
  to `repo_or_aur` so that fallback is actually reached instead of being
  skipped whenever a helper happened to be installed.

### Added

- **Thermalright TRCC** under **Drivers** — the community Linux port of the
  Thermalright LCD Control Center, which drives the LCD screens and RGB LED
  segments on Thermalright CPU coolers, AIO pump heads and fan hubs: themes,
  video and GIF playback, sensor overlays, a CLI and a REST API.

  Which package gets installed is decided per family, because upstream's
  release carries four Linux packages and not all of them work everywhere.

  **Debian/Ubuntu** get one of two `.deb`s. The standard one depends on the
  apt-split `python3-pyside6.*` modules; the legacy one installs its Python
  dependencies into a venv under `/opt/trcc-linux` for releases where apt has
  no PySide6 at all. The installer picks by asking `apt-cache policy` whether
  `python3-pyside6.qtcore` has a candidate, rather than matching release
  numbers — derivatives version themselves however they like, and what
  actually decides is whether the dependency resolves.

  **Arch** installs upstream's `.pkg.tar.zst`; every dependency is in the
  official repos, so no AUR route is needed and the entry stays visible while
  AUR support is disabled.

  **Fedora, RHEL and openSUSE** install the PyPI build with `pipx` instead of
  upstream's RPM — the first pipx-based installer in this project. The RPM is
  built on whatever Fedora the maintainer happens to run (`fc43` in older
  releases, `fc44` now) and pins `python(abi)` to that release's interpreter,
  so it cannot resolve on any other Fedora; and as of v9.9.10 it also hard-
  requires `pythonX.Ydist(nvidia-ml-py)` — upstream's optional `[nvidia]`
  extra leaked into `Requires` — which no Fedora or RPM Fusion repo packages,
  so `dnf` refuses it even on the Fedora it was built for. Rather than assume
  that, the Fedora path downloads the RPM and asks the repos: it walks the
  package's hard `Requires` through `dnf repoquery --whatprovides` and installs
  it when everything resolves, naming what is missing and falling back to PyPI
  when it does not. So the RPM starts being used again the moment upstream
  fixes it. `[` is a glob metacharacter to dnf and is escaped before each
  query — without that, extras provides such as
  `pythonX.Ydist(uvicorn[standard])` read as unmet when they are not.

  On the PyPI path only genuine system libraries come from the package manager
  (`sg3_utils`, `portaudio`, `libusb`, `xcb-util-cursor`, plus best-effort
  `7zip`/`ffmpeg`/`lm_sensors` where the repo has them); PySide6 and the rest
  of the Python stack install as wheels. `pipx` deliberately runs without
  `sudo`, since it installs into the invoking user's `~/.local` and a root run
  would land in `/root` where the desktop session never sees it. The udev
  rules, usb-storage quirks and `modules-load.d` entries that the native
  packages ship are not part of the PyPI package, so the installer runs
  `trcc system setup`, which re-execs itself through sudo to write them — and
  uninstall removes those four files itself on that path, since no package owns
  them there. That call deliberately omits `--yes`: upstream documents the flag
  as "non-interactive (assume yes to prompts)", but it maps to
  `interactive=False`, which `LinuxPlatform.setup()` reads as a **dry run** —
  it prints the rules it would write, changes nothing, and still exits 0, so
  passing it left the install with no device access at all. The plain form has
  no prompts to answer; that code path contains no `input()` or `confirm()`
  calls, only work.

  Release assets are matched on their versioned names. Every package is
  published twice, once versioned and once under a stable `-latest` alias, and
  only the versioned names appear in `SHA256SUMS.txt` — picking an alias would
  silently skip checksum verification, because `github_verify_checksum` treats
  a filename that is absent from the checksums file as nothing to check rather
  than as a failure.

- **OpenLogi** under **Drivers** — a local-first alternative to Logitech
  Options+ for Logi Bolt, Unifying, Bluetooth and wired Logitech peripherals:
  button and gesture remapping, DPI presets, SmartShift, keyboard F-key
  remapping, and UVC webcam controls, with no account, no telemetry, and a
  plain TOML config at `~/.config/openlogi/config.toml`.

  OpenLogi is in no distribution's repositories, so every family installs
  upstream's own package (x86-64 and arm64) through `pkg_install_local` — the
  `.deb` on Debian/Ubuntu, the `.rpm` on Fedora, RHEL and openSUSE (zypper gets
  its `--allow-unsigned-rpm` from `pkg_install_local`), and the
  `.pkg.tar.zst` on Arch, which is why this entry needs no AUR route and stays
  visible while AUR support is disabled. Each download is checked with
  `verify_download` and against the release's `SHA256SUMS` via
  `github_verify_checksum`. GitHub's `latest` endpoint is used directly here:
  upstream publishes only numbered releases, every one of them carrying the
  full Linux asset set. The asset pattern is anchored on the extension because
  every package ships a `.minisig` sibling that would otherwise match first.

  The packages install the udev rules that grant the active-seat user access to
  `/dev/hidraw*`, `/dev/uinput` and the mouse's `/dev/input/event*` node without
  root, and reload udev themselves. What they deliberately leave undone is the
  agent: `openlogi-agent.service` is a *user* unit, so it has to be enabled per
  user, and without it the GUI opens but drives nothing. The installer enables
  and starts it, falling back to printing the `systemctl --user` command when no
  systemd user session is reachable (a container, or SSH with no lingering user
  instance) rather than failing the install over it. An update restarts the
  agent, since the package upgrade replaces the binary underneath it.

  Only one program can own a receiver's HID++ channel at a time, so the
  installer warns when Solaar or Logi Options+ is already running. Uninstall
  disables the agent first, removes the package, clears
  `~/.config/openlogi`, and deletes the private copy of the unit that the GUI's
  "launch at login" setting writes into `~/.config/systemd/user/` — that copy
  outlives the package and would otherwise keep pointing at a binary that is
  gone.

- **Pay Respects** under **System Tools** — press `F` after a mistyped or failed
  command and it prints the fix for confirmation; a Rust replacement for
  `thefuck`, with an inline `Ctrl+X` correction mode that rewrites the command
  line without running it.

  pay-respects is in no Debian, Ubuntu, Fedora or openSUSE repository, so the
  installer uses upstream's own dependency-free packages — the `.deb` on
  Debian/Ubuntu and the `.rpm` on Fedora, RHEL and openSUSE (x86-64 and
  aarch64), both verified with `verify_download` and `github_verify_checksum`,
  installed through `pkg_install_local` so zypper gets its
  `--allow-unsigned-rpm`. Arch has no official-repo build either and goes to the
  AUR's `pay-respects-bin`, so the entry is registered with
  `mark_aur_only_arch`.

  The release asset is not taken from GitHub's `latest` endpoint. Upstream keeps
  a rolling `nightly` release in the same list, published as an ordinary release
  rather than a prerelease, so it can outrank the tagged versions at any time.
  The installer only accepts assets under a `/download/vX.Y.Z/` path, which
  skips the nightly build and lands on the newest numbered release; the checksum
  lookup follows that release's own tag for the same reason.

  The binary does nothing until the shell is told to bind `F` to it, so the
  installer appends a marker-delimited block to `~/.bashrc` (and to `~/.zshrc`
  when it exists — rerun Update after setting up zsh) in the style of the
  Command-Not-Found Prompt task, removed cleanly on uninstall along with
  `~/.config/pay-respects`. Because pay-respects also installs a
  `command_not_found` hook of its own, the block is written with `--nocnf`
  whenever that rc file already carries the Command-Not-Found Prompt handler —
  otherwise two handlers land in one shell and whichever is sourced last
  silently wins.

  The packages bundle a `request-ai` module that, when no local rule matches,
  sends the failed command and its error message to the author's API server
  using a key compiled into the binary. The generated block sets
  `_PR_AI_DISABLE=1` so that is off by default; deleting that one line turns it
  on.

- **LocalSend** under **Internet › File Transfer** — an open-source AirDrop
  alternative that moves files and text between devices on the same network
  with no internet connection, account, or cloud service in the middle.

  Debian/Ubuntu install from upstream's official `.deb` (x86-64 and arm-64),
  verified with `verify_download` and `github_verify_checksum`. Everything else
  goes through Flathub (`org.localsend.localsend_app`): upstream publishes no
  `.rpm` at all and the app is in no RPM distro's repositories, so Fedora, RHEL
  and openSUSE install Flatpak first if it is missing rather than being told to
  go find a package that does not exist. Arch prefers Flathub and falls back to
  the AUR's `localsend-bin`, so it is not hidden while AUR support is disabled.

  The release asset is not taken from GitHub's `latest` endpoint. LocalSend
  ships Android-only hotfix releases — v1.18.1 carries no Linux assets
  whatsoever — so `latest` intermittently points at a release with nothing to
  install. The installer walks the releases list, newest first, and takes the
  first one that actually has a Linux build; the checksum lookup follows that
  release's own tag rather than `latest` for the same reason.

  Because discovery is the whole point of the app, the installer offers to open
  port 53317 (TCP for transfers, UDP for discovery) when ufw or firewalld is
  active — without it LocalSend starts normally but stays invisible to every
  other device on the network, which is a silent failure that looks like a bug.
  Uninstall removes those rules, guarded on their actually being present, and
  clears the app's settings directory while leaving received files in
  `~/Downloads` alone.

- **Euro-Office** under **Productivity** — the desktop office suite from the
  European community fork of ONLYOFFICE (documents, spreadsheets,
  presentations, PDF and forms; AGPL v3). Unlike every other entry in this
  category it is **built from source**, because upstream publishes no desktop
  binaries at all: the `DesktopEditors` repository carries tags but no
  releases, nothing is on Flathub, Snap or AppImage, there is no apt or rpm
  repository, and the ghcr.io images for the desktop build are private. Only
  their Document Server — the server component — ships packages. The single
  supported route to the client is upstream's own containerised build, so this
  task drives it: it clones the superrepo, checks out the newest release tag,
  syncs the submodules the build needs, and runs `build/linux/build.sh`
  (`docker buildx bake`), then installs the `.deb` or `.rpm` that comes out.

  Because that compile runs for hours and wants tens of GB, nothing starts
  without a decision. The task confirms before the clone — not just before the
  compile, since the checkout with its submodules is itself several GB — and
  refuses to run unattended unless `EUROOFFICE_BUILD=yes` is set, rather than
  silently occupying a machine that has no terminal to ask at. Docker, the
  Buildx plugin and a reachable daemon are checked up front, as is the CPU
  architecture: upstream's packaging maps only x86_64 and aarch64, and
  anything else would produce a package named for an architecture that
  installs nowhere. Free space is reported for the source tree, Docker's data
  root and `/tmp` before the prompt, and `/tmp` gets its own warning when it is
  a tmpfs — upstream's bake file exports several GB of build cache to a fixed
  path there, which on Fedora and friends is charged to RAM.

  A dedicated `linux-util-euro-office` buildx builder is created for the build.
  The default `docker` driver cannot export a build to a local directory or
  reuse the local cache the bake file declares, and using our own named builder
  means removing it on uninstall cannot take anyone else's build cache with it.
  The build runs with `BUILDX_BAKE_ENTITLEMENTS_FS=0`, since the bake writes
  outside its context and buildx would otherwise stop to ask — hanging an
  unattended run. Output is streamed rather than hidden behind a spinner: over
  a multi-hour compile, the log is the only sign it is still alive.

  The newest release tag is built by default rather than whatever `main`
  happens to be, with pre-release tags (`-rc`, `-beta`, `-tp`) filtered out;
  `EUROOFFICE_REF` overrides that with any tag, branch or commit. Sources stay
  in `~/.cache/linux_util/euro-office`, so a failed build resumes instead of
  starting over and updates rebuild incrementally. Updating first compares the
  installed version against the newest tag and does nothing when they match —
  an update task that silently spent hours recompiling an identical release
  would be a poor trade. Arch takes a different route entirely: the AUR
  package runs the same containerised build under `makepkg`, and pacman ends up
  tracking a real package, which beats unpacking upstream's tarball over
  `/usr` and `/opt` untracked. Uninstall removes the package, the source and
  build cache, the builder volume and the app's settings, and names the
  leftover Docker images rather than deleting images on the user's behalf.

  When upstream starts publishing releases — their CI is already wired to
  upload these packages to a GitHub Release — this collapses to an ordinary
  download-and-install and the menu entry does not change.

- **WinApps** under **Productivity** — runs Windows applications as individual
  windows on the Linux desktop, backed by a Windows VM and FreeRDP RemoteApp.
  Upstream ships only an interactive `dialog`-driven wizard that aborts unless a
  Windows VM is already reachable and `~/.config/winapps/winapps.conf` already
  exists, so this task front-loads everything that wizard assumes: it installs
  the dependency set (FreeRDP 3, `dialog`, netcat, `libnotify`, `iproute2`,
  git), clones the source to `~/.local/bin/winapps-src` — the exact path
  upstream's own installer uses, so `winapps-setup` updates that checkout
  instead of cloning a second one — links `winapps-setup` onto `PATH`, and
  writes a mode-600 `winapps.conf` template. The `winapps` symlink is
  deliberately *not* created: upstream's setup reads that file as a pre-existing
  installation and refuses to run.

  It then offers to create the Windows VM itself from upstream's `compose.yaml`
  (Windows 11 Pro, 4 GB RAM, 4 cores, 64 GB disk, ~8 GB download), with an
  option to edit that file first for a different edition or sizing. The prompt
  is skipped entirely when there is no `/dev/tty`, so an unattended
  `--install WinApps` never starts a multi-GB download on its own; set
  `WINAPPS_DEPLOY_VM=yes`/`no` to decide in advance. `/dev/kvm` is checked
  before anything is pulled, since without it QEMU drops to software emulation
  and Windows is unusable. The compose front-end is resolved across `docker
  compose`, `docker-compose`, `podman compose`, and `podman-compose`, and when
  Podman is used `WAFLAVOR` in `winapps.conf` is rewritten to match — otherwise
  WinApps would look for the VM with the wrong tool. Declining is safe: the
  closing instructions print the exact command to run later. The user finishes
  with `winapps-setup --user` once Windows has booted.

  The Windows credentials are carried from `compose.yaml` into `winapps.conf`
  once the compose file has had its final edit. The config template is
  necessarily written before the user is offered the editor, so a VM created
  with a changed `USERNAME`/`PASSWORD` used to leave the config holding
  dockur's defaults, and WinApps then failed with `ERRCONNECT_LOGON_FAILURE` —
  an error that reads like a broken connection rather than a credential
  mismatch. Only placeholder values are replaced; anything the user set
  deliberately is left alone, and a disagreement between the two files is
  reported instead of silently resolved. The password is written single-quoted,
  since WinApps sources that file as shell and a `$` or backtick in a password
  would otherwise be expanded into a login failure that looks identical.

  `winapps-setup` is now a generated wrapper rather than a symlink to
  upstream's `setup.sh`. Upstream locates itself with `dirname` applied before
  `readlink`, so through a symlink it resolves to `~/.local/bin`, decides it is
  a stray copy outside its expected source directory, and offers to create a
  duplicate installation — which it does on every run once an installation
  exists. The wrapper changes into the source tree first, so upstream sees the
  location it expects.

  The configuration template now documents the multi-monitor trap. FreeRDP
  publishes a RemoteApp session on the monitor at offset `+0+0` only: windows
  open there and stop responding to input the moment they are dragged to
  another screen, because the X11 client leaves the RemoteApp "monitored
  desktop" handling unimplemented — neither `/multimon` nor `/size` works
  around it, and `/size` is ignored outright in RemoteApp mode. The template
  gives the arrangement that does work, `+span /monitors:<id>,<id>`, points at
  `xfreerdp /list:monitor` for the ids, and warns to exclude anything that is
  not a real screen, since a TV or AV receiver on HDMI is enumerated as a
  monitor and including one leaves part of the session rendering where nothing
  is visible.

  Host port conflicts are settled before the container starts, not after the
  multi-GB image has already been pulled. Port 3389 is usually taken by an RDP
  server on the same machine — `xrdp` and `krdp` are both installable from this
  tool — which fails the port bind outright, and left alone would aim
  `RDP_PORT` at the Linux desktop's own RDP server rather than at Windows. Both
  3389 and 8006 are checked, the conflicting service is named where it can be
  identified, and the mapping is republished on the next free port with
  `winapps.conf` updated to match. Only the host half of the mapping moves, so
  Windows still listens on 3389 inside the container, and the commented-out
  mappings that expose RDP to the local network are left untouched. The port
  currently published is read back out of `compose.yaml`, so re-running the task
  honours an earlier remap instead of rewriting the wrong line. Given a tty the
  user can decline and free the port instead — the message quotes the
  `systemctl disable --now` command for the service holding it — while
  unattended runs take the option that works. A failed `compose up` now says to
  clear the half-created container before retrying, and local edits to
  `compose.yaml`, which carries the VM's Windows password, are named when they
  block the `git pull` that updates the checkout.

  FreeRDP 2 is not usable here, and `freerdp3-x11` only exists on Debian 13+ /
  Ubuntu 24.04+, so on older Debian-family releases the task installs FreeRDP 3
  from Flathub and grants it `--filesystem=home` instead of silently leaving a
  v2 binary that WinApps would reject. On RHEL, EPEL is enabled first — both
  `freerdp` and `nmap-ncat` live there. Uninstall delegates to upstream's
  `--uninstall` when a full install is present, then removes the source tree and
  any launchers left pointing at the deleted binary, but keeps `winapps.conf`,
  which holds the user's Windows credentials. It also never removes the Windows
  container or its volume — that disk holds a full Windows installation and
  whatever the user saved inside it — and instead reports that it is still there
  along with the command to delete it deliberately. Since upstream publishes no
  tags or releases, the reported version is the checkout's commit date and short
  hash.

  Utility detection now ignores WinApps' own launchers. `winapps-setup` writes a
  two-line launcher into `~/.local/bin` for every application it finds in the
  Windows VM — `pwsh`, `cmd`, `explorer`, `msedge` and dozens more — and that
  directory sits ahead of `/usr/bin` on most PATHs, so `command -v pwsh` began
  matching a Windows shortcut. Startup detection reported PowerShell as
  installed on Linux and then ran `pwsh --version` to read its version, which
  opened a full RDP session to the VM: 20–30 seconds added to every launch, with
  a Windows PowerShell window flashing on screen. Checks now resolve a command
  to the first executable on `PATH` that is not a WinApps launcher, recognised
  by the fixed shape upstream generates rather than by location, since these sit
  in the same directory as the user's own scripts. Version probes run that
  resolved path instead of the bare name, so reading a version can never start a
  VM. A real Linux program hidden behind a launcher of the same name is still
  found and still reported, and the same protection covers every utility whose
  name a Windows application might share — Firefox, Thunderbird, VS Code, Steam
  and the rest.

### Fixed

- **LACT** install/update on Fedora and RHEL enabled the wrong COPR repo
  (`ilyalobintsev/lact`), which no longer exists, so `dnf copr enable` 404'd
  on every attempt (retries included, since the failure wasn't transient).
  Upstream's Copr repo is `ilyaz/LACT`; both distro branches now point at it.

- **Enable RDP**'s KDE Wallet integration never actually ran, so the wallet
  still prompted at every RDP login on Fedora/RHEL — most visibly as a KDE
  Wallet password dialog the first time **Visual Studio Code** was launched,
  since Chromium and Electron open the wallet at startup to fetch the key they
  encrypt saved credentials with. The `auth optional pam_kwallet5.so` line was
  appended below the stack's existing `auth include password-auth`, but
  `include` adopts the included stack's jumps: `password-auth` grants with
  `auth sufficient pam_unix.so`, so a successful login returned from the whole
  auth stack and nothing below the include was reached. The module loaded
  during the session phase, found no password had been captured, and logged
  `open_session called without kwallet5_key` before giving up. Fedora's own
  `plasmalogin` and `kde` stacks use `substack` instead of `include` for
  exactly this reason, which is why a local login unlocked the wallet where an
  RDP login did not.

  The installer now converts that `auth include` to `auth substack` when it
  adds the module, and detects and repairs stacks that earlier versions left
  half-configured — previously the "already wired into the xrdp PAM stack"
  check saw the `pam_kwallet` line, declared success, and left the broken
  ordering in place on every re-run. Both paths still prompt before touching
  PAM, keep a timestamped backup, and leave the module `optional` so it can
  never block authentication. The `account`, `password` and `session` includes
  are untouched — only the auth stack has the early-return problem.

  The README's troubleshooting entry claimed a persistent prompt meant the
  wallet password did not match the login password. That was the wrong
  diagnosis for the most likely cause; it now explains what to read out of
  `journalctl -b | grep pam_kwallet` to tell the three failure modes apart.

## [1.1.0] - 2026-08-01

### Added

- Seven clients under **Internet → Email Clients**, which previously
  offered only KMail and Thunderbird and so had no native option for a GNOME or
  XFCE desktop, no terminal client, and no way to use Proton Mail at all.
  - **Evolution** — GNOME's mail/calendar/contacts suite. Pulls in
    `evolution-ews` alongside the base package, because Exchange support is
    split into that separate package on every distro and Evolution silently
    omits the EWS account type without it; the extra install is non-fatal, so
    the client still lands on repos that do not carry it. Uninstall removes
    `evolution-ews` in a separate, tolerated command — bundling both names into
    one `apt purge`/`pacman -Rs` aborts the whole removal when EWS was never
    installed.
  - **Geary** — lightweight GNOME client. **Claws Mail** — lightweight GTK
    client suited to XFCE. **NeoMutt** — terminal client, the maintained fork of
    Mutt. All three are absent from the RHEL base channels, so each enables EPEL
    first. NeoMutt's uninstall deliberately leaves `~/.config/neomutt` and any
    local Maildirs alone: its config is hand-written, and a Maildir may hold the
    only copy of the user's mail.
  - **Proton Mail Bridge** — local IMAP/SMTP gateway that lets any of the above
    talk to Proton Mail. Installed from Flathub on every distro: Proton
    publishes only version-pinned `.deb`/`.rpm` URLs behind no "latest"
    endpoint and no apt/dnf repo, so there is nothing a native install could
    track. Requires a paid Proton plan and a running secret service, both of
    which the installer states up front rather than failing at first launch.
  - **Betterbird** — Thunderbird fork with fixes upstream has not merged. No
    distro packages it, so it installs from Flathub everywhere, falling back to
    the AUR build on an Arch system without Flatpak. Its uninstall leaves
    `~/.thunderbird` in place, because Betterbird shares that profile directory
    with a possibly still-installed Thunderbird.
  - **Trojitá** — Qt-native IMAP client, a lighter option than KMail on KDE.
    Registered as `Trojita` so the name stays typeable on the CLI. Offered on
    Fedora, Arch (AUR) and openSUSE only; Debian dropped the package and it was
    never in EPEL, so those two families get an explicit error pointing at KMail
    or Claws Mail instead of a silent failure. Note that upstream is quiet — 0.7
    dates from 2016.
- **Firewalls** category with four installable utilities: **UFW**,
  **Gufw** (UFW's GTK frontend), **firewalld**, and **firewall-config**
  (firewalld's GUI). UFW moved out of System Tasks into this category, and Gufw
  is now its own registry entry rather than being auto-installed as a side
  effect of the UFW task. Installing UFW disables an active firewalld and vice
  versa, so only one firewall manager is ever running.
- **xrdp** on Fedora, RHEL, Arch and openSUSE now offers to add
  `pam_kwallet5` to `/etc/pam.d/xrdp-sesman` when KDE is present, so KDE Wallet
  unlocks at login instead of prompting every session. An RDP login has no
  display manager behind it, so nothing hands the password to `kwalletd`; on
  Debian this is already handled, because `libpam-kwallet5` ships a
  `pam-auth-update` profile that lands in `common-auth`/`common-session`, which
  `xrdp-sesman` includes. Because a bad PAM edit can lock users out of RDP, the
  change is prompted rather than automatic, backs the file up first, uses
  `optional` so a failing module never blocks authentication, and is skipped if
  the stack already references `pam_kwallet`. It only takes effect if the wallet
  password matches the login password — which the installer reports but cannot
  fix.

### Changed

- Twelve utilities now prefer **Flathub over the AUR on Arch**
  when Flatpak is already installed: **Betterbird**, **Heroic Games Launcher**,
  **LibreWolf**, **Logseq**, **Mark Text**, **OnlyOffice**, **ProtonUp-Qt**,
  **RustDesk**, **Slack**, **Standard Notes**, **WPS Office** and **Zoom**. Each
  already shipped a Flathub build for the other distro families, so Arch was the
  only family being asked to build and trust an unreviewed PKGBUILD for software
  that had a vendor-published Flatpak. The new `flatpak_or_aur` helper only takes
  the Flatpak route when `flatpak` is already on the system — a machine without
  it has not opted in, and pulling in the whole runtime stack to avoid one AUR
  package would be the worse trade — so it falls back to the AUR otherwise.
  **Termius** and **ProtonVPN** were deliberately left on the AUR: the Termius
  Flatpak cannot reach the host shell (the same reason the RPM families moved off
  it, below), and a sandboxed VPN client cannot drive NetworkManager.
  **OnlyOffice** and **WPS Office** also gained the Flatpak checks their
  `arch)` uninstall and update branches were missing, which would otherwise have
  reached for the AUR package while a Flatpak copy was installed, and **Heroic**
  now reads its version from Flatpak when installed that way instead of
  reporting blank.
- **Termius** on Fedora, RHEL and openSUSE now installs natively
  into `/opt/Termius` by unpacking the upstream `.deb`, instead of using
  Flathub. The Flatpak's `/usr` belongs to the `org.freedesktop.Platform`
  runtime rather than the host, and its manifest grants no filesystem access at
  all, so the built-in local terminal could never reach the user's shell and
  permanently pinned `/bin/sh` as its "Local Terminal Path". The native install
  sees the real `/usr` and picks up `$SHELL` the same way the Debian package
  does. Existing Flatpak and snap copies are detected and reported with removal
  instructions rather than being removed automatically.
- `--version` now reports the release tag via `git describe`
  (e.g. `v1.1.0`, or `v1.1.0-5-g<hash>` between releases) instead of a bare
  commit hash.

### Fixed

- Ten utilities installed from the **AUR a package that is in Arch's
  official `extra` repo**: **Btrfs Assistant**, **Element**, **Input Leap**,
  **LACT**, **Obsidian**, **OpenTofu**, **Signal**, **Terraform**, **Tor
  Browser** and **Vivaldi**. On a system with `yay` or `paru` this was invisible,
  because the helpers resolve repo packages too — but with no helper installed,
  `aur_ensure` falls through to `aur_build`, which clones
  `aur.archlinux.org/<pkg>.git`, and no such AUR repo exists for a package that
  only ships in `extra`. Every one of those installs failed outright on a fresh
  Arch system with no AUR helper. They now go through a `repo_or_aur` helper that
  tries `pacman -S` first and only falls back to the AUR. **Bitwarden** likewise
  now prefers `extra/bitwarden` over the AUR's `bitwarden-bin`. Both new routing
  helpers are covered by tests, since neither can be exercised on a non-Arch
  system otherwise.
- **Cockpit** now has a description in the TUI. It was registered
  with a category and subcategory but no `UTILITY_DESCRIPTION`, so highlighting
  it rendered an empty description pane — `menu.sh` falls back to `""` for a
  missing key rather than erroring, so the gap was silent. Cockpit was the only
  one of the project's registered utilities affected. Added a test that diffs the
  `UTILITY_CATEGORY` key set against the `UTILITY_DESCRIPTION` key set, so a
  utility registered without a description now fails the suite instead of
  shipping a blank pane.
- **xrdp** now installs its NetworkManager polkit rule on every
  distro family, not only Kubuntu 26.04+. The cause is not Kubuntu-specific:
  logind gives an RDP session no local seat, so polkit skips the `allow_active`
  and `allow_inactive` tiers of an action's defaults and falls through to
  `allow_any` — `auth_admin` — making the plasma-nm applet prompt for a password
  at every login. Fedora's stock NetworkManager rule does not cover this either,
  because it gates its `wheel` exemption on `subject.local`, which is false over
  RDP. The rule now picks the right group per family (`netdev` on Debian, which
  has no `wheel`; `wheel` elsewhere, which has no `netdev`) and additionally
  requires `subject.active`, closing a hole in the previous Debian-only version
  that authorised *any* process owned by a `netdev` member — SSH sessions, cron
  jobs and background daemons included — rather than just the desktop session.
  Users are auto-joined to `netdev` as before, but never to `wheel`, since that
  grants sudo; a non-member is warned instead. Uninstall removes the rule on all
  families rather than only Kubuntu.
- **xrdp** on Fedora and RHEL now installs `xorgxrdp` (and
  `xrdp-selinux`) alongside `xrdp`. Unlike Debian, the Fedora/EPEL `xrdp`
  package does not pull in the Xorg backend that sesman launches per session,
  and `xrdp-selinux` is only a weak dependency — without them every login failed
  with "X server could not be started".
- **Stacer** on the rpm family now installs as a self-contained
  AppImage. The upstream `.rpm` is unsigned and rpm >= 6 rejects it outright,
  and Flathub has never carried a Stacer package, so both prior approaches were
  dead ends. This also fixes the openSUSE fallback path. Additionally,
  `pkg_get_version` no longer leaks rpm's "package X is not installed" message
  into the returned version string on rpm/dnf/zypper systems.

## [1.0.0] - 2026-07-18

First tagged release. See the dated sections below for the full history leading up
to this release.

### Added
- **Boxflat** installer under the **Gaming** category — settings manager for Moza
  Racing sim-racing hardware (wheelbase, wheel, pedals, shifter). Installed via
  Flatpak from Flathub by default, with a `boxflat-git` AUR fallback on Arch when
  Flatpak is unavailable. Registered in the "Gaming Utilities" subcategory and
  added to the shell-completion lists.

### Fixed
- Self-update no longer drags a pinned checkout back onto `main`. When launched
  from a detached HEAD (e.g. after `git checkout v1.0.0`), it now recognises the
  pin, skips the auto-pull, and reports the pinned ref — making tagged releases
  usable as frozen versions. Run from a branch to resume rolling updates.

## 2026-07

### Added
- Config editor for `unattended-upgrades`.
- OCCT stability-testing tool installer.
- UniFi Endpoint and Libation installers.
- Fedora/RHEL and openSUSE support for the krdp RDP server.
- fwupd firmware-update support in the system-updates task.
- Kup KDE backup tool support.

### Fixed
- xrdp: install the KDE X11 packages and open the firewall port.
- System updates/snapshots: clean only dnf/yum packages and include Flatpak.

## 2026-06

### Added
- **Bootloaders** category: GRUB, Limine, and systemd-boot installers with config
  generation, plus initramfs repair.
- GRUB theme utilities and a GRUB Theme Selector to switch installed themes.
- **Kernel Managers** subcategory (four kernel tools).
- **Login Screens** category (display managers and themes).
- Distrobox, BoxBuddy, and DistroShelf installers.
- Zen Browser installer with extension-policy support; Brave Origin browser support.
- Cockpit web-based server management utility.
- WSL support: environment detection, reboot handling, and the GTK Window Fix task.
- Minimal/standard/full install-tier selection.
- Package-repair tasks, the Delete Default Cloud-Init User task, and the Fix RDP
  Kerberos Delay task.
- OpenRSAT installer and a reorganised Remote Admin Tools category.

### Fixed
- Numerous SDDM, KDE, btrfs, Docker, Fedora, GRUB, Limine, AUR, and LACT fixes;
  honour `/var/run/reboot-required` on Debian/Ubuntu; skip flock for read-only
  commands.

## 2026-05

### Added
- **Package Managers** category (7 cross-distro tools).
- **Disk Utilities** category (GParted) and **File Managers** / **Window Managers**
  categories.
- Interactive Zsh theme selector with Powerlevel10k support.
- CachyOS-specific support across multiple installers.
- ClamAV daemon enablement and ClamTK preference configuration.
- Syncthing folder-setup wizard as a standalone task.
- Angry IP Scanner, LibreWolf, Thorium, and Brave Debloat utilities.
- Locale auto-generation on minimal systems.
- Expanded btrfs/Snapper snapshot support (Debian/Ubuntu and Fedora).

### Fixed
- Reboot via `systemctl`, lock-fd release before reboot, apt cache-freshness
  checks, and safe handling of empty mount options.

## 2026-04

### Added
- **Desktop Environments** category with distro-aware DE registration.
- **Backup** category (Déjà Dup, Vorta, Duplicati, Snapper) and snapshot tools.
- Browser-extension utilities with subcategory ordering.
- Profiles system with curated installation presets and export/import.
- Large utility-registry expansion (60+ apps: Firefox/Chromium/Chrome/Vivaldi/
  Thorium/Thunderbird/KMail, VS Code, PowerShell, Node.js, WireGuard client/server,
  and more).
- AMD and Intel chipset-driver installers; LACT GPU overclocking tool.
- Mount Local Drive plus NFS/SMB share discovery and mount tasks.
- Time Zone / Locale wizard and a Num Lock at boot task.
- Download verification, JSON output, and a description panel in the TUI menu.

### Fixed
- Numerous menu, `pkg_manager`, SDDM, and EPEL/RHEL fixes; auto-enable EPEL on
  RHEL; detect deb822 apt sources in the preflight check.

## 2026-03

### Added
- Distribution version-upgrade support: Debian codename swap, RHEL family via
  leapp, Linux Mint, Zorin OS, Elementary OS, and Ubuntu LTS→non-LTS tracks.
- xrdp and krdp RDP server support.
- Feral Gamemode installer.
- command-not-found auto-install prompt for Ubuntu/zsh.
- Thorough system-cleanup routine and an animated spinner for package operations.

### Fixed
- Extensive stabilisation across Arch/Manjaro, Fedora/RHEL, KDE Neon, and Kubuntu;
  Xen guest-tools installs; menu rendering and flicker over SSH; version detection
  and formatting; Docker, Steam/NVIDIA, and many other installers.

## 2026-02

### Added
- Initial version: core TUI installer with Fedora support and the `manage_logs.sh`
  log-management script.
