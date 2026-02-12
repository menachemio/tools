#!/usr/bin/env bash
# Installation script for Tools Repository

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/tools"

# Logging functions
log_info() { echo -e "${BLUE}INFO:${NC} $*"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $*"; }
log_error() { echo -e "${RED}ERROR:${NC} $*"; }

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=()
    
    # Required dependencies
    if ! command -v tmux >/dev/null 2>&1; then
        missing+=("tmux")
    fi
    
    if ! command -v bash >/dev/null 2>&1; then
        missing+=("bash")
    fi
    
    # Check bash version (need 4.0+)
    if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
        log_error "Bash 4.0+ required (found: $BASH_VERSION)"
        exit 1
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Please install them and try again:"
        echo "  Ubuntu/Debian: sudo apt install ${missing[*]}"
        echo "  RHEL/CentOS:   sudo yum install ${missing[*]}"
        echo "  macOS:         brew install ${missing[*]}"
        exit 1
    fi
    
    log_success "All dependencies satisfied"
}

# Create directories
create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"/{sessions,cleanup}
    mkdir -p "$CONFIG_DIR/examples"
    
    log_success "Created directories"
}

# Install binaries
install_binaries() {
    log_info "Installing binaries..."
    
    # Install session manager
    cat > "$INSTALL_DIR/session" << 'EOF'
#!/usr/bin/env bash
# Session Manager wrapper - automatically finds tools directory
set -euo pipefail

# Find tools directory
TOOLS_DIR=""
if [[ -n "${TOOLS_HOME:-}" && -f "$TOOLS_HOME/bin/session-new" ]]; then
    TOOLS_DIR="$TOOLS_HOME"
elif [[ -f "$HOME/.local/share/tools/bin/session-new" ]]; then
    TOOLS_DIR="$HOME/.local/share/tools"
elif [[ -f "/usr/local/share/tools/bin/session-new" ]]; then
    TOOLS_DIR="/usr/local/share/tools"
else
    echo "Error: Tools installation not found" >&2
    echo "Set TOOLS_HOME environment variable or reinstall tools" >&2
    exit 1
fi

exec "$TOOLS_DIR/bin/session-new" "$@"
EOF
    
    chmod +x "$INSTALL_DIR/session"
    
    # Install cleanup utility
    cat > "$INSTALL_DIR/cleanup" << EOF
#!/usr/bin/env bash
# Cleanup utility wrapper
set -euo pipefail

# Find tools directory
TOOLS_DIR=""
if [[ -n "\${TOOLS_HOME:-}" && -f "\$TOOLS_HOME/bin/cleanup" ]]; then
    TOOLS_DIR="\$TOOLS_HOME"
elif [[ -f "\$HOME/.local/share/tools/bin/cleanup" ]]; then
    TOOLS_DIR="\$HOME/.local/share/tools"
elif [[ -f "/usr/local/share/tools/bin/cleanup" ]]; then
    TOOLS_DIR="/usr/local/share/tools"
else
    echo "Error: Tools installation not found" >&2
    exit 1
fi

exec "\$TOOLS_DIR/bin/cleanup" "\$@"
EOF
    
    chmod +x "$INSTALL_DIR/cleanup"
    
    log_success "Installed binaries to $INSTALL_DIR"
}

# Install tools directory
install_tools() {
    log_info "Installing tools to ~/.local/share/tools..."
    
    local target_dir="$HOME/.local/share/tools"
    
    # Remove existing installation
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
    fi
    
    # Copy tools directory
    cp -r "$TOOLS_DIR" "$target_dir"
    
    # Make sure binaries are executable
    chmod +x "$target_dir/bin"/*
    chmod +x "$target_dir/scripts"/*
    
    log_success "Installed tools to $target_dir"
}

# Copy example configurations
install_examples() {
    log_info "Installing example configurations..."
    
    cp -r "$TOOLS_DIR/config/examples"/* "$CONFIG_DIR/examples/"
    
    log_success "Installed examples to $CONFIG_DIR/examples"
}

# Update PATH
update_path() {
    log_info "Updating PATH..."
    
    local updated=false
    
    # Check if already in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        # Update .bashrc
        if [[ -f "$HOME/.bashrc" ]]; then
            if ! grep -q "export PATH.*$INSTALL_DIR" "$HOME/.bashrc"; then
                echo "" >> "$HOME/.bashrc"
                echo "# Added by tools installer" >> "$HOME/.bashrc"
                echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.bashrc"
                updated=true
                log_info "Updated ~/.bashrc"
            fi
        fi
        
        # Update .zshrc if it exists
        if [[ -f "$HOME/.zshrc" ]]; then
            if ! grep -q "export PATH.*$INSTALL_DIR" "$HOME/.zshrc"; then
                echo "" >> "$HOME/.zshrc"
                echo "# Added by tools installer" >> "$HOME/.zshrc"
                echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.zshrc"
                updated=true
                log_info "Updated ~/.zshrc"
            fi
        fi
        
        # Update current session
        export PATH="$PATH:$INSTALL_DIR"
        
        if [[ "$updated" == true ]]; then
            log_success "Updated shell configuration files"
        else
            log_info "PATH already configured"
        fi
    else
        log_info "PATH already includes $INSTALL_DIR"
    fi
}

# Set TOOLS_HOME environment variable
set_tools_home() {
    log_info "Setting TOOLS_HOME environment variable..."
    
    local tools_home="$HOME/.local/share/tools"
    local updated=false
    
    # Update .bashrc
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "TOOLS_HOME" "$HOME/.bashrc"; then
            echo "export TOOLS_HOME=\"$tools_home\"" >> "$HOME/.bashrc"
            updated=true
        fi
    fi
    
    # Update .zshrc if it exists
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -q "TOOLS_HOME" "$HOME/.zshrc"; then
            echo "export TOOLS_HOME=\"$tools_home\"" >> "$HOME/.zshrc"
            updated=true
        fi
    fi
    
    # Set for current session
    export TOOLS_HOME="$tools_home"
    
    if [[ "$updated" == true ]]; then
        log_success "Set TOOLS_HOME=$tools_home"
    else
        log_info "TOOLS_HOME already configured"
    fi
}

# Migrate existing configurations
migrate_existing() {
    log_info "Checking for existing configurations to migrate..."
    
    local migrated=0
    
    # Look for existing bash configs
    local search_dirs=("$HOME" "$HOME/workers" "$HOME/projects")
    
    for search_dir in "${search_dirs[@]}"; do
        if [[ ! -d "$search_dir" ]]; then
            continue
        fi
        
        # Find bash session configs
        while IFS= read -r -d '' config_file; do
            local basename=$(basename "$config_file" .sh)
            basename=${basename%-config}
            local yaml_file="$CONFIG_DIR/sessions/${basename}.session.yaml"
            
            if [[ ! -f "$yaml_file" ]]; then
                log_info "Found config to migrate: $config_file"
                if "$HOME/.local/share/tools/scripts/migrate-to-yaml.sh" "$config_file" "$yaml_file" 2>/dev/null; then
                    log_success "Migrated: $yaml_file"
                    ((migrated++))
                else
                    log_warning "Failed to migrate: $config_file (will need manual conversion)"
                fi
            fi
        done < <(find "$search_dir" -maxdepth 2 -name "*session*config*.sh" -print0 2>/dev/null)
    done
    
    if [[ $migrated -gt 0 ]]; then
        log_success "Migrated $migrated configuration(s)"
    else
        log_info "No existing configurations found to migrate"
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Test session command
    if command -v session >/dev/null 2>&1; then
        log_success "Session command available"
    else
        log_error "Session command not found in PATH"
        return 1
    fi
    
    # Test cleanup command
    if command -v cleanup >/dev/null 2>&1; then
        log_success "Cleanup command available"
    else
        log_error "Cleanup command not found in PATH"
        return 1
    fi
    
    # Test tools directory
    if [[ -n "${TOOLS_HOME:-}" && -d "$TOOLS_HOME" ]]; then
        log_success "TOOLS_HOME configured: $TOOLS_HOME"
    else
        log_error "TOOLS_HOME not configured"
        return 1
    fi
    
    return 0
}

# Show completion message
show_completion() {
    cat << EOF

${GREEN}🚀 Installation Complete!${NC}
=====================================

${BLUE}Installed commands:${NC}
  • session    - YAML-based tmux session manager
  • cleanup    - System cleanup utility

${BLUE}Configuration:${NC}
  • TOOLS_HOME: $HOME/.local/share/tools
  • Config dir: $CONFIG_DIR
  • Examples:   $CONFIG_DIR/examples/

${BLUE}Quick Start:${NC}
  1. Copy an example config:
     cp $CONFIG_DIR/examples/simple-project.session.yaml myproject.session.yaml

  2. Edit the config for your project

  3. Start your session:
     session myproject

${BLUE}Commands:${NC}
  session myproject                 # Start session
  session myproject --headless      # Start in background
  session myproject backend         # Start subsession
  session myproject status          # Show status
  session myproject kill            # Kill all sessions
  cleanup                          # Run system cleanup
  cleanup --dry-run                # Preview cleanup

${YELLOW}Note: Restart your terminal or run 'source ~/.bashrc' to use the new commands.${NC}

${BLUE}Documentation:${NC}
  • Session docs: $TOOLS_HOME/docs/SESSION.md
  • Cleanup docs: $TOOLS_HOME/docs/CLEANUP.md
  • Examples:     $TOOLS_HOME/config/examples/

EOF
}

# Main installation
main() {
    echo -e "${GREEN}Tools Repository Installer${NC}"
    echo "=========================="
    echo
    
    # Run installation steps
    check_dependencies
    create_directories
    install_tools
    install_binaries
    install_examples
    update_path
    set_tools_home
    migrate_existing
    
    # Verify installation
    if verify_installation; then
        show_completion
    else
        log_error "Installation verification failed"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-install}" in
    "install"|"")
        main
        ;;
    "uninstall")
        echo "Uninstalling tools..."
        rm -f "$INSTALL_DIR/session" "$INSTALL_DIR/cleanup"
        rm -rf "$HOME/.local/share/tools"
        echo "Uninstalled. You may need to manually remove PATH entries from shell configs."
        ;;
    "help"|"--help"|"-h")
        echo "Usage: install.sh [install|uninstall|help]"
        echo ""
        echo "Commands:"
        echo "  install      Install tools (default)"
        echo "  uninstall    Remove installation"
        echo "  help         Show this help"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use 'install.sh help' for usage information"
        exit 1
        ;;
esac