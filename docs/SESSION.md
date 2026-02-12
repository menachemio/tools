# Session Manager Documentation

The Session Manager provides YAML-based tmux session management with smart subsession handling.

## Overview

The session manager separates **what runs** (subsessions) from **how it's displayed** (windows). This allows:

- Independent subsession lifecycle management
- Flexible window layouts that reference subsessions
- Direct subsession access for development workflow
- Resilient session recovery and restart capabilities

## Configuration Format

Session configurations use YAML format with `.session.yaml` extension.

### Basic Structure

```yaml
# Session metadata
name: myproject
timezone: America/New_York
show_utc: true
color: blue

# Define what can run independently
subsessions:
  backend:
    dir: ./api
    command: npm run dev
    env: |
      PORT=3000
      NODE_ENV=development
    delay: 0
  
  frontend:
    dir: ./web
    command: npm start
    delay: 10

# Define how things are displayed  
windows:
  - name: dev
    dir: .
    color: green
    panes:
      - type: command
        cmd: nvim
        execute: true
      - type: subsession
        subsession: backend
      - type: subsession
        subsession: frontend
```

### Configuration Discovery

The session manager searches for configurations in this order:

1. `./[session-name].session.yaml` - Project-specific config
2. `./.session.yaml` - Generic project config
3. `./.session/config.yaml` - Hidden config directory
4. `~/.config/tools/sessions/[session-name].yaml` - User config directory

## Command Interface

### Basic Usage

```bash
# Start/attach to main session
session myproject

# Start session in background
session myproject --headless

# Start/attach to specific subsession
session myproject backend

# Start subsession in background
session myproject backend --headless
```

### Session Management

```bash
session myproject status          # Show session status
session myproject stop            # Stop main session (keep subsessions)
session myproject kill            # Kill all sessions (with confirmation)
session myproject restart         # Restart entire session
session myproject restart backend # Restart specific subsession
```

## Subsessions

Subsessions are independent tmux sessions that can run with or without windows attached.

### Subsession Configuration

```yaml
subsessions:
  api-server:
    dir: ./api                    # Working directory
    command: npm run dev          # Command to run
    delay: 5                      # Wait 5 seconds before starting
    env: |                        # Environment variables
      PORT=3000
      NODE_ENV=development
      DEBUG=*
```

### Subsession Lifecycle

- **Auto-start**: Subsessions start automatically when referenced by windows
- **Independent**: Run without windows attached
- **Persistent**: Continue running even if windows close
- **Resumable**: Attach/detach from subsessions freely

### Direct Subsession Access

```bash
session myproject api-server      # Attach to api-server subsession
session myproject api-server --headless  # Start without attaching
```

## Windows and Panes

Windows define the tmux layout and how subsessions/commands are displayed.

### Pane Types

#### Command Panes

```yaml
panes:
  - type: command
    cmd: nvim
    execute: true       # Run immediately
    history: true       # Add to bash history
  
  - type: command  
    cmd: "git status"
    execute: false      # Type but don't run (wait for Enter)
    history: false      # Don't add to history
```

#### Subsession Panes

```yaml
panes:
  - type: subsession
    subsession: backend   # Reference to subsession name
```

### Window Layouts

Pane layouts are automatically determined by pane count:

- **1 pane**: Full window
- **2 panes**: 50% horizontal split
- **3 panes**: Left 50% | Right top 25% | Right bottom 25%
- **4 panes**: 25% each in 2x2 grid
- **5+ panes**: Tiled layout

### Window Colors

```yaml
windows:
  - name: development
    color: green        # Simple color name
    # or
    color: colour46     # Tmux color code
```

Supported color names: `red`, `green`, `blue`, `yellow`, `orange`, `purple`, `cyan`

## Advanced Features

### Headless Mode

Start everything in background without attaching:

```bash
session myproject --headless
```

This:
- Starts all defined subsessions
- Creates main session with windows
- Runs in background (no tmux attachment)
- Later use `session myproject` to attach

### Session Colors and Theming

```yaml
# Session-level color (master session status bar)
color: orange

windows:
  - name: api
    color: blue     # Window tab color
  - name: web
    color: green
```

### Timezone Display

```yaml
timezone: America/New_York    # Primary timezone
show_utc: true               # Also show UTC time
```

Status bar shows: `14:30 EST [19:30 UTC]`

### Environment Variables

```yaml
subsessions:
  backend:
    env: |
      PORT=3000
      NODE_ENV=development
      DEBUG=api:*
      DATABASE_URL=postgresql://localhost/mydb
```

## Migration from Bash Configs

Convert existing bash session configs:

```bash
# Convert single config
tools/scripts/migrate-to-yaml.sh old-config.sh new-config.yaml

# The migration script will:
# - Extract session metadata
# - Convert windows and panes
# - Identify subsessions
# - Generate YAML equivalent
```

## Examples

### Simple Web Development

```yaml
name: webapp
color: blue

subsessions:
  server:
    dir: ./backend
    command: npm run dev
  
  client:
    dir: ./frontend
    command: npm start
    delay: 5

windows:
  - name: code
    panes:
      - type: command
        cmd: nvim
        execute: true
      - type: subsession
        subsession: server
      - type: subsession
        subsession: client
```

### Microservices Project

```yaml
name: microservices  
color: orange

subsessions:
  auth:
    dir: ./auth-service
    command: go run main.go
    env: |
      PORT=8001
  
  gateway:
    dir: ./api-gateway
    command: npm run dev
    env: |
      PORT=8000
    delay: 3
  
  database:
    dir: .
    command: docker-compose up -d

windows:
  - name: services
    panes:
      - type: subsession
        subsession: auth
      - type: subsession
        subsession: gateway
      - type: subsession
        subsession: database
      - type: command
        cmd: "docker ps"
        execute: false

  - name: monitoring
    panes:
      - type: command
        cmd: "watch docker stats"
        execute: true
      - type: command
        cmd: htop
        execute: true
```

## Tips and Best Practices

1. **Project-specific configs**: Keep `.session.yaml` in project root
2. **Subsession naming**: Use descriptive names like `api-server`, `web-client`
3. **Delay coordination**: Stagger subsession starts with `delay` for dependencies
4. **Environment isolation**: Use `env` block for subsession-specific variables
5. **Headless development**: Use `--headless` for CI/CD or server environments
6. **Direct subsession access**: Use `session project subsession` for focused development

## Troubleshooting

### Subsessions Not Starting

Check subsession status:
```bash
session myproject status
```

Restart specific subsession:
```bash
session myproject restart backend
```

### Layout Issues

Ensure terminal size is adequate (minimum 80x24 recommended).

### Configuration Errors

Test YAML parsing:
```bash
session myproject --help  # Will show config parsing errors
```

### Clipboard Integration

The session manager automatically detects available clipboard tools:
- Linux: `xclip` or `wl-clipboard`
- macOS: `pbcopy`
- WSL: Windows clipboard

## Integration

### With IDEs

Configure your IDE to use session manager:
```bash
# VS Code integrated terminal
session myproject backend

# Attach to running subsession
session myproject api-server
```

### With Git Hooks

```bash
# In .git/hooks/post-checkout
#!/bin/bash
session myproject --headless
```

### With Docker

```yaml
subsessions:
  database:
    command: docker-compose up postgres
  
  redis:
    command: docker-compose up redis
    delay: 2
```