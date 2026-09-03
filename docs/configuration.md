# Configuration and Logging

## Configuration

Copy the example config and edit as needed:

```bash
cp linux_util.conf.example linux_util.conf
```

| Setting | Default | Description |
|---------|---------|-------------|
| `log_retention_days` | `30` | Days to keep log files |
| `max_log_size_mb` | `50` | Maximum log file size in MB |
| `max_logs_per_day` | `15` | Maximum log files per day |
| `compress_old_logs` | `true` | Compress older log files |
| `log_level` | `INFO` | Log level: `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `auto_confirm` | `false` | Skip confirmation prompts |
| `retry_failed` | `true` | Retry failed installations |
| `retry_attempts` | `3` | Number of retry attempts |
| `dns_check_enabled` | `true` | Check DNS connectivity at startup |
| `dns_timeout_seconds` | `10` | DNS check timeout |
| `dns_check_host` | `1.1.1.1` | Host used for the connectivity check. Override if Cloudflare is blocked on your network; a fallback to `9.9.9.9` is always tried |
| `disk_min_mb` | `1024` | Minimum free disk space (MB) before allowing installs |
| `update_channel` | `main` | Which stream self-update follows: `main` (releases only), `dev` (continuous), or a release tag such as `v1.3.1` to pin |
| `auto_cleanup` | `true` | Automatic cleanup of temp files |
| `verbose` | `false` | Enable verbose output |
| `debug` | `false` | Enable debug output |

### Update channel

`update_channel` controls what the **Self Update** utility does:

- `main` — follow released versions only. This is the default.
- `dev` — follow the development branch. Newer, may be unstable.
- a release tag, e.g. `v1.3.1` — pin to that exact release. Self-update checks
  the tag out and then makes no further changes. The header still shows when a
  newer release exists, so a pin is never silent.

Switching between `main` and `dev` moves you onto that branch on the next
self-update run. A manual `git checkout` always takes precedence: if you have
checked out a tag or commit by hand, self-update leaves you there and says so,
rather than dragging you back onto the configured channel.

## Logging

Every run creates timestamped log files in `logs/`:

- `success_YYYYMMDD_HHMMSS.log` — successful operations
- `error_YYYYMMDD_HHMMSS.log` — errors and warnings (only created if needed)
- `success_latest.log` / `error_latest.log` — symlinks to the most recent logs

Use `manage_logs.sh` for log management:

```bash
./manage_logs.sh list             # list all log files
./manage_logs.sh view latest      # view latest logs
./manage_logs.sh tail success     # follow a log in real time
./manage_logs.sh search "Docker"  # search logs
./manage_logs.sh stats            # show statistics
./manage_logs.sh clean 30         # remove logs older than 30 days
./manage_logs.sh compress         # compress old logs
```

## Shell Completions

Tab-completion scripts for bash and zsh are provided in the `completions/` directory.

### Bash

```bash
# Source for the current session
source completions/linux_util.bash

# Install system-wide (requires root)
sudo cp completions/linux_util.bash /etc/bash_completion.d/linux_util

# Or install for your user only
mkdir -p ~/.local/share/bash-completion/completions
cp completions/linux_util.bash ~/.local/share/bash-completion/completions/linux_util
```

### Zsh

```zsh
# Add the completions directory to fpath (add this to ~/.zshrc)
fpath=(/path/to/linux_util/completions $fpath)
autoload -Uz compinit && compinit

# Or install system-wide
sudo cp completions/_linux_util /usr/local/share/zsh/site-functions/_linux_util

# Or install for your user only
mkdir -p ~/.zsh/completions
cp completions/_linux_util ~/.zsh/completions/_linux_util
# Add to ~/.zshrc:  fpath=(~/.zsh/completions $fpath)
```

Once installed, tab-completing `./linux_util.sh --install <TAB>` lists all available utility names.
