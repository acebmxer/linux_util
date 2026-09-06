# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).
`linux_util.sh --version` reports the release tag via `git describe`. Sections
below 1.0.0 predate tagging and are grouped by month, newest first. Add new
entries under **[Unreleased]** as work lands; move them into a versioned section
when a release is cut.

## [Unreleased]

### Fixed

- **tmux auto-attach never fired on SSH login.** The snippet the **tmux**
  installer appends to `~/.bashrc` or `~/.zshrc` was guarded by
  `[ -z "$TMUX" ] && [ -t 1 ]`. The `[ -t 1 ]` test is the problem: an rc file is
  sourced while the shell is still starting up, before stdout is connected to the
  terminal, so the test returns false even in a genuine interactive SSH login and
  the whole block was skipped. Reconnecting after a dropped connection therefore
  landed in a bare shell instead of the persistent `work` session — the exact
  scenario the feature exists for. The guard now tests `$-` for the `i` flag
  alone, which is set for interactive shells and absent for `ssh host cmd`, scp
  and rsync, preserving the protection that stopped non-interactive transfers
  from being broken by terminal escapes. Because the marker check made a re-run a
  no-op, an rc file already carrying the broken snippet would have kept it
  forever; the installer now detects a stale block containing `[ -t 1 ]`, strips
  it, and writes the corrected one, leaving the user's own rc lines untouched.

- **tmux auto-attach failed with "open terminal failed: not a terminal" under
  Powerlevel10k.** With the `[ -t 1 ]` guard removed the block finally ran, but
  appending it to the end of `~/.zshrc` put it *after* p10k's instant-prompt
  preamble, which takes over the console partway through initialisation. tmux
  started from there gets no usable terminal and exits immediately, dropping the
  user at a bare shell, and p10k additionally warns about "console output during
  zsh initialization". Powerlevel10k documents that code needing the console must
  run above the preamble, so the installer now looks for the
  `p10k-instant-prompt` guard and inserts the block above it, backing up over the
  preceding comment block so the snippet lands before the preamble rather than
  inside its comments. An existing block stranded below the preamble is detected
  and relocated even when its guards are already correct. Shells with no p10k
  preamble — the common case — are unaffected and still get a plain append.

- **fastfetch stopped appearing once tmux auto-attach was enabled.** Both
  installers insert their block above the Powerlevel10k preamble, so whichever
  ran last ended up first. With the tmux block ahead of it, `tmux attach`
  replaced the shell before the `# linux_util:fastfetch` line was ever reached
  and the banner silently disappeared; in the opposite order it printed on every
  single reconnect, including reattaches to a session already in progress.
  Neither is right, and an rc-file line cannot tell the two cases apart. The
  auto-attach snippet now runs fastfetch on the branch that *creates* the
  session — `if ! tmux attach -t work; then fastfetch; tmux new -s work; fi` — so
  it shows on a first connect after a reboot or after `exit` destroyed the
  session, and never paints over work being resumed after a dropped connection.
  The **fastfetch** installer's own line gained a `-z $TMUX` guard so it does not
  double up inside tmux while still running normally outside it, and because the
  marker check made a re-run a no-op, an existing line without that guard is
  rewritten in place rather than left stale.

- **fastfetch was never visible inside the tmux session.** The banner was
  printed by the login shell just before tmux started, and tmux clears the
  screen when it takes over — so on a session-creating connect it was wiped
  immediately and only reappeared in the scrollback after exiting. The block now
  shows it in both places: once on the login shell as before, and once inside the
  new session, where it stays on screen. The in-session copy is delivered by
  creating the session detached and using `tmux send-keys` to run `clear;
  fastfetch` in its first window, then attaching. Passing a flag through the
  environment does not work here — a shell started inside tmux inherits the tmux
  *server's* environment rather than the client's, so both a `VAR=1` prefix and
  `tmux new -e` arrive empty. Extra windows and panes opened later are unaffected,
  a reattach still shows nothing, and the plain `tmux new` path is kept for
  machines with no fastfetch installed.

- **fastfetch printed twice on a connect that created a tmux session.** The
  `-z $TMUX` guard added to the **fastfetch** auto-run line only suppresses it
  for shells started *inside* tmux. On the login shell that is about to start
  tmux, `$TMUX` is still empty, so that line ran, and then the auto-attach block
  ran it again on the create branch — two banners on a first connect, and one on
  a reattach where there should have been none. The auto-attach block now sets
  `_LU_TMUX_AUTOATTACH` when it is going to handle the login, the fastfetch line
  stands down on that flag, and the installer writes the block above that line so
  the flag is assigned before it is read. The flag is set only when tmux is
  actually present, so removing tmux hands the banner back to the fastfetch line
  rather than silencing it everywhere; a block already sitting below the
  fastfetch line is detected and moved above it.

- **An out-of-date tmux auto-attach block was not refreshed unless it matched a
  known defect.** The installer decided whether to rewrite an existing block by
  testing for specific faults — first a `[ -t 1 ]` guard, later a position below
  the Powerlevel10k preamble — which meant each new change to the block needed
  its own bespoke check and silently no-op'd on machines that already had one.
  Adding the fastfetch line hit exactly this: a correctly placed, correctly
  guarded block reported "already present" and kept the old body. The block now
  has a single definition (`_tmux_autoattach_block`) and the installer compares
  what is on disk against it, rewriting on any difference, so future edits reach
  existing installs without further changes. Writing twice still converges, so a
  re-run does not churn the file.

- **Test suite no longer edits the developer's own `linux_util.conf`.** The
  repository is itself a working install — `linux_util.conf` sits in the
  checkout — and the CLI tests run the real `linux_util.sh` from the repo root.
  Startup config migration therefore fired against that file, rewriting comments
  in it and leaving `linux_util.conf.bak.<stamp>` files in the working tree, on
  every test run. `lib/config.sh` now honours a `LINUX_UTIL_CONFIG_FILE`
  override for the config path, and the CLI test harness points every run at a
  throwaway copy under `/tmp`. A guard test fails the suite if a run ever leaves
  a new backup beside the repository's own config again.

### Added

- **Config schema migration.** `linux_util.conf` is created once by copying
  `linux_util.conf.example` and then maintained by hand, so keys added to the
  example in later releases never reached it — a config written a few releases
  ago silently ran on defaults its owner had never seen or chosen. On startup,
  any key present in the example but absent from the user's config is now
  appended, carrying the example's own comment block so it arrives documented.
  Documentation is kept current too: a key that already exists keeps whatever
  value the user set, but where the example has since reworded the comment above
  it, that new text replaces the old. Without this, only *missing keys* were
  ever brought over, so a config written before a rewording kept describing
  behaviour the program no longer had — worse than a missing comment, because
  the user has no reason to doubt it. This is how `auto_confirm` came to be
  documented as "Skip confirmation prompts" in existing configs long after the
  example explained that it answers installer prompts and not the package
  manager's, and how the `config_version` stamp kept a one-line note that
  contradicted the three-line block the example ships. The stamp's comment is
  now taken from the example rather than written out separately in
  `_cfg_stamp_version`, so one file is the authority on how that key is
  documented, and a reworded explanation reaches existing configs even when the
  schema version itself has not moved.
  Replacing a comment replaces the whole block above the key, so a note the user
  hand-wrote directly above a documented setting is lost — a per-line merge
  cannot tell an edited stock comment from a hand-written one, and keeping both
  is how a config ends up documenting one key two contradictory ways. Comments
  above keys the example does not define are never touched, and the backup is
  the recovery path. `# --- Section ---` banners are treated as headings rather
  than as part of the following key's comment, so migrating a key no longer
  drags a duplicate section header into the config with it.
  **This edits a file the user maintains.** Setting values and their ordering
  are never changed, no key is ever removed, and a timestamped
  `linux_util.conf.bak.<stamp>` is written beside the file before any change. A
  notice before the menu lists every key that was added and every comment that
  was rewritten, and points at the backup, so changes to a hand-edited file are
  never a surprise found later; it waits for ENTER so the TUI does not clear it
  off the screen, and skips that wait when no terminal is attached. A run that
  changes nothing is silent, writes nothing and leaves no backup.
  It runs *after* the self-update step, which is the ordering that makes it
  work: a `git pull` is the moment a new `linux_util.conf.example` first exists
  on disk, so migrating beforehand would compare against the old example, find
  nothing, and leave the user a release behind until their next launch. When
  self-update applies a new version it re-execs, so the migration runs once in
  the fresh process against current files.
  The scan compares directly against the example every run, with no "already at
  the latest version, skip" shortcut: such a shortcut would make correctness
  depend on remembering to bump a version constant by hand every time a key was
  added, and forgetting it would leave every existing config stamped current and
  silently never receiving the new key — while fresh installs, copied from the
  example, got it, so the bug would be invisible to whoever shipped it. Adding a
  key to `linux_util.conf.example` is therefore all that is needed for existing
  configs to pick it up. `config_version` records what the file has been brought
  up to and is read from the example itself, so the version travels with the
  keys it describes instead of living in a constant that can drift out of step.

- **tmux** and **tmux Resurrect** under *Remote Admin Tools > Remote Access*,
  covering SSH sessions that survive a dropped connection. An SSH drop kills the
  client, not the remote shell: with tmux the session and everything running in
  it stay alive on the server, and reattaching resumes the same shell rather than
  starting a new one. tmux runs entirely on the remote side, so unlike mosh or
  Eternal Terminal — which need matching binaries at both ends — it works from
  any terminal or SSH client, including GNOME Terminal, Konsole and Termius.
  Installed from each distro's own repositories (verified present in Arch
  `extra`, Debian stable, Ubuntu noble, and Fedora 41).
  The **tmux** installer offers, as an explicit prompt defaulting to yes, to
  append an auto-attach block to the user's shell startup file (`~/.bashrc` or
  `~/.zshrc`) so an interactive login reattaches to a `work` session instead of
  landing in a bare shell. **This edits a file the user maintains**; declining
  leaves the file untouched, the block is delimited by markers so uninstalling
  removes exactly what was added, and a non-interactive run skips it entirely
  rather than rewriting a login shell's rc unattended — unless `auto_confirm` is
  set, which takes the default (yes) as the user's standing answer. The snippet is guarded
  against recursing inside an existing tmux session and against firing on
  non-interactive sessions, which would otherwise break `scp`, `rsync` and
  git-over-SSH.
  **tmux Resurrect** covers the case tmux alone does not: sessions live in the
  tmux server's memory and so do not survive a reboot of the machine hosting
  them. It restores window and pane layout and working directories — not the
  processes that were running in them. No distribution packages it, so it is
  installed by cloning upstream into `~/.tmux/plugins/` and sourced directly
  from `~/.tmux.conf`, avoiding a dependency on TPM for a single plugin; it
  pulls tmux in first if missing, since the plugin is inert without it.

- The TUI header now shows the current release version on the byline row, as
  `Version: v1.3.1   By: PozzaTech`. The number is read from the tag list by
  version sort (`git tag --sort=-v:refname`) rather than `git describe`, which
  walks HEAD's ancestry: release tags are created on `main` after a pull request
  merges, so the merge commit they point at never exists on `dev` and `describe`
  from a development branch reports the *previous* release. Sorting the tag list
  ignores ancestry and reports the newest release from any branch. Tags are
  refreshed once at startup so a release cut since the last pull is picked up.
- **Self Update** honours a new `update_channel` config key, letting a user
  choose what the updater follows instead of always tracking whichever branch
  happened to be checked out: `main` for released versions only (the default),
  `dev` for continuous updates, or a release tag such as `v1.3.1` to pin. A
  pinned install checks that tag out and then makes no further changes, and the
  header appends `(v1.4.0 available)` when a newer release exists so that a pin
  never silently strands a user on a stale version. A manual `git checkout`
  still takes precedence over the configured channel — self-update reports the
  detached HEAD and leaves it alone rather than dragging the user back onto a
  branch, since discarding a deliberate checkout would be destructive.
- Added `docs/configuration.md` coverage for the new `update_channel` setting.

### Removed

- The `create_backups` and `backup_dir` config settings, which were parsed and
  documented but never read by any code — setting them had no effect. The
  backups that do happen (package-manager repo config saved before a reset) are
  written by the installers themselves to `/var/backups/linux_util/`, and never
  consulted these keys.

### Fixed

- The `auto_confirm` config key did nothing. `lib/config.sh` parsed it, validated
  it as a boolean and assigned `CFG_AUTO_CONFIRM`, but no code ever read that
  variable — so a user who set `auto_confirm=true` to skip prompts, as the
  shipped example told them it would, still got every prompt. It is now consumed
  by `_confirm_step()` in `lib/installers/_shared.sh`, the shared gate the
  installers already call for confirmations, so one change covers all of them.
  The no-terminal case is now explicit too: `_confirm_step` previously read
  `/dev/tty` unconditionally, which in a detached run (a pipe, cron, a systemd
  unit) either failed the read and fell through to "No" by accident or blocked
  outright. It now tests that `/dev/tty` can actually be opened — `-r` alone
  passes in a detached session and then errors on open, leaking a raw shell
  error — and declines with an explanation, so an unattended run never takes a
  destructive branch nobody approved.

- **System Updates** on Arch-family systems applied the entire system upgrade
  during the pre-flight step, before the run the user had actually selected
  began — so the run itself then reported `No update available` and looked like
  it had done nothing, moments after 24 packages had been upgraded a few lines
  higher under the single line `Refreshing package cache & upgrading`. The cause
  was `pkg_refresh`, the generic step that runs before any install: on apt and
  dnf it only refreshes metadata (`apt update`, `dnf makecache`), but pacman has
  no safe metadata-only refresh in general — `pacman -Sy` without `-u` leaves a
  partial-upgrade window — so it ran a full `pacman -Syu` and swallowed the
  update. A utility is now marked when its own run performs a complete system
  upgrade (`mark_full_upgrade`, currently **System Updates**), and for such a run
  the pre-flight syncs the database only, leaving the upgrade to happen inside
  the selected run where the user asked for it and where its package list is
  printed — matching how apt and dnf already behaved. Ordinary installs are
  unaffected and still get the full `-Syu`, since the partial-upgrade window is
  real for them; a batch that mixes **System Updates** with any other utility
  also keeps the full upgrade, because that other install needs an already
  upgraded system underneath it.
- The end-of-run pending-reboot check never fired on Arch-family systems, so a
  run could report `No reboot needed` while the desktop was showing a reboot
  notification for the very same upgrade. The check tested only
  `/var/run/reboot-required` (a Debian/Ubuntu marker file) and `needs-restarting`
  (RHEL/Fedora); Arch has neither, so on CachyOS the safety net was dead code.
  `_reboot_required` now also reads the pending restart off the live system on
  Arch, from two independent signals: the running kernel's module tree being gone
  from `/usr/lib/modules` (pacman removes it when the kernel package is upgraded,
  so its absence means the running kernel is no longer the installed one), and
  running processes still mapping `/usr` files that have been replaced on disk —
  the `(deleted)` mappings in `/proc/<pid>/maps` that a library upgrade leaves
  behind, which is the case an ordinary `openssl`/`curl`/`mesa` update hits with
  no kernel change at all. Both read only `/proc` and the filesystem, needing no
  sudo and no package-manager call, and only `/usr` paths count so a browser's
  deleted shm segment or a temp file never raises a prompt. The warning names the
  owning packages (`Triggered by: curl, gpgme, mesa, wireplumber`) rather than
  the thirty-odd individual `.so` paths behind them, resolving a replaced
  versioned soname back to its package via the unversioned name when pacman no
  longer owns the old path. Note that CachyOS's own reboot notification is
  transient — its pacman hook fires once during the transaction and writes no
  marker — so unlike Debian's `/var/run/reboot-required` there is no file to
  consult afterwards; recomputing from `/proc` is what lets a second run without
  an intervening reboot still report the restart as pending, matching how
  `needs-restarting` behaves on Fedora.
- The Arch pending-reboot check inverted its own result inside the running
  script, reporting `No reboot needed` with thirty replaced libraries still
  mapped. `linux_util.sh` runs under `set -o pipefail` and the check ended in
  `… | grep -q .`; `grep -q` exits on its first match, which SIGPIPEs the `sort`
  feeding it, and `pipefail` then takes that as the pipeline's status — so the
  check reported "nothing stale" precisely *because* it had found something. The
  result is now assigned and tested with `[[ -n ]]` rather than piped into
  `grep -q`, and `_reboot_stale_files` no longer leaks the per-process `grep`
  failures (one for nearly every process, since most map nothing stale) as its
  own exit status. The regression tests for this run under `pipefail`, which the
  suite did not previously set — the reason the fault passed tests while failing
  in the real script.
- The `Triggered by:` package list printed pairs separated by alternating comma
  and space (`curl,gpgme mesa,wireplumber`) because `paste -sd', '` treats its
  argument as a delimiter *list* applied cyclically rather than as one two-
  character separator.
- Added the missing `dns_check_host` row to the settings table in
  `docs/configuration.md`.

## [1.3.1] - 2026-09-02

### Fixed

- **System Updates** printed every upstream-binary app's name twice — the run
  showed `Updating Libation...` on two consecutive lines, and the same for
  **Visual Studio Code**. `_system_updates_upstream_binaries` announced each
  utility before calling it, but the functions it calls are the same
  `update_*` functions the menu invokes directly, and each of those already
  announces itself as its first action. The caller's line was the redundant
  one and has been removed: all six utilities registered as upstream binaries
  (**Visual Studio Code**, **VSCodium**, **Mark Text**, **Standard Notes**,
  **PowerShell**, **Libation**) print their own heading, so nothing is left
  unlabelled.
- **Visual Studio Code** and **VSCodium** announced their update with a bare
  `echo` rather than `info`, so the line printed without the `[INFO]` prefix
  and colour every other step of an update run uses — visible in a System
  Updates run as one unprefixed line among prefixed ones. Both now use `info`.

## [1.3.0] - 2026-09-02

### Added

- **VSCodium** (Development → IDEs & Editors), the community build of the VS
  Code source with Microsoft's telemetry, branding, and proprietary marketplace
  stripped out (extensions resolve against Open VSX). It coexists with
  **Visual Studio Code** rather than replacing it — different binary (`codium`),
  config (`~/.config/VSCodium`), and extension directory (`~/.vscode-oss`), so
  both can be installed at once and the uninstall only clears its own state.
  Debian and the rpm distros use the signed repos vscodium.com points at
  (`download.vscodium.com`, keyed from the paulcarroty repo project);
  `repo_gpgcheck` is on for the rpm side because that repo publishes a detached
  `repomd.xml.asc`. Arch has no repository package — `vscodium-bin` is AUR-only,
  and this tool keeps the AUR disabled — so it follows the same tiering as the
  VS Code installer: repos → Flathub → the project's own GitHub release tarball
  → AUR. That tarball is what `vscodium-bin` repackages, it ships `.sha256`
  sidecars so the download is checksum-verified, and unlike Microsoft's it
  unpacks flat, so it is extracted straight into `~/.local/share/vscodium`
  with no root needed.
- **ClamAV now offers the ClamUI desktop front-end** (`io.github.linx_systems.ClamUI`,
  MIT) from Flathub. ClamUI is a GTK4/libadwaita app — graphical scanning,
  quarantine management, scheduled scans and file-manager integration — and its
  Flathub build is publisher-verified. It bundles no scanner of its own: the
  Flatpak reaches the host's `clamscan`/`freshclam` through `flatpak-spawn
  --host`, so the engine packages this installer lays down are what it drives.
  Being a Flatpak on the GNOME runtime, it pulls no GNOME packages onto the
  system and runs anywhere — its tray registers with the KDE/XFCE/Cinnamon/MATE
  StatusNotifierItem watchers, and upstream integrates with Dolphin and Nemo as
  well as Nautilus.
  - **The installer now asks which front-end to install**, defaulting to ClamUI:
    ClamUI, ClamTk, or both. The prompt comes first, before any package work, so
    the rest of the install runs unattended instead of stopping for input
    part-way through. Arch is not asked (ClamTk is AUR-only there), and neither
    is a run with no controlling terminal — profile-driven installs take the
    default rather than hanging on `/dev/tty`.
  - **ClamTk remains available** wherever the distro packages it (Debian,
    Fedora/RHEL, openSUSE). Its preference seeding is now guarded on the binary
    actually being present rather than assumed, and a failed ClamTk install
    falls back to ClamUI rather than leaving no GUI at all.
  - **The engine is installed on its own**, separately from the front-end, so a
    GUI that is declined or unavailable can no longer take the scanner down with
    it. `update_clamav` updates whichever front-end is actually present and no
    longer force-installs ClamTk; an install with no GUI at all — one predating
    this change, or one whose front-end was removed by hand — gets ClamUI.
- **Package Managers section in the README's "Utilities by Category"**, which
  had never been written — Flatpak Setup, Homebrew, Nix, Snap (snapd),
  deb-get, Pacstall, yay and paru are now documented there.

### Changed

- **`README.md` trimmed from 694 lines to a lean front page, with the deep-dive
  material moved into `docs/`.** The README had grown to carry the entire
  utility catalogue — every category's per-item table, roughly 260 lines of it —
  alongside the config reference, logging, shell completions, WSL behaviour,
  project structure, module responsibilities, the how-to-add-a-utility walkthrough
  and the full troubleshooting section. The result was a front page nobody could
  skim: the answer to "what is this and how do I run it" sat above ten screens of
  reference tables, and the developer material duplicated `CONTRIBUTING.md`
  rather than deferring to it.
  - The README now opens with what the tool is, the clone-and-run block, and a
    **Read next** table pointing at each docs page. What survives inline is what
    a first-time reader needs: requirements, an annotated menu screenshot, a
    thirteen-row summary of what each category covers, the CLI flag list, the
    supported-distribution table, snapshots, and a short logging/config section.
  - New `docs/utilities.md` holds the complete catalogue, every per-utility
    description carried over verbatim, with a category index at the top.
  - New `docs/menu.md` (controls, selection logic, profiles), `docs/configuration.md`
    (config settings, logging, `manage_logs.sh`, bash/zsh completions),
    `docs/wsl.md` (WSL detection and the restart-the-distro reboot behaviour) and
    `docs/troubleshooting.md` (including the xrdp polkit and KDE Wallet PAM
    material).
  - The README's developer sections were dropped in favour of `CONTRIBUTING.md`,
    which already covered adding an installer, code style and the test suite.
    The two things it lacked were folded in: the **module responsibilities table**
    (which file to edit for a given kind of change) and the **helper function
    reference** (`pkg_install`, `repo_or_aur`, `download_file`, and the rest).
    A missing step was also added — assigning `UTILITY_CATEGORY` in
    `lib/installers.sh`, without which a newly registered utility never appears
    under a menu tab.
  - All 195 utility and system-task table rows from the old README are present in
    the new files; every internal link and heading anchor across `README.md`,
    `CONTRIBUTING.md` and `docs/*.md` was checked to resolve.

- **The README's menu diagram is now a real capture instead of a hand-drawn
  sketch.** The ASCII mock-up had been drawn by hand when the TUI was overhauled
  (`3c52569`, April 2026) and hand-patched once since, so it had drifted from
  what the code renders: it showed a `SYSTEM Details` header (the code emits
  `SYSTEM DETAILS`), seven sysinfo rows where the panel now has up to thirteen —
  `GPU`, `OS Age`, `Packages`, `WM` and `DE` were all missing — six of the
  sixteen registered categories, an abbreviated `Default Phys. PC` profile name,
  and a `[^v] Navigate … [Enter] Confirm` key hint that omitted the `[Tab] Focus`
  and `[Q] Quit` entries the footer actually prints. It also carried a
  hand-typing artefact from the original: the `Host:` row had one space too many,
  so its right border sat a column out from every other row.

  The block is now the actual frame `_compose_frame` draws, captured from a real
  render in a 100x46 pty with the sysinfo values replaced by representative ones
  (`linux-pc` / Arch Linux, rather than the capturing machine's hostname and
  hardware). All 45 lines are exactly 100 columns wide, so the border aligns.
  The **What it installs** summary in the README gained the four categories the
  capture exposed as missing — **File Managers**, **Firewalls**, **Login
  Screens** and **Window Managers**.

- **Stacer now tracks the maintained `QuentiumYT/Stacer` fork** instead of
  `oguzhaninan/Stacer`, which is dormant — last release v1.1.0 in **2019**, last
  push February 2024 — and whose age was the sole cause of every workaround this
  installer carried. The fork is the same codebase carried forward (oguzhaninan
  is still its top contributor at 524 commits, QuentiumYT has 138 on top), is
  ported to Qt6, and has shipped ten releases between May 2025 and v1.7.0 in May
  2026. Of the original's 100 forks it is the only one with any activity — the
  runner-up has two stars and was last pushed in 2017 — and both AUR packages
  (`stacer-bin` and `stacer`, different maintainers) already point at it, so
  Arch users were getting it regardless.
  - **Fedora/RHEL install the `.rpm` again**, dropping the AppImage workaround.
    The 2019 rpm predated payload digests, so rpm >= 6 (Fedora 41+) rejected it
    with "does not verify: no digest" and there was no bypass short of lowering
    `%_pkgverify_level` system-wide. The current rpm verifies clean and its
    `Requires` are Fedora-named (`qt6-qtbase`, `qt6-qtbase-gui`, `qt6-qtcharts`,
    `qt6-qtsvg`), so dnf resolves them from the distro repos. An existing
    extracted AppImage is torn out and replaced by the package on update;
    the AppImage remains as a fallback if the rpm install fails.
  - **openSUSE keeps the AppImage** — the rpm hard-requires those Fedora
    package names, which do not exist there, so zypper cannot resolve it.
  - **Debian gets a current build**, plus an explicit Qt6 runtime install: the
    upstream `.deb` declares **no `Depends` at all**, so apt pulled nothing while
    the binary needs libQt6Core/Gui/Widgets/Network/Charts. Names are tried
    individually and best-effort, since Debian's time_t transition renamed
    several of them with a `t64` suffix.
  - **Arch is unchanged** — `stacer-bin` already packaged this fork.

  Asset matching is now architecture-aware per artifact type, since the three
  differ in shape (`stacer_1.7.0-1_amd64.deb`, `stacer-1.7.0.x86_64.rpm`,
  `Stacer-1.7.0-x86_64.AppImage`) and the old code just excluded "arm". The
  AppImage desktop entry's icon path was corrected: the fork no longer ships a
  `stacer.png` at the root of the AppImage, only `icons/hicolor/<size>/apps/`,
  so the menu icon had silently broken. The Qt6 AppImage still bundles only
  `libqxcb.so` with no Wayland platform plugin, so the wrapper keeps pinning
  `QT_QPA_PLATFORM=xcb`.

- **Termius on Arch is now unpacked from the upstream `.deb` instead of built
  from the AUR**, the same native path the tool already used on
  Fedora/RHEL/openSUSE. `termius-deb` is not the plain repack its name suggests:
  it keeps only `resources/` (`app.asar` and friends), discards the Electron
  runtime that Termius ships, and execs the app on `electron21` instead —
  a release from September 2022 that went EOL around October 2023. Arch's repos
  carry `electron39`–`electron43` and nothing near 21, so that dependency could
  only come from `electron21-bin` in the AUR (last touched June 2024, four
  votes): an unpatched ~4-year-old Chromium under the program holding the user's
  SSH keys. The native unpack keeps upstream's own Electron, needs no AUR helper
  and no `AUR_ENABLED=true`, and picks up `$SHELL` on first run exactly as it
  does on Debian. Runtime dependencies for Arch (`gtk3`, `libnotify`, `nss`,
  `libxss`, `libxtst`, `xdg-utils`, `at-spi2-core`, `util-linux-libs`,
  `libsecret`, `mesa`, `alsa-lib`) were each verified to resolve in core/extra.
  A derivative that ever ships a real `termius` package in its own repos is
  still preferred and installed with plain `pacman`; the AUR is no longer a
  fallback, since a failed native install should report an error rather than
  quietly land the user on EOL Electron. Termius is consequently no longer
  marked AUR-only, so it stays visible in the menu with `AUR_ENABLED=false`.
  Existing `termius-deb` installs are left alone — it owns `/opt/termius`
  (lowercase), which never overlapped this tool's `/opt/Termius` — but installs
  and updates now warn that the leftover copy is a second menu entry still
  running Electron 21, with the `pacman -Rs` line to remove it. Uninstall
  already removed `termius-deb` by name and still does.
- **Flatpak Setup moved from System Tasks to the Package Managers category**,
  alongside Snap, Homebrew, Nix and the AUR/deb helpers — it is the same class
  of thing as those (a cross-distro manager running beside the native one), and
  unlike a true system task it already tracked real installed state and a
  version. It is registered with `register_utility` instead of
  `register_system_task` and listed first inside the category, since Bottles,
  BoxBuddy, DistroShelf, Boxflat, Duplicati and ProtonUp-Qt install through it.
  The name is unchanged, so `--install "Flatpak Setup"`, shell completions and
  existing custom profiles keep working; the Home Desktop profile now selects
  it with `_profile_select_for_install` (which skips it when Flatpak is already
  configured) rather than `_profile_select_task`. Prompts that pointed at "the
  'Flatpak Setup' system task" now point at the Package Managers category.

### Fixed

- **"System Updates" now updates applications installed from an upstream binary,
  which every package-manager run had been silently skipping.** When no package
  source carries an application, `arch_install_ordered` falls through to its
  upstream-binary tier and unpacks the vendor's own tarball, AppImage or `.deb`
  payload into place — on Arch this is the normal path, because the AUR tier
  stays disabled by default. Such a copy belongs to no package manager, so
  nothing in an update run ever touched it: on Arch, "System Updates" hands the
  whole job to `cachy-update`/`arch-update`, which covers pacman, the AUR and
  Flatpak and then reports "No update available" — true for what it manages, and
  misleading for everything it does not. The application's own updater kept
  advertising the new release, and **Visual Studio Code**'s tarball build has no
  self-update mechanism at all, so its Update button could only open the download
  page. The net effect was an app frozen at its install-time version while both
  the system updater and the app itself appeared to be working.
  - `mark_upstream_binary` (`lib/utilities.sh`) records each such utility against
    the path that exists *only* for that install route, so the check is a fact
    about the machine rather than an assumption about which install tier ran; a
    packaged copy replacing it removes the path and the entry stops matching.
    Registered for **Visual Studio Code**, **VSCodium**, **Mark Text**,
    **Standard Notes**, **PowerShell** and **Libation**.
  - `setup_system_updates` now calls `_system_updates_upstream_binaries` on both
    the Arch handoff path and the generic path, invoking each utility's already
    registered update function — the same route as updating it from the menu. A
    vendor that is unreachable produces a warning, not a failed run.
  - `pkg_snapshot` folds these versions into its hash alongside the Flatpak
    commit state. Without this a run that updated only an upstream binary still
    compared equal and reported "No package changes were made".
  - The pending-update count beside **System Updates** in the menu now includes
    these applications (shown as "N apps"). It was built from `checkupdates`/
    `pacman -Qu` and `fwupdmgr` alone, so it read zero while an upstream update
    was genuinely waiting — the same blind spot as the update run itself.
    `mark_upstream_latest` registers a per-utility lookup for the current
    published version (**Visual Studio Code** via the update API's
    `productVersion`, **Libation** via its GitHub release tag); results are
    cached under `${XDG_CACHE_HOME:-~/.cache}/linux_util/upstream-versions` for
    `PKG_CACHE_MAX_AGE_SECS` (default one hour), so the menu makes no vendor
    request per repaint. A failed lookup is never cached, so a brief outage
    cannot pin the count at zero.
  - **Visual Studio Code and Libation no longer re-download when already
    current.** Both installers unpacked the vendor's latest release
    unconditionally, so every update run refetched the build already on disk —
    roughly 330 MB for VS Code — and reported it as an update. Each now compares
    the installed version against the published one first and skips when they
    match. A version that cannot be determined still installs, so a failed
    lookup never suppresses a real update; `VSCODE_FORCE_REINSTALL=1` and
    `LIBATION_FORCE_REINSTALL=1` force the download.
  - **Libation now reports its version when installed from the upstream `.deb`
    payload.** `get_version_libation` only queried the package manager, which
    owns nothing on the unpacked-payload path, so the version showed as unknown
    — leaving it out of the snapshot hash and the update comparison. The
    installer now stamps the version from the `.deb`'s own control member, and
    an install predating that stamp is read from the shipped
    `AppScaffolding.dll` assembly version rather than forcing one needless
    re-download.

- **Documented category list now matches the code.** `CONTRIBUTING.md` now names
  all sixteen real category strings rather than the twelve the old README
  implied. `docs/utilities.md` carries a note recording that the catalogue is
  incomplete: 226 utilities and system tasks are registered in
  `lib/installers.sh` against 188 documented. Four whole categories — **File
  Managers**, **Firewalls**, **Login Screens**, **Window Managers** — have no
  table, and eight entries are missing from categories that do (Angry IP
  Scanner, Brave Debloat, LocalSend, PowerShell, Snapper GUI, fail2ban,
  Unattended Upgrades, GTK Window Fix). None of these were in the old README
  either; the gap was found by diffing the registry against the docs.

- **Claude Code installed but would not run — `claude` reported "claude native
  binary not installed".** npm 12 blocks package lifecycle scripts by default as
  a supply-chain hardening measure, so the `@anthropic-ai/claude-code`
  postinstall (`install.cjs`) never ran. That postinstall is what replaces the
  500-byte `bin/claude.exe` placeholder with the real ~215 MB native binary, so
  the package landed on disk complete — platform binary and all — but the only
  thing on `PATH` was the placeholder stub, whose entire job is to print that
  error. npm still exited 0 and the installer reported success, so the breakage
  was silent. Both `install_claude_code` and `update_claude_code` now run
  `install.cjs` directly after npm and then verify `claude --version` actually
  works, failing loudly with the repair command instead of trusting npm's exit
  code. The extra step is a no-op on npm versions that already ran the
  postinstall, so it is deliberately not gated on npm version or distro —
  distros adopt npm 12 at different times, and the same failure appears on any
  of them once they do.
- **Claude Code no longer reports a version number in the menu**, showing
  `(installed)` instead. `get_version_claude_code` shelled out to
  `claude --version`, which is exactly the call that fails when the native
  binary is missing, and the version string carried no information worth the
  extra process on every menu draw.

- **Installing Virt-Manager on Arch failed outright and then falsely reported
  success.** `bridge-utils` was dropped from the Arch repos, so the single
  `pacman -S` call aborted the whole transaction with `target not found:
  bridge-utils` and *nothing* — `virt-manager`, `libvirt`, `qemu-full` —
  installed. The installer ignored pacman's exit code and pressed on, so the
  next step (`usermod -aG libvirt`) failed with `group 'libvirt' does not
  exist`, and the run was still reported as "Successfully installed" before the
  health check caught the missing binary. Three changes: `bridge-utils` is
  removed from the Arch package list (`iproute2`, already a base dependency,
  provides the bridge tooling libvirt uses); every distro family's package-
  install step now returns non-zero on failure instead of continuing; and the
  `usermod` call is gated on the `libvirt` group actually existing — if it is
  missing the installer runs `systemd-sysusers` to apply the package's
  sysusers.d entry, and warns and skips rather than erroring if the group still
  is not there.

- **Every Flatpak update/uninstall failed the same way the Aug 22 install
  sweep fixed for installs**: `"Flatpak system operation Deploy not allowed
  for user"` (or `Uninstall`/`Undeploy`). That sweep put `sudo` on all 76
  `flatpak install` sites but never touched `update`/`uninstall`, which hit
  the identical polkit refusal for the same reason — Flathub is a *system*
  remote and every app in this project deploys system-wide, so an
  unprivileged `flatpak update`/`uninstall` can't get the system-helper to
  act on it. This showed up most visibly in **System Updates**, where the
  blanket `flatpak update -y` step failed outright on every runtime
  (`org.freedesktop.Platform.GL.default`, `.Locale`, etc.) with `Error: There
  were one or more errors`. All `update_x`/`uninstall_x` call sites across
  every Flatpak-based installer (~45 files) now try the unprivileged `--user`
  installation first (a silent no-op if nothing is user-scoped) and fall back
  to `sudo … --system`, matching the pattern already used by the Termius
  installer. The blanket calls in **System Updates** and **Flatpak Setup**'s
  own `update` action got the same two-step treatment. ClamAV, qBittorrent,
  and Termius already had a working sudo fallback and were left alone.

- **Installing VSCodium no longer leaves the menu hanging forever on
  "Checking installed utilities...".** The repo it writes sets
  `repo_gpgcheck=1`, so dnf verifies the repository metadata signature on every
  metadata refresh. The key was only ever imported with `rpm --import`, which
  populates **root's** rpm keyring — fine for `sudo dnf install`, but the menu's
  pending-update count runs **unprivileged**, against its own trust store in
  `~/.cache/libdnf5`, where the key was absent. dnf therefore stopped to ask
  `Importing OpenPGP key 0x5A278D9C ... Is this ok [y/N]:` and waited for an
  answer. That call is `_out=$("${PKG_MGR}" check-update 2>/dev/null)` — stdout
  captured by the command substitution, stderr discarded — so the question was
  never displayed and the script sat on a prompt nobody could see. It only
  reproduced with a terminal attached; with stdin closed dnf cannot prompt and
  fails in about a second, which is why it went unnoticed. `install_vscodium`
  now also accepts the key once for the installing user, non-interactively, so
  the prompt never arises. `metadata_expire=1h` is gone from the repo as well:
  expiry is not repo-local — any `check-update` refreshes every configured repo
  — so an hourly expiry forced a refresh on practically every invocation and
  turned a rare prompt into one on every startup. `repo_gpgcheck=1` is
  deliberately kept; the metadata signature is still verified.
- **JetBrains Toolbox now installs a working application instead of a launcher
  that dies on start.** The installer pulled the ~150 MB upstream tarball and
  then `find`-ed a single file out of it — `jetbrains-toolbox` — copying only
  that 1.2 MB stub into place and deleting the other 900-odd extracted files.
  But the archive is a self-contained bundle: `jetbrains-toolbox-<version>/bin/`
  holds the stub *plus* the JRE it runs on (`jre/`), its jars (`lib/`) and its
  native libraries. The stub is only a native loader that `dlopen()`s
  `bin/jre/lib/server/libjvm.so` relative to its own directory, so with the JRE
  discarded every launch aborted instantly with `Failed to start JVM` — visible
  only in `~/.local/share/JetBrains/Toolbox/logs/toolbox-native.log`, since the
  install ran in the background and reported success either way. The whole
  `bin/` tree is now copied with `cp -a`, and an unexpected archive layout is a
  hard error rather than a silent partial install. Only `bin/` is replaced on
  update; installed IDEs under `apps/` are untouched.
- **JetBrains Toolbox appears in the application menu right after install.**
  Toolbox writes its own `.desktop` entry, but only once it has started
  successfully — which, given the above, never happened, leaving no menu entry
  and no obvious way to launch it. The installer now writes the entry and
  installs the bundled `toolbox.svg` icon itself, then calls
  `refresh_desktop_caches`. `Exec=` is the absolute path to the binary rather
  than the `~/.local/bin` symlink, which desktop sessions do not reliably have
  on `PATH`. Uninstall removes the icon and the full Toolbox directory.
- **A half-installed JetBrains Toolbox is no longer reported as installed.**
  `check_jetbrains_toolbox` tested only for the stub's existence, so the broken
  tree above satisfied it — the TUI showed Toolbox as present and `--check`
  exited 0. It now requires the bundled `libjvm.so` as well, while still
  recognising a copy installed by other means elsewhere on `PATH`. The launch
  after install is also skipped when neither `DISPLAY` nor `WAYLAND_DISPLAY` is
  set, since starting a tray app over SSH just exits silently; the message then
  says how to start it later instead of claiming it is about to appear.
- **ClamAV's clamd daemon now actually starts on Fedora and RHEL.** Fedora ships
  `/etc/clamd.d/scan.conf` with every socket line commented out — the only active
  settings in the stock file are `LogSyslog` and `User` — so `clamd` exited
  immediately with "ERROR: Please define server type (local and/or TCP)" on every
  start, and systemd gave up after five restarts. `systemctl enable --now
  clamd@scan` was wrapped in `2>/dev/null || true`, so the enable "succeeded",
  the daemon was dead, and the install reported success. On-access scanning was
  silently unavailable, and front-ends reported the service as N/A. The installer
  now uncomments the `LocalSocket` line the packaged unit and its tmpfiles entry
  (`/run/clamd.scan`, 0710 clamscan:virusgroup) already expect, touching only the
  first of the two commented copies the stock file carries, and leaving any
  socket an admin has already defined alone.
  - **A daemon that fails to start is now reported instead of swallowed.** The
    enable is checked with `systemctl is-active`, and a dead unit prints the last
    error from the journal plus the `systemctl status` command to investigate,
    while making clear that on-demand `clamscan` is unaffected.

- **ClamAV no longer fails to install on Arch.** `clamtk` is AUR-only, so naming
  it in the same `pacman -S` call as `clamav` made the call fail as a unit and
  left the machine with no antivirus at all — the same in `update_clamav`, and
  `pacman -Rs` on uninstall. Arch installs the engine alone now and gets ClamUI
  as its GUI.
- **WPS Office installs again.** Every direct install had been failing with
  "Could not determine WPS Office download URL from linux.wps.com": that host
  now 301s to `www.wps.com/office/linux/`, a Nuxt single-page app whose HTML
  contains no package links at all, so the scrape for an `href` ending in
  `_amd64.deb` matched nothing. Four separate faults were in the way, each of
  which alone was enough to break the install:
  - **The download URL is now read from the page's entry JS bundle**, where the
    Deb and RPM buttons get their targets. Packages live under a per-build
    directory on `wdl1.pcfg.cache.wpscdn.com` and carry an `.XA` suffix
    (`.../linux/11723/wps-office_11.1.0.11723.XA_amd64.deb`). The bundle
    filename is content-hashed and changes on every site rebuild, so the entry
    `<script type="module">` is read out of the page rather than hardcoded. The
    resolved URL is checked with a HEAD request before the ~320 MB download
    starts, and falls back to a pinned known-good build if the scrape comes up
    empty — WPS ships Linux builds rarely, so a pin is a safety net rather than
    a stale-version trap. The `wps-linux-personal.wpscdn.cn` URLs also present
    in that bundle are the China-personal CDN and answer 403 from outside it,
    so they are not used.
  - **`dpkg -i` and `dnf localinstall` are replaced by `pkg_install_local`**,
    which hands the file to apt/dnf so dependencies resolve. `dpkg -i` cannot
    pull the dozen libraries the package needs, and `localinstall` was removed
    in dnf5 (Fedora 41+), which left the rpm branch falling through to a bare
    `rpm -i` that aborts on unresolved dependencies.
  - **`xdg-utils` is installed first.** The package's `postinst` calls
    `xdg-icon-resource` but declares no dependency on it, so on a minimal system
    the script dies with "command not found" (exit 127) and leaves the package
    half-configured (`iF` in `dpkg -l`), which apt then trips over on every
    later run.
  - **Fedora and RHEL now install the Flatpak.** Upstream's `.rpm` predates
    payload digests, so rpm 6 refuses it: dnf resolves all 24 dependencies and
    then aborts with "does not verify: no digest", with no bypass short of
    lowering `%_pkgverify_level` system-wide — the same wall the Stacer
    installer hit. Flathub carries the same upstream build, so the Flatpak is
    the working path; the `.rpm` remains a fallback for older rpm releases that
    still accept it. Uninstall and update follow the Flatpak on those distros
    too, so an installed copy no longer survives its own removal.

  Also on this installer: the **aarch64 branch was fiction** — it built
  `_arm64.deb` URLs that have never existed on the CDN (they 403), so it is
  replaced by the Flatpak where available and a clear error otherwise; the
  download is now checked with `verify_download` like every other installer
  here; and **`get_version_wps_office` no longer shells out to `dpkg`**, which
  only exists on Debian, so an installed WPS Office finally reports a version on
  Fedora and openSUSE instead of a blank.

- **`curl: (23) Failure writing output to destination` no longer appears during
  installs that scrape a download URL.** Five installers piped `curl` straight
  into a filter that stops at the first match — `grep -m1` in Pay Respects,
  `head -1` in JetBrains Toolbox, Go, WPS Office and PIA VPN. The filter exits
  the moment it has its line, closing the pipe while curl is still writing the
  rest of the body; curl ignores SIGPIPE and reports the short write as error 23
  on stderr instead of exiting quietly the way grep does. The URL was always
  correct and the installs succeeded — the message was pure noise — but it read
  as a failure in the log, and it only showed up when the transfer was slow
  enough to still be in flight, which is why it surfaced on remote machines and
  not locally. Each site now captures the response into a variable first and
  filters it afterwards, taking the first line with a parameter expansion so no
  stage of the pipeline exits early. As a side effect these lookups now return a
  meaningful exit status under `set -o pipefail`, where before a genuine network
  failure was visible only as an empty URL.

- **OCCT no longer runs its 207 MB binary on every menu render — and no longer
  segfaults doing it.** `check_installed_utilities` calls each utility's version
  function at startup, and OCCT's ran `occt --version`. That command produces no
  output at all (exit 0, nothing on stdout or stderr), so version detection could
  only ever return an empty string, while each call paid a full exec of the .NET
  single-file bundle. It was also crashing: OCCT's `main()` calls
  `IsAnotherLauncherRunning()` before it parses argv, which reads the PID that the
  previous run left in `/tmp/OCCTLAUNCHER.PID` (never cleaned up on exit),
  resolves `/proc/<pid>/exe`, and passes the result to `std::filesystem::path`
  with no null check — `strlen(NULL)`, SIGSEGV, and a coredump in the journal for
  every affected launch. Not every stale PID triggers it, so the crashes looked
  random. OCCT is now registered with no version function; its status line reads
  "Installed" with no version, which is what it effectively showed anyway.

- **`$SHELL` was empty in Termius terminals, breaking every tool that reads it.**
  Typing `toolbox create` in a Termius local terminal failed with "failed to get
  the current user's default shell" — Toolbx reads `os.Getenv("SHELL")` and
  refuses an empty value. The cause is Termius: it reads `$SHELL` to choose
  which binary to launch (correctly picking zsh), then removes it from the
  environment it hands the pty — the spawning helper process carries
  `SHELL=/usr/bin/zsh` while the zsh below it has the identical variable set
  minus `SHELL`. Nothing downstream restores it, because zsh does not set
  `$SHELL` itself; on a normal login PAM does. **Zsh + Oh My Zsh** now installs a
  guard into `~/.zshenv`:

  ```zsh
  [[ -n $SHELL ]] || export SHELL=${${:-/proc/$$/exe}:A}
  ```

  `.zshenv` rather than `.zshrc` because it is sourced before Oh My Zsh and the
  Powerlevel10k instant prompt block — both of which read `$SHELL` — and because
  it also covers non-interactive shells. Reading `/proc/$$/exe` reports the
  interpreter actually running rather than baking in a path that varies across
  the distro families this module supports, and zsh's `:A` modifier resolves it
  without forking, so shell startup pays nothing. The guard only fills a gap: a
  `$SHELL` that is already set is left alone, making it a no-op in Konsole,
  VS Code, SSH sessions, and scripts. It is applied on update as well as install,
  and removed on uninstall.

- **"Local Time Zone / Locale" could never generate a missing locale on Debian.**
  Picking `en_US` on a minimal Debian 13 image ran `locale-gen en_US.UTF-8`,
  which printed "Generating locales… Generation complete." and generated
  nothing, so the re-scan of `locale -a` reported "No matching locales found"
  and the task failed. Debian's `/usr/sbin/locale-gen` compares `$1` only
  against `--keep-existing` and otherwise **discards its arguments**, generating
  exactly the entries that are uncommented in `/etc/locale.gen` — on a cloud
  image, none. (Ubuntu ships a variant that does honour arguments, which is why
  this path looked correct.) The locale is now uncommented in, or appended to,
  `/etc/locale.gen` before `locale-gen` is run with no arguments, and the
  charset field is carried over from `/usr/share/i18n/SUPPORTED`, which
  `/etc/locale.gen` requires. If the locale is still absent afterwards the task
  says so instead of falling through to the generic "no matching locales"
  message.

- **Root-only tools in `/usr/sbin` were invisible to detection on Debian.**
  Debian's `/etc/profile` gives non-root users
  `/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games` — no sbin
  directories at all — while sudo finds those tools through its own
  `secure_path`. So `command -v locale-gen` was false even with the `locales`
  package installed (the task offered to install it every run, and apt answered
  "already the newest version"), and `command -v update-locale` was false too,
  which sent the locale write to `localectl` and straight into Debian's deny.
  New `_sbin_command` / `_have_sbin_cmd` helpers in `lib/pkg_manager.sh` search
  `/usr/local/sbin`, `/usr/sbin`, and `/sbin` after PATH and print the resolved
  path, which the caller then runs under sudo. The locale task uses them for
  `locale-gen` and `update-locale`.

- **Setting a locale could never succeed on Debian either.** Once the locale
  generated, `localectl set-locale` failed with "Failed to issue method call:
  Access denied". Debian ships
  `/usr/share/dbus-1/system.d/systemd-localed-read-only.conf`, which denies
  `locale1.SetLocale` to *every* caller including root — its own comment reads
  "On Debian and derivatives keymap/locales/etc are not set via localed... Ensure
  not even root can use it to modify the settings." There is no privilege that
  gets past it. The apply step now tries `update-locale` first and falls back to
  `localectl`: `update-locale` ships in the same `locales` package as
  `locale-gen`, writes `/etc/locale.conf` directly (`/etc/default/locale` is a
  symlink to it), and exists only on Debian/Ubuntu, so the ordering picks the
  right tool per distro without a distro test. `timedatectl set-timezone` was
  never affected — the deny covers `locale1` only.

- **Cancelling a task during a retry was logged as a failure.** The first
  attempt treats exit code 2 as "cancelled by user" and 3 as "succeeded, no
  changes", but the retry loop used a bare `if $func; then`, so choosing
  *Cancel* at a re-prompted menu produced "Retry 2/3 failed" and burned the
  remaining attempts. The retry path now reads the same exit codes as the first
  attempt. "Local Time Zone / Locale" is also `NO_RETRY` now — it is an
  interactive menu, so re-running it after a failure only asks the same
  questions again.

- **Every Flatpak install failed on systems with no polkit agent**, taking the
  Arch fallback ladder down with it. `ensure_flatpak` adds flathub as a *system*
  remote (`sudo flatpak remote-add`), so `flatpak install -y flathub <id>`
  deploys system-wide — but it was invoked unprivileged at all 76 call sites.
  An unprivileged process asking `flatpak-system-helper` to deploy is refused by
  polkit outright ("Flatpak system operation Deploy not allowed for user"), and
  it is refused *after* the whole download finishes: an attempted VS Code
  install pulled ~700 MB of runtime, was denied, and then did it twice more
  through the retry logic. All 76 sites now run under `sudo`, matching the
  Termius installer, which already handled this. The only bare `flatpak install`
  left is the advice string printed by the PIA VPN installer, where a user
  typing it interactively does get a polkit prompt.

- **Visual Studio Code could not be installed on Arch at all** once the Flatpak
  tier was failing. Microsoft publishes no pacman repository —
  `packages.microsoft.com` serves apt and yum repos only, and their Linux docs
  send Arch users to the AUR, which this tool keeps disabled — so the
  upstream-binary tier of `arch_install_ordered` was left empty and the ladder
  ran out of rungs. Microsoft does publish a distro-agnostic x64 tarball, and it
  is exactly what the AUR's `visual-studio-code-bin` repackages, so the Arch
  path now fetches it straight from the vendor: unpacked per-user to
  `~/.local/share/vscode`, symlinked to `~/.local/bin/code`, with a `.desktop`
  entry and the icon shipped inside the archive. Tier order is unchanged —
  repos → Flathub → **Microsoft tarball** → AUR (disabled) — so a derivative
  that carries the package in its own repos still wins. `check`, `update`,
  `uninstall` and version reporting all understand the tarball copy; the version
  is read from `resources/app/package.json` rather than by running the binary,
  since `~/.local/bin` is not always on PATH. Note the endpoint publishes no
  checksum or signature (the AUR PKGBUILD does not verify one either), so HTTPS
  to the vendor is the guarantee, as with the Termius and Zen Browser paths.
  The ~330 MB download calls `curl` directly with a 30-minute cap rather than
  going through `download_file`, whose 30-second `--max-time` is a *total*
  limit no download that size can meet — the same reason the OCCT installer
  bypasses it.

- **Steam failed to install on CachyOS** with "unresolvable package conflicts
  detected". Steam depends on the virtual `vulkan-driver` and
  `lib32-vulkan-driver`; nothing in a default install provides them, because
  `mesa` provides `opengl-driver` and `libva-driver` but not `vulkan-driver`. So
  pacman must pick a provider, and `--noconfirm` makes it take the first one
  offered — which repo order decides, not suitability. On plain Arch that list
  starts at `extra` and any pick works, which is why other distros never showed
  this. CachyOS inserts `cachyos-v3` and `cachyos` ahead of `extra` and they
  carry `mesa-git`, so provider #1 became `mesa-git`/`lib32-mesa-git`, whose
  `conflicts=('mesa')` collides with the stable `mesa` CachyOS itself installed,
  aborting the transaction. Being deterministic, all three retries reproduced it
  exactly. The dependency is now settled explicitly *before* Steam is requested,
  using `pacman -T` to leave an existing provider alone and otherwise installing
  `vulkan-swrast` (Lavapipe) — a software rasteriser that needs no GPU, so it
  works in a VM, headless, or on any hardware, and conflicts with nothing.
  **Installing Steam no longer depends on what graphics hardware is present.**
  A matching hardware driver is added afterwards as a pure optimisation that can
  never fail the install; a virtual adapter (QXL, VMware SVGA, Bochs, VirtualBox)
  matches nothing and correctly stays on software rendering. This also replaces
  a shotgun `lib32-vulkan-intel lib32-vulkan-radeon lib32-nvidia-utils` install
  that pulled the NVIDIA stack onto AMD machines and, with `2>/dev/null || true`,
  silently installed nothing whenever one name in the batch failed.
- **Enable RDP could not install on Arch, and reported success anyway.** The
  Arch branch ran `pacman -S --noconfirm xrdp`, but `xrdp` is AUR-only (152
  votes) and absent from Arch's repos and from CachyOS's, so it could only fail
  with "target not found". `xorgxrdp` — also AUR-only — was never installed at
  all, and without it sesman has no Xorg backend and logins fail with "X server
  could not be started", the same reason the Fedora branch installs it
  explicitly. Both now go through `repo_or_aur`, which still probes the repos
  first. Nothing checked any of the results, so the installer printed "xrdp
  installed and started" after the failed install and failed `systemctl`, and
  the runner logged "Successfully installed: Enable RDP" for a machine with no
  xrdp on it — only the health check dissented. The Arch branch now fails on a
  bad install or a failed enable/start, and a final `systemctl is-active` gate
  applies to **every** family, so success is never reported for a service that
  is not running. Enable RDP is marked AUR-only on Arch accordingly.

- **Mark Text on Arch ran on Electron 15, and its Debian download never
  worked.** The `marktext` AUR package pins `_electron=electron15` and rewrites
  `package.json` so the app runs on that system runtime instead of the Electron
  upstream bundles. Electron 15 shipped September 2021 and went EOL in May 2022;
  Arch carries `electron39`–`electron43`, so the dependency resolves only from
  AUR `electron15` (last touched **2022-08-31**) or `electron15-bin` — about
  four years of unpatched Chromium, reached through a from-source
  yarn/`electron-rebuild` build, stuck at 0.17.1, and flagged out-of-date since
  2026-07-10 while upstream is at 0.19.1. Flathub remains the first choice on
  every family; where Flatpak is absent, Arch now unpacks upstream's own
  `.tar.gz` per-user into `~/.local/share/marktext` — root-free, carrying the
  Electron Mark Text actually ships, and avoiding the AppImage runtime's
  `libfuse.so.2` dependency the same way `stacer.sh` does. Separately, the
  Debian branch asked for `marktext-amd64.deb`, a filename upstream has never
  published — assets are named `marktext-linux-0.19.1.deb` — so every Debian
  install silently 404'd into the Flatpak fallback. Both now resolve the asset
  URL from the release API.
- **Pay Respects no longer needs the AUR on Arch.** The `pay-respects-bin`
  package was sound — its maintainer, `iff`, is upstream — but it was never
  necessary: upstream publishes a static-pie musl tarball carrying the same
  binaries, so there is nothing to build and no dependency to resolve. Arch now
  unpacks that into `/usr/local` (not `/usr`, since pacman does not own these
  files), mirroring upstream's own `.deb` layout — all three binaries on `PATH`,
  man pages beside them — so every family ends up with the same arrangement and
  module discovery keeps working off the `_pay-respects-*` naming convention
  with no `_PR_LIB` wiring. A derivative that packages it is still preferred.
  Pay Respects is consequently no longer marked AUR-only and stays visible with
  `AUR_ENABLED=false`.

- **Five Arch installers named AUR packages that no longer exist**, three of
  them fatally. `repo_or_aur` only checks whether pacman can resolve a name
  before falling back to the AUR — it never verified the AUR package was still
  there, so each of these cloned `aur.archlinux.org/<pkg>.git` for a repository
  that has been deleted and failed:
  - **ProtonVPN** asked for `protonvpn`, gone from the AUR (only unrelated
    community forks like `protonvpn-cli-community` remain). Arch packages the
    real app in **extra as `proton-vpn-gtk-app`** — binary `protonvpn-app`,
    pulling `proton-vpn-daemon` and the `python-proton-*` stack as proper
    dependencies — so it now installs with plain `pacman`, needs no AUR helper,
    and is no longer marked AUR-only. `check_`/`get_version_` learned the Arch
    package name, which differs from the `proton-vpn-gnome-desktop` that
    Proton's own apt/dnf repos ship.
  - **PIA VPN** asked for `privateinternetaccess-bin`, gone with no replacement
    under any similar name. It now uses upstream's `.run` bundle — the same
    `_pia_install_via_run` this file already used for Debian/Fedora/RHEL.
  - **Snapper GUI** asked for `snapper-gui`, which has never existed as an Arch
    package at all; only `snapper-gui-git` does (51 votes, ordinary current
    dependencies). This one stays AUR-only, and legitimately so: upstream
    `ricardomv/snapper-gui` is a frozen Python/GTK source tree with no releases
    and no binary artifacts, so there is nothing to install directly. `update_`
    now rebuilds through the AUR helper rather than calling `pkg_upgrade`, which
    cannot move a `-git` package.
  - **LibreWolf** asked for `librewolf-bin`, gone. `librewolf` is in **extra**,
    so Arch now installs it from the repos, with Flathub kept as the fallback
    for a derivative that lacks it.
  - **Standard Notes** asked for `standard-notes-bin`, gone. Flathub stays the
    first choice; when Flatpak is absent it now falls back to upstream's
    AppImage, which this file already used on every other family, instead of a
    dead AUR clone.

  Each uninstaller still tries the old AUR name so installs predating this
  change are cleaned up. Separately, PIA VPN's uninstall now runs
  `/opt/piavpn/bin/uninstall.sh` when present, on **every** family: the `.run`
  bundle never registers with a package manager, so the previous
  `apt purge`/`dnf remove` of `privateinternetaccess` could not have removed a
  bundle-installed copy on Debian or Fedora either.
- **Arch installs now use the distro's own repos before falling back to the
  AUR.** 33 installers called `aur_ensure` directly, so on an Arch derivative
  that packages the software itself the tool ignored the repo build and demanded
  an AUR helper plus `AUR_ENABLED=true`. CachyOS ships `brave-bin`,
  `brave-origin-bin`, `zotero` and other AUR-named packages in its own repos,
  where `sudo pacman -S brave-bin` just works — but Brave Browser, Brave Origin, Google
  Chrome, VS Code and the rest of the AUR-only list were hidden from the menu
  entirely and unreachable. Every one of those call sites now goes through
  `repo_or_aur`, which tries `pacman -S --needed` first and only reaches for the
  AUR when the package is genuinely absent from the configured repos. The
  hand-rolled `has_aur_helper`/`aur_install`/`aur_build` branches in Devolutions
  RDM, Boxflat and PIA VPN were folded into the same helper; PIA VPN no longer
  dead-ends with "requires an AUR helper" on a system whose repos carry the
  package. Behaviour on upstream Arch is unchanged.
- **AUR-only entries stay visible when the local repos carry the package.**
  `_utility_hidden_aur_only` hid every entry marked AUR-only whenever
  `AUR_ENABLED=false`, without ever asking pacman whether the package existed —
  correct for upstream Arch, wrong for derivatives with a larger repo set. Each
  entry in `mark_aur_only_arch` now carries its package name
  (`"Brave Browser=brave-bin"`), and the gate skips hiding when the new
  `arch_repo_has` helper finds it in a configured repo. Probe results are cached
  per run, since the menu re-evaluates the gate on every redraw.
- **`flatpak_or_aur` prefers a native repo package over Flathub.** A distro-
  signed package needs no runtime stack and no unreviewed PKGBUILD, so it is now
  tried first, ahead of both Flatpak and the AUR; it takes an optional third
  argument for when the repo name differs from the AUR name. Systems without the
  package in their repos are unaffected. Boxflat, whose Flatpak-first logic sits
  in its own installer, follows the same order.
- **Arch installs of Brave and friends no longer report as "not installed".**
  `check_brave` tested for a `brave-browser` binary and package, but the Arch
  package is `brave-bin` and its binary is `brave`, so a successful install still
  showed unchecked in the menu. `_check_standard` takes optional Arch package and
  binary names, consulted only under pacman, and Brave Browser, Brave Origin,
  AnyDesk, Stacer, PowerShell, VS Code and Google Chrome now pass their Arch
  package names.
- **Angry IP Scanner installs on Arch again, without the AUR.** `ipscan` is not
  in the Arch or CachyOS repos — only the AUR, which this tool keeps disabled, so
  the entry was hidden and unreachable on Arch family. Upstream also publishes a
  self-contained JAR next to the .deb and .rpm, and the Arch branch now installs
  that: `ipscan-linux64-<ver>.jar` into `~/.local/share/angry-ip-scanner`, with a
  wrapper at `~/.local/bin/ipscan`, a menu entry, and the icon extracted from the
  JAR itself. No root, no AUR, no packaging. The JAR bundles its own SWT/GTK
  natives and needs only a JRE; its classes target Java 17, so `_angry_ip_ensure_java`
  installs one from the distro's repos when java is missing or older. Angry IP
  Scanner is no longer marked AUR-only, so it lists normally on Arch. Downloads
  are checked with the existing `verify_download`/`github_verify_checksum` pair,
  which gained a `jar` magic-byte case.
- **Uninstalling Angry IP Scanner on Arch targeted the wrong package name.**
  Install and update use `ipscan`, but the Arch branch of the uninstall tried
  `angryipscanner` first — a name nothing in the file installs — and the failure
  was hidden by the trailing `|| true`. It now removes the JAR install and then
  any older package-based copy, trying `ipscan` before the legacy `angryipscanner`.
- **Gufw is now offered only on the distro families that can install it —
  Debian/Ubuntu and Arch.** No RPM-family distro packages it: it is absent from
  Fedora, EPEL 9 and 10, openSUSE Tumbleweed and openSUSE Leap (verified against
  each distribution's own repository metadata), and there is no Flatpak or COPR
  build either, so the entry could only ever fail there. It is now registered
  behind a distro-family guard, the same way Snapper GUI already was. Users on
  those distros wanting a firewall GUI need firewalld with its firewall-config
  front-end, both listed in the same Firewalls subcategory. UFW itself is
  unaffected and still fully supported on all of them from the command line.
- **A failed Gufw install now reports as a failure.** The Fedora branch of
  `install_gufw` ran `dnf install -y gufw` without checking the result, and the
  function ended with an unconditional `info "Gufw installed."`, so it returned 0
  even when dnf had said `No match for argument: gufw` — the failure surfaced
  only afterwards, as a health-check warning, and the summary counted the
  install as successful. Every branch now propagates its package manager's
  failure, and the RPM-family branches warn and return 1 as a safety net for
  direct calls now that the entry is unregistered there.
- **A failed UFW install no longer reports success either.** `install_ufw`
  ignored its package manager's exit status too, then went on to run `ufw
  default deny incoming` and friends against a binary that might not exist, and
  returned 0 regardless. That also defeated the `install_ufw || return 1` guard
  `install_gufw` uses to pull UFW in first. Each branch now propagates failure.
- **UFW on openSUSE no longer silently installs firewalld in its place.** On
  Leap 15.6 and older, where `ufw` is not in the repos, `install_ufw` quietly
  installed and enabled firewalld instead and returned success — so the run
  summary reported "Successfully installed: UFW Firewall" for a machine that had
  just been given a different firewall the user never chose. It now explains
  that this openSUSE version does not ship UFW, points at the firewalld entry in
  the same category, and returns 1. Tumbleweed and Leap 16.0 do ship `ufw` and
  are unaffected.
- **UFW's systemd unit is now started, not just enabled.** `ufw --force enable`
  loads the rules into netfilter itself but leaves `ufw.service` inactive, so
  `systemctl is-active ufw` reported `inactive` on a freshly installed and
  working firewall until the next reboot. The install now uses `systemctl enable
  --now ufw`, matching the `enable --now` the firewalld installer already used.

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
