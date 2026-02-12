# Tools

Unified toolkit for tmux session management and system cleanup on Linux.

## Install

```bash
git clone <repo-url> ~/tools
cd ~/tools
./install.sh
```

This adds `~/tools/bin` to your PATH. No files are copied elsewhere.

To uninstall everything (PATH entries, wrappers, caches):

```bash
./install.sh uninstall
```

## Session Manager

YAML-based tmux session orchestration with independent subsessions.

```bash
session myproject                # Start/attach
session myproject --headless     # Start in background
session myproject backend        # Attach to subsession
session myproject status         # Show what's running
session myproject kill           # Tear down everything
session myproject restart api    # Restart one subsession
```

### Register a project as a command

```bash
session install /path/to/whatever.yaml
# Reads the `name:` field from inside the YAML
# Creates ~/.local/bin/<name> wrapper
```

### Config format

```yaml
name: myproject
timezone: America/New_York
show_utc: true
color: colour33                # Any valid tmux colour

subsessions:
  backend:
    dir: ./api                 # Resolved relative to config file
    command: npm run dev
    delay: 5

windows:
  - name: dev
    dir: ./src
    color: colour46
    panes:
      - type: command
        cmd: nvim
        execute: true
      - type: subsession
        subsession: backend
```

Config files can be named anything. The `name` field inside the YAML is what matters.

## Cleanup Utility

Modular system cleanup with dry-run support and YAML configuration.

```bash
cleanup                    # Interactive with prompts
cleanup --dry-run          # Preview what would be cleaned
cleanup --auto             # No prompts for safe targets
cleanup --update           # Also run apt/snap/npm updates
cleanup --config file.yaml # Custom config
```

## File Structure

```
tools/
├── bin/
│   ├── session            # Session manager entry point
│   ├── cleanup            # Cleanup utility entry point
│   └── self-update        # Git pull + reinstall
├── lib/
│   ├── session/
│   │   ├── core.sh        # Session orchestration
│   │   └── subsession-manager.sh
│   ├── cleanup/
│   │   ├── common.sh      # Shared helpers, dry-run support
│   │   ├── config.sh      # YAML config loader
│   │   ├── vscode.sh      # VS Code Server cleanup
│   │   ├── nodejs.sh      # NPM/pnpm/node_modules
│   │   ├── system.sh      # Journals, APT, temp files
│   │   ├── dev-tools.sh   # Docker, Wrangler, Volta, etc.
│   │   └── updates.sh     # apt/snap/flatpak/npm updates
│   └── common/
│       └── yaml-parser.sh # Pure-bash YAML parser
├── config/examples/       # Example configs
├── docs/                  # SESSION.md, CLEANUP.md
├── scripts_legacy/        # Old bash session manager, migration tool
├── install.sh             # Installer / uninstaller
└── .gitignore
```

## What gets installed where

| Location | Contents | Uninstall removes? |
|----------|----------|--------------------|
| `~/tools/bin/` in PATH | Core commands (session, cleanup, self-update) | PATH entry removed |
| `~/.local/bin/<name>` | Project wrappers from `session install` | Yes |
| `~/.config/tools/` | User config directory | Yes |
| `~/.cache/tools/` | Runtime temp files (tmux configs) | Yes |

Nothing else. No copies of the repo. No global installs.

## Requirements

- Linux (or macOS)
- tmux
- bash 4.0+

## Docs

- [Session Manager](docs/SESSION.md)
- [Cleanup Utility](docs/CLEANUP.md)
