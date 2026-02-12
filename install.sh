#!/usr/bin/env bash
# Tools Repository — installer / uninstaller
# Adds bin/ to PATH so `session` and `cleanup` work globally.
# Project wrappers go in ~/.local/bin via `session install`.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_BIN="$TOOLS_DIR/bin"
WRAPPER_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/tools"
CACHE_DIR="$HOME/.cache/tools"

# Marker used in shell configs so we can find and remove our lines
PATH_MARKER="# tools-repo"

info()    { echo -e "${BLUE}::${NC} $*"; }
ok()      { echo -e "${GREEN}::${NC} $*"; }
warn()    { echo -e "${YELLOW}::${NC} $*"; }
err()     { echo -e "${RED}::${NC} $*" >&2; }

# ─── Dependency check ───────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v tmux  >/dev/null 2>&1 || missing+=("tmux")
    command -v bash  >/dev/null 2>&1 || missing+=("bash")
    if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
        err "Bash 4.0+ required (found: $BASH_VERSION)"; exit 1
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing: ${missing[*]}"
        echo "  apt install ${missing[*]}"
        exit 1
    fi
    ok "Dependencies satisfied"
}

# ─── Add tools/bin to PATH in shell rc files ────────────────────────
add_to_path() {
    # Also ensure ~/.local/bin is in PATH (for project wrappers)
    local dirs_to_add=("$TOOLS_BIN" "$WRAPPER_DIR")

    for dir in "${dirs_to_add[@]}"; do
        for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [[ -f "$rc" ]] || continue
            if ! grep -qF "$dir" "$rc" 2>/dev/null; then
                echo "" >> "$rc"
                echo "export PATH=\"$dir:\$PATH\"  $PATH_MARKER" >> "$rc"
                info "Added $dir to $rc"
            fi
        done
    done

    # Update current shell
    export PATH="$TOOLS_BIN:$WRAPPER_DIR:$PATH"
    ok "PATH configured"
}

# ─── Make binaries executable ────────────────────────────────────────
set_permissions() {
    chmod +x "$TOOLS_BIN"/* 2>/dev/null || true
    ok "Permissions set"
}

# ─── Create config dirs ─────────────────────────────────────────────
create_dirs() {
    mkdir -p "$WRAPPER_DIR"
    mkdir -p "$CONFIG_DIR"
    ok "Directories ready"
}

# ─── Verify ──────────────────────────────────────────────────────────
verify() {
    local ok=true
    if command -v session >/dev/null 2>&1; then
        ok "session command available"
    else
        warn "session not in PATH yet (restart terminal or source shell rc)"
        ok=false
    fi
    if command -v cleanup >/dev/null 2>&1; then
        ok "cleanup command available"
    else
        warn "cleanup not in PATH yet (restart terminal or source shell rc)"
        ok=false
    fi
}

# ─── Install ─────────────────────────────────────────────────────────
do_install() {
    echo -e "${GREEN}Tools Installer${NC}"
    echo "==============="
    echo

    check_deps
    create_dirs
    set_permissions
    add_to_path
    verify

    cat << EOF

${GREEN}Installed.${NC}

  Commands (available after terminal restart or \`source ~/.bashrc\`):
    session          YAML-based tmux session manager
    cleanup          System cleanup utility
    self-update      Pull latest and refresh

  Register a project:
    session install /path/to/myproject.yaml
    # Creates ~/.local/bin/<name> wrapper (name read from YAML)

  Uninstall everything:
    ./install.sh uninstall

  Docs: $TOOLS_DIR/docs/
EOF
}

# ─── Uninstall ────────────────────────────────────────────────────────
do_uninstall() {
    echo -e "${RED}Uninstalling tools${NC}"
    echo

    # Remove project wrappers created by `session install`
    local removed_wrappers=0
    if [[ -d "$WRAPPER_DIR" ]]; then
        while IFS= read -r wrapper; do
            local name
            name=$(basename "$wrapper")
            info "Removing project wrapper: $name"
            rm -f "$wrapper"
            ((removed_wrappers++))
        done < <(grep -rl "tools-session-wrapper" "$WRAPPER_DIR" 2>/dev/null || true)
    fi

    # Remove old generic wrappers from previous installs
    for old_wrapper in session-manager session cleanup tools-update; do
        if [[ -f "$WRAPPER_DIR/$old_wrapper" ]]; then
            info "Removing old wrapper: $old_wrapper"
            rm -f "$WRAPPER_DIR/$old_wrapper"
        fi
    done

    # Remove PATH and env entries from shell configs
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$PATH_MARKER" "$rc" 2>/dev/null; then
            # Remove lines containing our marker
            sed -i "/$PATH_MARKER/d" "$rc"
            # Remove any old TOOLS_HOME lines
            sed -i '/^export TOOLS_HOME=/d' "$rc"
            # Clean up blank lines we left behind (collapse multiple blanks)
            sed -i '/^$/N;/^\n$/d' "$rc"
            info "Cleaned $rc"
        fi
    done

    # Remove config and cache dirs
    if [[ -d "$CONFIG_DIR" ]]; then
        info "Removing $CONFIG_DIR"
        rm -rf "$CONFIG_DIR"
    fi
    if [[ -d "$CACHE_DIR" ]]; then
        info "Removing $CACHE_DIR"
        rm -rf "$CACHE_DIR"
    fi

    # Remove old install location if it exists
    if [[ -d "$HOME/.local/share/tools" ]]; then
        info "Removing old install copy at ~/.local/share/tools"
        rm -rf "$HOME/.local/share/tools"
    fi

    echo
    ok "Uninstalled. Removed $removed_wrappers project wrapper(s)."
    ok "The repo at $TOOLS_DIR is untouched — delete it manually if desired."
}

# ─── Entry point ──────────────────────────────────────────────────────
VERBOSE=false
if [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]]; then
    VERBOSE=true
    shift
fi

case "${1:-install}" in
    install|"")   do_install ;;
    uninstall)    do_uninstall ;;
    update)       exec "$TOOLS_DIR/bin/self-update" ;;
    help|--help|-h)
        cat << 'EOF'
Tools Repository Installer

Usage:
  ./install.sh [COMMAND]

Commands:
  install      Add tools/bin to PATH (default if no command given)
  uninstall    Remove all tools traces from the system
  update       Pull latest changes and refresh (runs self-update)
  help         Show this help

Options:
  -v, --verbose    Show detailed output

Examples:
  ./install.sh               Install tools
  ./install.sh uninstall     Remove everything
  ./install.sh update        Pull latest and refresh
EOF
        ;;
    *)
        err "Unknown: $1"; echo "Run: install.sh help"; exit 1 ;;
esac
