#!/usr/bin/env bash
# Subsession Manager - Smart tmux subsession management

# yaml-parser.sh is sourced by core.sh before this file

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
    local execute="${6:-true}"
    local history="${7:-false}"

    if subsession_exists "$name"; then
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        log "Directory does not exist for subsession '$name': $dir"
        return 1
    fi

    local tmux_conf="${TOOLS_RUNTIME_DIR}/session-tmux.conf"
    local tmux_new_flags=()
    [[ -f "$tmux_conf" ]] && tmux_new_flags+=(-f "$tmux_conf")
    if ! tmux "${tmux_new_flags[@]}" new-session -d -s "$name" -c "$dir" 2>/dev/null; then
        log "Failed to create subsession $name"
        return 1
    fi

    # Subsession baseline defaults (before color/tmux overrides)
    tmux set-option -t "$name" status-justify left 2>/dev/null || true

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

    # Send command to the subsession pane
    # If delay is set, fork a background subshell that waits then sends — the manager
    # process continues immediately and the pane shows a clean command (no sleep &&)
    _send_subsession_command() {
        if [[ -n "$command" && "$command" != "bash" ]]; then
            if [[ "$execute" == "false" ]]; then
                # Pre-fill command text without executing (env vars still exported first)
                if [[ -n "$export_prefix" ]]; then
                    tmux send-keys -t "$name" "${HIST_SKIP}${export_prefix%%; }" Enter 2>/dev/null || true
                fi
                tmux send-keys -t "$name" "$command" 2>/dev/null || true
            else
                tmux send-keys -t "$name" "${HIST_SKIP}${export_prefix}${command}" Enter 2>/dev/null || true
                if [[ "$history" == "true" ]]; then
                    echo "$command" >> ~/.bash_history
                fi
            fi
        elif [[ -n "$export_prefix" ]]; then
            tmux send-keys -t "$name" "${HIST_SKIP}${export_prefix%%; }" Enter 2>/dev/null || true
        fi
    }

    if [[ "${delay:-0}" -gt 0 ]]; then
        ( sleep "$delay"; _send_subsession_command ) &
    else
        _send_subsession_command
    fi

    exclude_from_resurrect "$name"
    return 0
}

# Attach a pane to a subsession
attach_pane_to_subsession() {
    local pane="$1"
    local subsession="$2"
    local cmd="${3:-}"

    if ! subsession_exists "$subsession"; then
        log "Subsession $subsession does not exist"
        return 1
    fi

    if [[ -n "$cmd" ]]; then
        tmux send-keys -t "$subsession" "${HIST_SKIP}$cmd" Enter 2>/dev/null || true
    fi
    tmux send-keys -t "$pane" "${HIST_SKIP}TMUX= tmux attach-session -t $subsession || exec bash" Enter 2>/dev/null || return 1
    return 0
}

# Stop a subsession
stop_subsession() {
    local name="$1"

    if ! subsession_exists "$name"; then
        log "Subsession '$name' is not running"
        return 0
    fi

    tmux kill-session -t "$name" 2>/dev/null || true
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
    local execute=$(yaml_get_subsession "$name" "execute")
    local history=$(yaml_get_subsession "$name" "history")

    [[ -z "$dir" ]] && dir="."
    dir=$(resolve_dir "$dir")

    if subsession_exists "$name"; then
        stop_subsession "$name"
        sleep 1
    fi

    start_subsession "$name" "$dir" "$command" "$delay" "$env_vars" "$execute" "$history"
    _apply_subsession_color "$name"
    apply_tmux_subsession_options "$name"
}

# Refresh a subsession's tmux settings without restarting it
refresh_subsession() {
    local name="$1"

    if ! subsession_exists "$name"; then
        die "Subsession '$name' is not running"
    fi

    if [[ -z "${TIMEZONE_SCRIPT:-}" ]]; then
        TIMEZONE_SCRIPT=$(create_timezone_script)
    fi

    _apply_subsession_color "$name"
    apply_tmux_subsession_options "$name"

    echo "Refreshed subsession '$name'"
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
    local execute=$(yaml_get_subsession "$name" "execute")
    local history=$(yaml_get_subsession "$name" "history")

    if [[ -z "$dir" ]]; then
        log "No configuration found for subsession $name"
        return 1
    fi

    dir=$(resolve_dir "$dir")
    start_subsession "$name" "$dir" "$command" "$delay" "$env_vars" "$execute" "$history"
    _apply_subsession_color "$name"
    apply_tmux_subsession_options "$name"
}

# Internal: find and apply the color for a subsession based on its parent window
_apply_subsession_color() {
    local name="$1"

    # Create timezone script if not already set
    if [[ -z "${TIMEZONE_SCRIPT:-}" ]]; then
        TIMEZONE_SCRIPT=$(create_timezone_script)
    fi

    # Subsession-level color takes priority over window color
    local sub_color=$(yaml_get_subsession "$name" "color")
    if [[ -n "$sub_color" ]]; then
        apply_subsession_colors "$name" "$sub_color" "$TIMEZONE_SCRIPT"
        return 0
    fi

    # Fall back to parent window's color
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

# Apply color scheme to subsession (uses shared _apply_color_defaults from core.sh)
apply_subsession_colors() {
    local name="$1"
    local color="$2"
    local timezone_script="$3"

    [[ -z "$color" ]] && return
    subsession_exists "$name" || return

    _apply_color_defaults "$name" "$color" "$timezone_script" \
        "$(yaml_get_tmux_subsession "$name" "status-style")" \
        "$(yaml_get_tmux_subsession "$name" "status-left")" \
        "$(yaml_get_tmux_subsession "$name" "status-right")"
}

# Apply per-subsession tmux options from YAML (uses shared _apply_tmux_opts from core.sh)
apply_tmux_subsession_options() {
    subsession_exists "$1" || return
    _apply_tmux_opts "$1" "set-option" "tmux_subsession_${1}_"
}
