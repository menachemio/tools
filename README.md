# Linux Development Tools

A unified toolkit for session management and system cleanup, designed for Linux development environments.

## Features

### Session Manager
- **Smart subsession management** - Independent tmux sessions that persist across window operations
- **YAML configuration** - Simple, readable configuration files
- **Flexible command syntax** - `myproject` or `myproject subsession --headless`
- **Project-local configs** - Configurations live with your projects
- **Mixed pane types** - Commands, pre-filled commands, or subsessions

### Cleanup Utility
- **Configurable cleaning** - YAML-based configuration for safe automation
- **Dry-run mode** - Preview changes before execution
- **Smart detection** - Find orphaned files, old caches, and unused dependencies
- **Progress tracking** - Visual feedback for long operations

## Quick Start

```bash
# Install globally
./install.sh

# Create a session config in your project
# myproject.session.yaml
name: myproject
subsessions:
  backend:
    dir: ./api
    command: npm run dev
  frontend:
    dir: ./web
    command: npm start

windows:
  - name: dev
    panes:
      - type: command
        cmd: nvim
        execute: true
      - type: subsession
        subsession: backend
      - type: subsession
        subsession: frontend

# Use your session
myproject                    # Start full session
myproject backend            # Just start backend subsession
myproject --headless         # Start in background
myproject backend --headless # Start backend in background

# Cleanup your system
cleanup                      # Interactive cleanup
cleanup --dry-run           # See what would be cleaned
cleanup --config my.yaml    # Use custom config
```

## Installation

```bash
git clone <repository-url>
cd tools
./install.sh
```

This will:
- Install tools to `~/.local/bin`
- Set up configuration directories
- Update your shell PATH
- Verify dependencies

## Documentation

- [Session Manager Guide](docs/SESSION.md)
- [Cleanup Tool Guide](docs/CLEANUP.md)
- [Configuration Examples](config/examples/)

## Requirements

- Linux or macOS
- tmux (for session management)
- bash 4.0+
- Basic UNIX utilities (grep, awk, sed)

