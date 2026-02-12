#!/usr/bin/env bash
# Session Manager Core - YAML-based session management with subsessions

# Source dependencies
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CORE_DIR/../common/yaml-parser.sh"
source "$CORE_DIR/subsession-manager.sh"

# Global configuration
CONFIG_FILE=""
CONFIG_DIR=""
SESSION_NAME=""
TIMEZONE_SCRIPT=""
VERBOSE="${VERBOSE:-false}"

# Logging functions
log() { [[ "$VERBOSE" == "true" ]] && echo ":: $*" >&2 || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Find session configuration file
find_session_config() {
    local search_dir="$1"
    local config_name="$2"

    local search_paths=(
        "$search_dir/${config_name}.session.yaml"
        "$search_dir/.session.yaml"
        "$search_dir/.session/config.yaml"
        "$HOME/.config/tools/sessions/${config_name}.yaml"
    )

    for config_path in "${search_paths[@]}"; do
        if [[ -f "$config_path" ]]; then
            echo "$(cd "$(dirname "$config_path")" && pwd)/$(basename "$config_path")"
            return 0
        fi
    done

    return 1
}

# Resolve a path relative to the config file's directory
resolve_dir() {
    local dir="$1"
    if [[ "$dir" == /* ]]; then
        echo "$dir"
    else
        echo "$CONFIG_DIR/$dir"
    fi
}

# Load configuration from YAML
load_session_config() {
    local config_file="$1"

    CONFIG_FILE="$(cd "$(dirname "$config_file")" && pwd)/$(basename "$config_file")"
    CONFIG_DIR="$(dirname "$CONFIG_FILE")"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Configuration file not found: $config_file"
    fi

    log "Loading configuration from: $CONFIG_FILE"

    if ! parse_yaml "$CONFIG_FILE"; then
        die "Failed to parse YAML configuration"
    fi

    SESSION_NAME=$(yaml_get "name")
    if [[ -z "$SESSION_NAME" ]]; then
        die "Session name not defined in configuration"
    fi

    log "Loaded session: $SESSION_NAME"
}

# Create timezone script for status bar
create_timezone_script() {
    local script="/tmp/${SESSION_NAME}-time.sh"
    local primary_tz=$(yaml_get "timezone")
    local show_utc=$(yaml_get "show_utc")

    [[ -z "$primary_tz" ]] && primary_tz="America/New_York"
    [[ -z "$show_utc" ]] && show_utc="true"

    cat > "$script" << EOF
#!/bin/bash
primary_time=\$(TZ="$primary_tz" date "+%H:%M %Z")
EOF

    if [[ "$show_utc" == "true" ]]; then
        cat >> "$script" << 'EOF'
utc_time=$(TZ=UTC date "+[%H:%M UTC]")
echo "$primary_time $utc_time"
EOF
    else
        cat >> "$script" << 'EOF'
echo "$primary_time"
EOF
    fi

    chmod +x "$script"
    echo "$script"
}

# Create tmux configuration
create_tmux_config() {
    local timezone_script="$1"

    cat > /tmp/session-tmux.conf << EOF
# Session Manager tmux configuration
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -g mouse on

# Clipboard support
set -g set-clipboard on
set -s copy-command 'xclip -selection clipboard 2>/dev/null || wl-copy 2>/dev/null || pbcopy 2>/dev/null'

# Start windows at 1
set -g base-index 1

# Status bar
set -g status on
set -g status-interval 1
set -g status-left-length 50
set -g status-right-length 100
set -g status-right '#($timezone_script)'
set -g status-bg black
set -g status-fg white

# Pane navigation - Arrow keys
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# Pane navigation - Vim style
bind -n M-h select-pane -L
bind -n M-j select-pane -D
bind -n M-k select-pane -U
bind -n M-l select-pane -R
EOF

    # Dynamic window bindings
    local window_count
    window_count=$(yaml_get_windows | wc -l)
    local max=$((window_count > 20 ? 20 : window_count))
    for ((i=1; i<=max; i++)); do
        echo "bind -n M-$i select-window -t $i" >> /tmp/session-tmux.conf
    done

    cat >> /tmp/session-tmux.conf << 'EOF'

# Quick window switching
bind -n M-n next-window
bind -n M-p previous-window

# Vi mode with clipboard
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "xclip -selection clipboard 2>/dev/null || wl-copy 2>/dev/null || pbcopy 2>/dev/null"

# Pane borders
set -g pane-border-style fg=brightblack
set -g pane-active-border-style fg=white
EOF
}

# Apply session color scheme
apply_session_colors() {
    local session_name="$1"
    local timezone_script="$2"

    local session_color=$(yaml_get "color")
    [[ -z "$session_color" ]] && return

    # Convert simple color names to tmux colors
    case "$session_color" in
        red) session_color="colour196" ;;
        green) session_color="colour46" ;;
        blue) session_color="colour33" ;;
        yellow) session_color="colour226" ;;
        orange) session_color="colour202" ;;
        purple|magenta) session_color="colour201" ;;
        cyan) session_color="colour51" ;;
    esac

    sleep 0.1
    tmux set-option -g status-style "default"
    tmux set-option -t "$session_name" status-style "fg=white,bg=${session_color}"
    tmux set-option -t "$session_name" status-left "#[fg=white,bg=${session_color},bold]  #S  #[default]   "
    tmux set-option -t "$session_name" status-right "#[fg=white,bg=${session_color}] #($timezone_script) #[default]"
    tmux set-option -t "$session_name" status-justify centre
    log "Applied session color: $session_color"
}

# Create pane layout
create_pane_layout() {
    local target="$1"
    local pane_count="$2"
    local working_dir="$3"

    log "Creating $pane_count panes for $target"

    # Check window dimensions
    local width=$(tmux display-message -t "$target" -p "#{window_width}")
    local height=$(tmux display-message -t "$target" -p "#{window_height}")
    if [[ $width -lt 20 || $height -lt 10 ]]; then
        tmux resize-window -t "$target" -x 80 -y 24 2>/dev/null || true
        sleep 0.1
    fi

    case $pane_count in
        1) return 0 ;;
        2)
            tmux split-window -h -t "$target" -c "$working_dir"
            ;;
        3)
            tmux split-window -h -t "$target" -c "$working_dir"
            tmux split-window -v -t "${target}.1" -c "$working_dir"
            ;;
        4)
            tmux split-window -v -t "$target" -c "$working_dir"
            tmux split-window -h -t "${target}.0" -c "$working_dir"
            tmux split-window -h -t "${target}.2" -c "$working_dir"
            tmux select-layout -t "$target" tiled
            ;;
        *)
            for ((i=1; i<pane_count; i++)); do
                tmux split-window -v -t "$target" -c "$working_dir" 2>/dev/null || break
                sleep 0.1
            done
            tmux select-layout -t "$target" tiled 2>/dev/null || true
            ;;
    esac

    sleep 0.1
    local actual=$(tmux list-panes -t "$target" | wc -l)
    log "Window $target: requested $pane_count, created $actual panes"
}

# Setup individual pane
setup_pane() {
    local window_target="$1"
    local pane_index="$2"
    local window_name="$3"
    local pane_target="${window_target}.${pane_index}"

    local pane_type=$(yaml_get_pane "$window_name" "$pane_index" "type")

    case "$pane_type" in
        "subsession")
            local subsession_name=$(yaml_get_pane "$window_name" "$pane_index" "subsession")
            if [[ -n "$subsession_name" ]]; then
                ensure_subsession "$subsession_name"
                sleep 0.1
                attach_pane_to_subsession "$pane_target" "$subsession_name"
            fi
            ;;
        "command")
            local cmd=$(yaml_get_pane "$window_name" "$pane_index" "cmd")
            local execute=$(yaml_get_pane "$window_name" "$pane_index" "execute")
            local history=$(yaml_get_pane "$window_name" "$pane_index" "history")

            if [[ -n "$cmd" ]]; then
                if [[ "$execute" == "true" ]]; then
                    # Execute command immediately
                    tmux send-keys -t "$pane_target" "$cmd" Enter

                    # Optionally add to history
                    if [[ "$history" == "true" ]]; then
                        echo "$cmd" >> ~/.bash_history
                    fi
                else
                    # Pre-fill command text, don't execute (wait for Enter)
                    tmux send-keys -t "$pane_target" "$cmd"
                fi
            fi
            ;;
    esac
}

# Create a window with panes
create_window() {
    local session_name="$1"
    local window_name="$2"
    local is_first_window="$3"

    log "Creating window: $window_name"

    local window_dir=$(yaml_get_window "$window_name" "dir")
    local window_color=$(yaml_get_window "$window_name" "color")

    # Resolve relative dir against config file location
    [[ -z "$window_dir" ]] && window_dir="."
    window_dir=$(resolve_dir "$window_dir")

    # Create or rename window
    if [[ "$is_first_window" == "true" ]]; then
        tmux rename-window -t "$session_name" "$window_name"
    else
        tmux new-window -t "$session_name" -n "$window_name"
    fi

    # Set working directory
    tmux send-keys -t "$session_name:$window_name" "cd '$window_dir'" Enter

    # Apply window colors
    if [[ -n "$window_color" ]]; then
        case "$window_color" in
            red) window_color="colour196" ;;
            green) window_color="colour46" ;;
            blue) window_color="colour33" ;;
            yellow) window_color="colour226" ;;
            orange) window_color="colour202" ;;
            purple|magenta) window_color="colour201" ;;
            cyan) window_color="colour51" ;;
        esac

        tmux set-window-option -t "$session_name:$window_name" window-status-current-style "fg=black,bg=$window_color,bold"
        tmux set-window-option -t "$session_name:$window_name" window-status-style "fg=$window_color,bg=default"
    fi

    # Get pane count and create layout
    local pane_count=$(yaml_get_pane_count "$window_name")
    if [[ $pane_count -gt 1 ]]; then
        create_pane_layout "$session_name:$window_name" "$pane_count" "$window_dir"
    fi

    sleep 0.2

    # Phase 1: Setup direct command panes (not subsessions)
    for ((i=0; i<pane_count; i++)); do
        local pane_type=$(yaml_get_pane "$window_name" "$i" "type")
        if [[ "$pane_type" == "command" ]]; then
            setup_pane "$session_name:$window_name" "$i" "$window_name"
        fi
    done
}

# Phase 2: Attach subsession panes (after all windows are stable)
attach_window_subsessions() {
    local session_name="$1"
    local window_name="$2"

    local pane_count=$(yaml_get_pane_count "$window_name")

    for ((i=0; i<pane_count; i++)); do
        local pane_type=$(yaml_get_pane "$window_name" "$i" "type")
        if [[ "$pane_type" == "subsession" ]]; then
            setup_pane "$session_name:$window_name" "$i" "$window_name"
            sleep 0.05
        fi
    done
}

# Start session
start_session() {
    local headless_mode="${1:-}"

    if [[ "$headless_mode" == "--headless" ]]; then
        log "Starting session in headless mode..."
    else
        log "Starting session..."
    fi

    command -v tmux >/dev/null || die "tmux not found"

    TIMEZONE_SCRIPT=$(create_timezone_script)
    create_tmux_config "$TIMEZONE_SCRIPT"

    # If session exists, just attach
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log "Session $SESSION_NAME already exists"
        tmux set-option -u window-size 2>/dev/null || true
        if [[ "$headless_mode" != "--headless" ]]; then
            exec tmux attach-session -t "$SESSION_NAME"
        else
            log "Session running in background"
        fi
        return 0
    fi

    log "Creating new session: $SESSION_NAME"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

    # Pre-create all subsessions
    log "Pre-creating subsessions..."
    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue

        local sub_dir=$(yaml_get_subsession "$sub_name" "dir")
        local sub_cmd=$(yaml_get_subsession "$sub_name" "command")
        local sub_delay=$(yaml_get_subsession "$sub_name" "delay")

        [[ -z "$sub_dir" ]] && sub_dir="."
        sub_dir=$(resolve_dir "$sub_dir")

        start_subsession "$sub_name" "$sub_dir" "$sub_cmd" "${sub_delay:-0}" ""
    done < <(yaml_get_subsessions)

    # Apply subsession colors
    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue
        # Find which window references this subsession and use that window's color
        while IFS= read -r win_name; do
            [[ -z "$win_name" ]] && continue
            local pcount=$(yaml_get_pane_count "$win_name")
            for ((pi=0; pi<pcount; pi++)); do
                local pt=$(yaml_get_pane "$win_name" "$pi" "type")
                local ps=$(yaml_get_pane "$win_name" "$pi" "subsession")
                if [[ "$pt" == "subsession" && "$ps" == "$sub_name" ]]; then
                    local wcolor=$(yaml_get_window "$win_name" "color")
                    if [[ -n "$wcolor" ]]; then
                        apply_subsession_colors "$sub_name" "$wcolor" "$TIMEZONE_SCRIPT"
                    fi
                    break 2
                fi
            done
        done < <(yaml_get_windows)
    done < <(yaml_get_subsessions)

    # Create main session
    tmux -f /tmp/session-tmux.conf new-session -d -s "$SESSION_NAME"
    tmux set-option -u window-size 2>/dev/null || true
    exclude_from_resurrect "$SESSION_NAME"
    apply_session_colors "$SESSION_NAME" "$TIMEZONE_SCRIPT"

    # Phase 1: Create all windows with direct command panes
    local first_window=true
    while IFS= read -r window_name; do
        [[ -z "$window_name" ]] && continue
        create_window "$SESSION_NAME" "$window_name" "$first_window"
        first_window=false
    done < <(yaml_get_windows)

    # Phase 2: Attach subsessions to panes (after windows are stable)
    log "Attaching subsessions to stable windows..."
    sleep 0.3
    while IFS= read -r window_name; do
        [[ -z "$window_name" ]] && continue
        attach_window_subsessions "$SESSION_NAME" "$window_name"
    done < <(yaml_get_windows)

    # Focus first window
    tmux select-window -t "$SESSION_NAME:1"
    tmux select-pane -t "$SESSION_NAME:1.0"

    if [[ "$headless_mode" == "--headless" ]]; then
        log "Session ready and running in background"
    else
        log "Attaching to session..."
        exec tmux attach-session -t "$SESSION_NAME"
    fi
}

# Stop session (keep subsessions)
stop_session() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log "Stopping main session: $SESSION_NAME"
        tmux kill-session -t "$SESSION_NAME"

        # Report remaining subsessions
        while IFS= read -r sub_name; do
            [[ -z "$sub_name" ]] && continue
            if subsession_exists "$sub_name"; then
                log "Subsession still running: $sub_name"
            fi
        done < <(yaml_get_subsessions)
    else
        log "Session not running: $SESSION_NAME"
    fi

    rm -f /tmp/session-tmux.conf "/tmp/${SESSION_NAME}-time.sh"
}

# Show session status
show_session_status() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Main session: $SESSION_NAME (running)"
        local windows
        windows=$(tmux list-windows -t "$SESSION_NAME" -F "#{window_name}" 2>/dev/null | tr '\n' ' ')
        echo "  Windows: $windows"
    else
        echo "Main session: $SESSION_NAME (not running)"
    fi

    echo "Subsessions:"
    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue
        if subsession_exists "$sub_name"; then
            echo "  $sub_name: running"
        else
            echo "  $sub_name: stopped"
        fi
    done < <(yaml_get_subsessions)
}

# Kill all sessions and subsessions
kill_all_sessions() {
    local sessions=()

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        sessions+=("$SESSION_NAME (main)")
    fi

    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue
        if subsession_exists "$sub_name"; then
            sessions+=("$sub_name")
        fi
    done < <(yaml_get_subsessions)

    if [[ ${#sessions[@]} -eq 0 ]]; then
        log "No sessions found"
        return 0
    fi

    echo "This will kill the following sessions:"
    printf "  - %s\n" "${sessions[@]}"
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cancelled"
        return 0
    fi

    # Kill subsessions first
    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue
        if subsession_exists "$sub_name"; then
            log "Killing subsession: $sub_name"
            tmux kill-session -t "$sub_name"
        fi
    done < <(yaml_get_subsessions)

    # Kill main session
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log "Killing main session: $SESSION_NAME"
        tmux kill-session -t "$SESSION_NAME"
    fi

    log "All sessions terminated"
    rm -f /tmp/session-tmux.conf "/tmp/${SESSION_NAME}-time.sh"
}