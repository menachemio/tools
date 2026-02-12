# Cleanup Utility Documentation

The cleanup utility provides intelligent system cleaning with configurable safety checks and automation.

## Overview

The cleanup utility targets common development environment bloat:
- VS Code Server caches and old extensions
- Node.js package caches and orphaned node_modules
- System logs and temporary files  
- Docker containers and images
- Development tool caches (Playwright, code-server, etc.)
- Installer packages and archives

## Basic Usage

```bash
# Interactive cleanup with safety prompts
cleanup

# Preview what would be cleaned (dry-run mode)  
cleanup --dry-run

# Use custom configuration
cleanup --config my-cleanup.yaml

# Auto-clean safe targets without prompts
cleanup --auto
```

## Safety Features

### Protected Paths

The cleanup utility will never touch:
- `$HOME/.ssh/` - SSH keys and config
- `$HOME/.gitconfig` - Git configuration
- `$HOME/.bashrc` / `$HOME/.zshrc` - Shell configurations
- Any files with `.key` or `.pem` extensions
- Active project directories with recent activity

### Confirmation Prompts

By default, the utility asks before:
- Removing large caches (>100MB)
- Deleting development files
- Cleaning Docker resources
- Truncating log files

### Backup Retention

Automatically preserves:
- Recent files (last 7 days)
- Current development sessions
- Important configuration backups

## Cleanup Targets

### VS Code Server

**What gets cleaned:**
- Old extension versions (keeps latest)
- CLI and bin folders
- Cached data and installations
- Log files older than 7 days
- Workspace storage older than 30 days

**Auto-cleaned (no prompts):**
- Extension duplicates
- CLI downloads
- Old server installations

**With confirmation:**
- History folders (30+ days old)
- Backup folders (30+ days old)

### Node.js and NPM

**Auto-cleaned:**
- NPM cache (`~/.npm`)
- Yarn cache (`~/.cache/yarn`)
- Node-gyp cache

**With detection:**
- Orphaned `node_modules` without `package.json`
- `node_modules` in home directory root
- Old package-lock.json files

### System Resources

**Automatic:**
- Systemd journal cleanup (keeps 100MB)
- APT cache clearing
- Old log rotations

**With confirmation:**
- Large log files (>500MB) - truncated to 50MB
- Compressed log archives

### Development Tools

**Auto-cleaned:**
- Playwright browser cache
- Claude CLI cache  
- Code-server cache
- Wrangler temporary files

**With confirmation:**
- Docker unused containers
- Docker unused images
- Development database dumps

### Cache Directories

**Scanned locations:**
- `~/.cache/` - User cache directory
- `/tmp/` - Temporary files (noted but skipped - clears on reboot)
- Project-specific caches

**Safe auto-removal:**
- Installer packages (`.deb`, `.rpm`, `.AppImage`)
- Large archive files (`.tar.gz`, `.zip` >50MB)
- Old cached downloads

## Configuration

### Default Configuration

The cleanup utility works well out-of-the-box with sensible defaults. For customization, create a configuration file:

```yaml
# ~/.config/tools/cleanup.yaml
general:
  auto_clean_threshold_gb: 1      # Auto-clean items under 1GB
  confirm_threshold_gb: 5         # Always confirm items over 5GB
  backup_retention_days: 30       # Keep backups for 30 days
  log_retention_days: 7           # Keep logs for 7 days

protected:
  directories:
    - $HOME/.ssh
    - $HOME/.gitconfig
    - $HOME/important-project
  patterns:
    - "*.key"
    - "*.pem" 
    - "*.p12"
    - "backup-*"

targets:
  vscode:
    enabled: true
    auto_clean_old_extensions: true
    keep_recent_workspaces: true
    
  nodejs:
    enabled: true
    clean_npm_cache: true
    detect_orphaned_modules: true
    
  docker:
    enabled: true
    remove_unused_containers: false  # Requires confirmation
    remove_unused_images: false     # Requires confirmation
    
  system:
    enabled: true
    clean_journals: true
    max_journal_size: "100M"
    clean_apt_cache: true

# Custom cleanup commands
custom:
  - name: "Clean old downloads"
    command: "find ~/Downloads -mtime +30 -delete"
    confirm: true
    
  - name: "Clear browser cache"
    command: "rm -rf ~/.cache/mozilla ~/.cache/google-chrome"
    confirm: true
```

### Environment Variables

```bash
# Override default config location
export CLEANUP_CONFIG="$HOME/my-cleanup.yaml"

# Set cleanup mode
export CLEANUP_MODE="auto"        # auto, interactive, dry-run

# Override safety limits
export CLEANUP_SIZE_LIMIT="10G"   # Don't auto-clean items over 10GB
```

## Advanced Usage

### Dry-Run Mode

Preview all actions without making changes:

```bash
cleanup --dry-run
```

Output shows:
- What would be cleaned
- Estimated space to be freed
- Safety checks that would be performed

### Custom Configurations

```bash
# Use project-specific cleanup
cleanup --config ./project-cleanup.yaml

# Combine multiple configs
cleanup --config base.yaml --config project.yaml
```

### Automation and Scheduling

#### Cron Integration

```bash
# Add to crontab for weekly cleanup
0 2 * * 0 /usr/local/bin/cleanup --auto --config ~/.config/tools/cleanup-auto.yaml
```

#### CI/CD Integration

```bash
# In CI pipeline
cleanup --auto --config ci-cleanup.yaml
```

#### Session Manager Integration

```bash
# In session config
subsessions:
  maintenance:
    command: cleanup --auto
    schedule: weekly
```

## Reporting and Monitoring

### Cleanup Reports

```bash
# Generate detailed report
cleanup --report

# Save report to file  
cleanup --report > cleanup-$(date +%Y%m%d).log
```

### Before/After Analysis

The cleanup utility automatically:
- Shows disk usage before cleanup
- Tracks space freed during operation
- Reports final disk usage and savings

### Integration with Monitoring

```bash
# JSON output for monitoring systems
cleanup --json | jq '.space_freed'

# Exit codes for automation
# 0: Success, space freed
# 1: Error occurred  
# 2: No cleanup needed
```

## Safety and Recovery

### Backup Before Cleanup

For extra safety, backup important directories:

```bash
# Manual backup before cleanup
tar -czf cleanup-backup-$(date +%Y%m%d).tar.gz ~/.config ~/.local/share/important
cleanup
```

### Recovery

If cleanup removes something important:

1. **Check recent backups**: Look in `/tmp/cleanup-backup-*`
2. **Restore from package manager**: `apt install --reinstall package`
3. **Regenerate caches**: Most caches rebuild automatically
4. **Session recovery**: Use session manager to restart development environment

### Undo Tracking

Enable undo tracking in config:

```yaml
general:
  track_deletions: true
  undo_retention_days: 7
```

Creates undo scripts in `~/.cache/cleanup-undo/`

## Best Practices

### Regular Maintenance

1. **Weekly automated cleanup**: Use cron with auto mode
2. **Monthly manual review**: Run interactive mode monthly  
3. **Project cleanup**: Run before major deployments
4. **Disk monitoring**: Check disk usage trends

### Development Workflow

1. **Pre-deployment**: Clean before shipping
2. **Environment refresh**: Clean between major features
3. **Dependency updates**: Clean after package updates
4. **Session restart**: Clean before starting new sessions

### Team Usage

1. **Shared configs**: Keep cleanup configs in project repos
2. **Documentation**: Document project-specific cleanup needs  
3. **CI integration**: Include cleanup in build pipelines
4. **Onboarding**: Include cleanup setup in developer setup

## Common Scenarios

### Low Disk Space Emergency

```bash
# Emergency cleanup - be more aggressive
cleanup --auto --aggressive

# Target specific large items
cleanup --target vscode,nodejs,docker --auto
```

### Development Environment Reset

```bash
# Full environment cleanup
cleanup --reset-dev-env

# Equivalent to:
# - Clean all caches
# - Remove orphaned files  
# - Reset development tools
# - Preserve configurations
```

### CI/CD Environment

```yaml
# ci-cleanup.yaml
general:
  auto_clean_threshold_gb: 0  # Clean everything automatically
  
targets:
  docker:
    enabled: true
    remove_unused_containers: true
    remove_unused_images: true
  
  system:
    clean_journals: true
    max_journal_size: "50M"
```

## Troubleshooting

### Permission Errors

```bash
# Run with proper permissions
sudo cleanup --system  # For system-level cleanup
cleanup --user         # For user-level only (default)
```

### Configuration Issues

```bash
# Validate configuration
cleanup --validate-config

# Use default config if custom fails  
cleanup --ignore-config
```

### Performance Issues

```bash
# Limit concurrent operations
cleanup --max-parallel 2

# Skip slow operations
cleanup --skip docker,large-files
```

## Integration Examples

### With Session Manager

```yaml
# In session config
windows:
  - name: maintenance
    panes:
      - type: command
        cmd: cleanup --dry-run
        execute: false
```

### With Docker Development

```yaml
# cleanup-docker.yaml
targets:
  docker:
    enabled: true
    remove_unused_containers: true
    remove_unused_images: true
    cleanup_volumes: true
    
custom:
  - name: "Clean Docker build cache"
    command: "docker builder prune -f"
    confirm: false
```

### With Node.js Projects

```yaml
# cleanup-node.yaml  
targets:
  nodejs:
    enabled: true
    clean_npm_cache: true
    clean_yarn_cache: true
    detect_orphaned_modules: true
    
custom:
  - name: "Clean package-lock files"
    command: "find . -name package-lock.json -mtime +7 -delete"
    confirm: true
```