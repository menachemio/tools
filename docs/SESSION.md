# Session Manager

YAML-based tmux session management with smart subsession handling.

## Overview

The session manager separates **what runs** (subsessions) from **how it's displayed** (windows). This allows:

- Independent subsession lifecycle management
- Flexible window layouts that reference subsessions
- Direct subsession access for development workflow
- Resilient session recovery and restart

## Configuration

Session configs use YAML with any filename. The `name` field inside the YAML is authoritative.

```yaml
name: myproject
timezone: America/New_York
show_utc: true
color: colour33                  # Any valid tmux colour value

subsessions:
  backend:
    dir: ./api                   # Resolved relative to config file
    command: npm run dev
    env: |
      PORT=3000
      NODE_ENV=development
    delay: 0

  frontend:
    dir: ./web
    command: npm start
    delay: 10

windows:
  - name: dev
    dir: .
    color: colour46
    panes:
      - type: command
        cmd: nvim
        execute: true
      - type: subsession
        subsession: backend
      - type: subsession
        subsession: frontend
```

### Config discovery

When running `session <name>` without an installed wrapper:

1. `./<name>.session.yaml`
2. `./.session.yaml`
3. `./.session/config.yaml`
4. `~/.config/tools/sessions/<name>.yaml`

When running an installed command (e.g. `myproject`), the wrapper passes the config path directly. Filename doesn't matter.

### Register a project

```bash
session install /any/path/whatever.yaml
# Reads name: from inside the YAML, creates ~/.local/bin/<name>
```

## Commands

```bash
session myproject                    # Start/attach
session myproject --headless         # Start in background
session myproject backend            # Attach to subsession
session myproject backend --headless # Start subsession in background
session myproject status             # Show all sessions
session myproject stop               # Stop main (keep subsessions)
session myproject kill               # Kill everything (with confirm)
session myproject restart            # Restart entire session
session myproject restart backend    # Restart one subsession
```

## Subsessions

Independent tmux sessions that persist across window operations.

```yaml
subsessions:
  api-server:
    dir: ./api
    command: npm run dev
    delay: 5
    env: |
      PORT=3000
      NODE_ENV=development
```

- **Auto-start**: Created when referenced by windows
- **Independent**: Run without windows attached
- **Persistent**: Continue running even if windows close
- **Resumable**: Attach/detach freely

## Pane types

### Command panes

```yaml
panes:
  - type: command
    cmd: nvim
    execute: true       # Run immediately
    history: true       # Add to bash history

  - type: command
    cmd: "git status"
    execute: false      # Pre-fill only, wait for Enter
```

### Subsession panes

```yaml
panes:
  - type: subsession
    subsession: backend
```

## Layouts

Automatic by pane count:

- **1**: Full window
- **2**: 50/50 horizontal split
- **3**: Left 50% | right top/bottom
- **4**: 2x2 tiled grid
- **5+**: Tiled layout

## Colors

Colors must be valid tmux colour values. Examples:

```yaml
color: colour33     # Blue
color: colour196    # Red
color: colour46     # Green
color: colour226    # Yellow
color: colour202    # Orange
color: colour51     # Cyan
color: white
color: default
```

Run `tmux show -s | grep default-terminal` to check your terminal's color support. Use `colour0`-`colour255` for 256-color mode.

## Timezone display

```yaml
timezone: America/New_York
show_utc: true
```

Status bar shows: `14:30 EST [19:30 UTC]`

## Validation

The session manager validates configs before creating anything:

- `name` field must exist
- At least one window required
- Each window must have at least one pane
- Subsession pane references must point to defined subsessions
- Directories must exist before subsession creation

## Troubleshooting

```bash
# Check what's running
session myproject status

# Restart a stuck subsession
session myproject restart backend

# Verbose output
session myproject --verbose

# Kill everything and start fresh
echo y | session myproject kill
session myproject
```
