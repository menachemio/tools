#!/usr/bin/env bash
# Cleanup utility — shared helpers

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Mode flags (set by bin/cleanup)
DRY_RUN="${DRY_RUN:-false}"
AUTO_MODE="${AUTO_MODE:-false}"
VERBOSE="${VERBOSE:-false}"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_dry()     { echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1"; }

get_size() {
    if [[ -d "$1" ]] || [[ -f "$1" ]]; then
        du -sh "$1" 2>/dev/null | cut -f1 || echo "0"
    else
        echo "0"
    fi
}

# Prompt user unless in auto or dry-run mode.
# Returns 0 (yes) or 1 (no).
confirm_action() {
    [[ "$AUTO_MODE" == "true" ]] && return 0
    [[ "$DRY_RUN" == "true" ]] && return 1
    if [[ ! -t 0 ]]; then
        # No tty — can't prompt, skip the action
        [[ "${_WARNED_NO_TTY:-}" != "true" ]] && {
            log_warning "No interactive terminal detected — skipping prompts (use --auto for non-interactive cleanup)"
            _WARNED_NO_TTY=true
        }
        return 1
    fi
    read -p "$1 (y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Execute or log a removal depending on dry-run mode.
# Usage: safe_rm <path> [description]
safe_rm() {
    local target="$1"
    local desc="${2:-$target}"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "remove $desc ($(get_size "$target"))"
    else
        rm -rf "$target"
    fi
}
