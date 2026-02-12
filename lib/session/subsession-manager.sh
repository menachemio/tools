#!/usr/bin/env bash
# Subsession Manager - Smart tmux subsession management

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/../common/yaml-parser.sh"

# Global subsession tracking
declare -A ACTIVE_SUBSESSIONS

# Check if a subsession exists and is running
subsession_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

# Start a new subsession
start_subsession() {
    local name="$1"
    local dir="$2"
    local command="$3"
    local delay="${4:-0}"
    local env_vars="$5"

    if subsession_exists "$name"; then
        return 0
    fi

    if ! tmux new-session -d -s "$name" -c "$dir" 2>/dev/null; then
        log "Failed to create subsession $name"
        return 1
    fi

    # Build export prefix from environment variables if provided
    local export_prefix=""
    if [[ -n "$env_vars" ]]; then
        local env_pairs=""
        while IFS='=' read -r key value; do
            # Skip empty lines
            [[ -z "$key" ]] && continue
            # Trim whitespace
            key="${key## }"; key="${key%% }"
            value="${value## }"; value="${value%% }"
            [[ -z "$key" ]] && continue
            if [[ -n "$env_pairs" ]]; then
                env_pairs="$env_pairs $key=$value"
            else
                env_pairs="$key=$value"
            fi
        done <<< "$env_vars"
        if [[ -n "$env_pairs" ]]; then
            export_prefix="export $env_pairs; "
        fi
    fi

    # Apply delay if specified
    if [[ "${delay:-0}" -gt 0 ]]; then
        sleep "$delay"
    fi

    # Send command if provided, with env exports prepended
    if [[ -n "$command" && "$command" != "bash" ]]; then
        tmux send-keys -t "$name" "${export_prefix}${command}" Enter 2>/dev/null || true
    elif [[ -n "$export_prefix" ]]; then
        # Even if no command (or command is bash), still export the env vars
        tmux send-keys -t "$name" "${export_prefix%%; }" Enter 2>/dev/null || true
    fi

    ACTIVE_SUBSESSIONS["$name"]="$dir"
    exclude_from_resurrect "$name"
    return 0
}

# Attach a pane to a subsession
attach_pane_to_subsession() {
    local pane="$1"
    local subsession="$2"

    if ! subsession_exists "$subsession"; then
        log "Subsession $subsession does not exist"
        return 1
    fi

    tmux send-keys -t "$pane" "TMUX= tmux attach-session -t $subsession || exec bash" Enter 2>/dev/null || return 1
    return 0
}

# Stop a subsession
stop_subsession() {
    local name="$1"

    if ! subsession_exists "$name"; then
        log "Subsession '$name' is not running"
        return 0
    fi

    tmux kill-session -t "$name"
    unset ACTIVE_SUBSESSIONS["$name"]
    log "Stopped subsession: $name"
    return 0
}

# Restart a subsession (uses resolve_dir from core.sh)
restart_subsession() {
    local name="$1"

    local dir=$(yaml_get_subsession "$name" "dir")
    local command=$(yaml_get_subsession "$name" "command")
    local delay=$(yaml_get_subsession "$name" "delay")
    local env_vars=$(yaml_get_subsession "$name" "env")

    [[ -z "$dir" ]] && dir="."
    dir=$(resolve_dir "$dir")

    if subsession_exists "$name"; then
        stop_subsession "$name"
        sleep 1
    fi

    start_subsession "$name" "$dir" "$command" "$delay" "$env_vars"
    _apply_subsession_color "$name"
}

# Get subsession status
subsession_status() {
    if subsession_exists "$1"; then echo "running"; else echo "stopped"; fi
}

# Auto-start subsession if needed (uses resolve_dir from core.sh)
ensure_subsession() {
    local name="$1"

    if subsession_exists "$name"; then
        return 0
    fi

    local dir=$(yaml_get_subsession "$name" "dir")
    local command=$(yaml_get_subsession "$name" "command")
    local delay=$(yaml_get_subsession "$name" "delay")
    local env_vars=$(yaml_get_subsession "$name" "env")

    if [[ -z "$dir" ]]; then
        log "No configuration found for subsession $name"
        return 1
    fi

    dir=$(resolve_dir "$dir")
    start_subsession "$name" "$dir" "$command" "$delay" "$env_vars"
    _apply_subsession_color "$name"
}

# Internal: find and apply the color for a subsession based on its parent window
_apply_subsession_color() {
    local name="$1"

    # Create timezone script if not already set
    if [[ -z "${TIMEZONE_SCRIPT:-}" ]]; then
        TIMEZONE_SCRIPT=$(create_timezone_script)
    fi

    # Find which window references this subsession and use that window's color
    while IFS= read -r win_name; do
        [[ -z "$win_name" ]] && continue
        local pcount=$(yaml_get_pane_count "$win_name")
        for ((pi=0; pi<pcount; pi++)); do
            if [[ "$(yaml_get_pane "$win_name" "$pi" "type")" == "subsession" && \
                  "$(yaml_get_pane "$win_name" "$pi" "subsession")" == "$name" ]]; then
                local wcolor=$(yaml_get_window "$win_name" "color")
                if [[ -n "$wcolor" ]]; then
                    apply_subsession_colors "$name" "$wcolor" "$TIMEZONE_SCRIPT"
                fi
                return 0
            fi
        done
    done < <(yaml_get_windows)
}

# Apply color scheme to subsession
apply_subsession_colors() {
    local name="$1"
    local color="$2"
    local timezone_script="$3"

    [[ -z "$color" ]] && return
    subsession_exists "$name" || return

    # Convert simple names
    case "$color" in
        red) color="colour196" ;; green) color="colour46" ;; blue) color="colour33" ;;
        yellow) color="colour226" ;; orange) color="colour202" ;;
        purple|magenta) color="colour201" ;; cyan) color="colour51" ;;
    esac

    tmux set-option -t "$name" status-style "fg=${color},bg=default"
    tmux set-option -t "$name" status-left "#[fg=${color},bold] #S #[default]"
    if [[ -n "$timezone_script" ]]; then
        tmux set-option -t "$name" status-right "#[fg=${color}] #($timezone_script) #[default]"
    fi
}

# Exclude session from tmux-resurrect if available
exclude_from_resurrect() {
    local session_name="$1"

    if ! tmux show-option -gv @resurrect-save-session-ignore &>/dev/null; then
        return 0
    fi

    local current_ignore
    current_ignore=$(tmux show-option -gv @resurrect-save-session-ignore 2>/dev/null || echo "")

    if [[ ",$current_ignore," == *",$session_name,"* ]]; then
        return 0
    fi

    if [[ -z "$current_ignore" ]]; then
        tmux set-option -g @resurrect-save-session-ignore "$session_name"
    else
        tmux set-option -g @resurrect-save-session-ignore "${current_ignore},${session_name}"
    fi
}