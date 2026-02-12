# Cleanup Utility

Modular system cleanup with YAML configuration, dry-run support, and optional system updates.

## Usage

```bash
cleanup                          # Interactive with prompts
cleanup --dry-run                # Preview what would be cleaned
cleanup --auto                   # Auto-clean safe targets, no prompts
cleanup --config file.yaml       # Use custom YAML config
cleanup --update                 # Also run system/tool updates
cleanup --verbose                # Detailed output
```

Flags combine freely:

```bash
cleanup --dry-run --update       # Preview cleanup + updates
cleanup --auto --config my.yaml  # Auto with custom config
```

## What it cleans

### VS Code Server
- Old extension versions (keeps latest)
- CLI and bin folders
- Cached data, old server installations
- Log files older than retention period
- Old workspace storage and backups

### Node.js
- NPM cache (`~/.npm`)
- pnpm store (`~/.pnpm-store`)
- Orphaned `node_modules` (no parent `package.json`)
- Accidental `~/node_modules`

### System
- systemd journals (vacuums to 100MB)
- APT cache and autoremove
- Rotated log files (`.gz`, `.old`, `.1-9`)
- Large logs (>500MB, with confirmation)
- User cache directories

### Development tools
- Playwright browser cache
- Claude CLI cache
- code-server cache and backups
- Old Claude CLI versions (keeps latest)
- Duplicate Next.js binaries (wrong arch)
- Old Volta Node/npm/yarn/pnpm versions
- Docker unused resources

### Wrangler
- Log files older than retention period
- Temp files

## System updates (`--update`)

When `--update` is passed:

- **APT**: `apt-get update` + `apt-get upgrade` (with confirmation)
- **Snap**: `snap refresh`
- **Flatpak**: `flatpak update`
- **npm globals**: `npm update -g`

All respect `--dry-run` and `--auto` flags.

## Configuration

### Config lookup order

1. `--config <file>` — explicit path
2. `$CLEANUP_CONFIG` — environment variable
3. `~/.config/tools/cleanup.yaml` — default location
4. Built-in defaults (everything enabled)

### Config format

```yaml
# Retention settings
log_retention_days: 7
backup_retention_days: 30

# Target toggles — set to false to skip
vscode_enabled: true
nodejs_enabled: true
docker_enabled: true
system_enabled: true
wrangler_enabled: true
dev_tools_enabled: true
```

## Dry-run mode

Preview all actions without making changes:

```bash
cleanup --dry-run
```

Output shows `[DRY-RUN] Would: ...` for every action that would be taken, with sizes.

## Auto mode

Skip all confirmation prompts. Safe targets are cleaned automatically:

```bash
cleanup --auto
```

## Architecture

The cleanup utility is split into focused modules under `lib/cleanup/`:

| Module | Handles |
|--------|---------|
| `common.sh` | Helpers, `safe_rm()`, dry-run/auto logic |
| `config.sh` | YAML config loading, target toggles |
| `vscode.sh` | VS Code Server cleanup |
| `nodejs.sh` | NPM/pnpm, orphaned node_modules |
| `system.sh` | Journals, APT, pip, temp files, logs |
| `dev-tools.sh` | Docker, Wrangler, Volta, Playwright, etc. |
| `updates.sh` | apt/snap/flatpak/npm global updates |

`bin/cleanup` sources all modules and orchestrates based on config.
