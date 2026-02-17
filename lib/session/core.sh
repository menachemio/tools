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

# Leading space prefix for tmux send-keys commands.
# Bash excludes commands starting with a space from history when
# HISTCONTROL includes "ignorespace" or "ignoreboth" (the default).
# All send-keys calls prepend this so session setup never pollutes history.
HIST_SKIP=" "

# Runtime directory for temp files (avoid hardcoded /tmp)
TOOLS_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/tools}/session"
mkdir -p "$TOOLS_RUNTIME_DIR" 2>/dev/null || true

# Logging functions
log() { [[ "$VERBOSE" == "true" ]] && echo ":: $*" >&2 || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Wait for a tmux target to become ready (pane exists and is responsive).
# Falls back to a short sleep if polling fails, with a bounded retry.
wait_for_target() {
    local target="$1"
    local max_attempts="${2:-50}"  # 50 x 100ms = 5s max
    local i=0
    while [[ $i -lt $max_attempts ]]; do
        tmux display-message -t "$target" -p "#{pane_id}" &>/dev/null && return 0
        sleep 0.1
        ((i++)) || true
    done
    log "Timed out waiting for $target after ${max_attempts} attempts"
    return 1
}

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
    if [[ "$dir" != /* ]]; then
        dir="$CONFIG_DIR/$dir"
    fi
    # Normalize /./ and trailing /. so paths are clean in pane output
    dir="${dir//\/.\//\/}"
    dir="${dir%/.}"
    echo "$dir"
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

    # Validate windows exist
    local window_list
    window_list=$(yaml_get_windows)
    if [[ -z "$window_list" ]]; then
        die "No windows defined in configuration"
    fi

    # Validate each window has at least one pane
    while IFS= read -r wname; do
        [[ -z "$wname" ]] && continue
        local pc
        pc=$(yaml_get_pane_count "$wname")
        if [[ "$pc" -eq 0 ]]; then
            die "Window '$wname' has no panes defined"
        fi
    done <<< "$window_list"

    # Validate subsession references in panes point to defined subsessions
    while IFS= read -r wname; do
        [[ -z "$wname" ]] && continue
        local pc
        pc=$(yaml_get_pane_count "$wname")
        for ((pi=0; pi<pc; pi++)); do
            local ptype
            ptype=$(yaml_get_pane "$wname" "$pi" "type")
            if [[ "$ptype" == "subsession" ]]; then
                local sref
                sref=$(yaml_get_pane "$wname" "$pi" "subsession")
                if [[ -z "$sref" ]]; then
                    die "Window '$wname' pane $pi: subsession type but no subsession name specified"
                fi
                local sdir
                sdir=$(yaml_get_subsession "$sref" "dir")
                if [[ -z "$sdir" ]]; then
                    die "Subsession '$sref' referenced in window '$wname' is not defined in subsessions section"
                fi
            fi
        done
    done <<< "$window_list"

    log "Loaded session: $SESSION_NAME"
}

# Create timezone script for status bar
create_timezone_script() {
    local script="${TOOLS_RUNTIME_DIR}/${SESSION_NAME}-time.sh"
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
# This is the authoritative config -- loaded via -f, bypassing ~/.tmux.conf
# Options under tmux.global in YAML override these defaults.
create_tmux_config() {
    local timezone_script="$1"
    local conf="${TOOLS_RUNTIME_DIR}/session-tmux.conf"

    # Resolve all options: YAML tmux.global override -> hardcoded default.
    # Direct associative array access — no subshells.
    local opt_prefix="${YAML_VALUES["tmux_global_prefix"]:-C-b}"
    local opt_default_terminal="${YAML_VALUES["tmux_global_default-terminal"]:-tmux-256color}"
    local opt_terminal_overrides="${YAML_VALUES["tmux_global_terminal-overrides"]:-,*256col*:Tc}"
    local opt_escape_time="${YAML_VALUES["tmux_global_escape-time"]:-10}"
    local opt_focus_events="${YAML_VALUES["tmux_global_focus-events"]:-on}"
    local opt_mouse="${YAML_VALUES["tmux_global_mouse"]:-on}"
    local opt_set_clipboard="${YAML_VALUES["tmux_global_set-clipboard"]:-on}"
    local opt_copy_command="${YAML_VALUES["tmux_global_copy-command"]:-xclip -selection clipboard 2>/dev/null || wl-copy 2>/dev/null || pbcopy 2>/dev/null}"
    local opt_base_index="${YAML_VALUES["tmux_global_base-index"]:-1}"
    local opt_pane_base_index="${YAML_VALUES["tmux_global_pane-base-index"]:-1}"
    local opt_renumber_windows="${YAML_VALUES["tmux_global_renumber-windows"]:-on}"
    local opt_status="${YAML_VALUES["tmux_global_status"]:-on}"
    local opt_status_interval="${YAML_VALUES["tmux_global_status-interval"]:-1}"
    local opt_status_position="${YAML_VALUES["tmux_global_status-position"]:-bottom}"
    local opt_status_justify="${YAML_VALUES["tmux_global_status-justify"]:-centre}"
    local opt_status_left_length="${YAML_VALUES["tmux_global_status-left-length"]:-50}"
    local opt_status_right_length="${YAML_VALUES["tmux_global_status-right-length"]:-100}"
    local opt_status_style="${YAML_VALUES["tmux_global_status-style"]:-bg=black,fg=white}"
    local opt_status_left="${YAML_VALUES["tmux_global_status-left"]:- #S  }"
    local opt_status_right="${YAML_VALUES["tmux_global_status-right"]:-#($timezone_script)}"
    local opt_pane_border_style="${YAML_VALUES["tmux_global_pane-border-style"]:-fg=brightblack}"
    local opt_pane_active_border_style="${YAML_VALUES["tmux_global_pane-active-border-style"]:-fg=white}"
    local opt_mode_keys="${YAML_VALUES["tmux_global_mode-keys"]:-vi}"

    cat > "$conf" << EOF
# Session Manager tmux configuration (authoritative)
# Loaded via -f on server start -- ~/.tmux.conf is bypassed
# Options can be overridden via the tmux.global section in session YAML

# Prefix key
set-option -g prefix ${opt_prefix}
bind-key ${opt_prefix} send-prefix

# Terminal
set -g default-terminal "${opt_default_terminal}"
set -ga terminal-overrides "${opt_terminal_overrides}"
set-option -sg escape-time ${opt_escape_time}
set-option -g focus-events ${opt_focus_events}

# Mouse
set -g mouse ${opt_mouse}

# Clipboard
set -g set-clipboard ${opt_set_clipboard}
set -s copy-command '${opt_copy_command}'

# Indexing
set -g base-index ${opt_base_index}
setw -g pane-base-index ${opt_pane_base_index}
set -g renumber-windows ${opt_renumber_windows}

# Status bar defaults
set -g status ${opt_status}
set -g status-interval ${opt_status_interval}
set -g status-position ${opt_status_position}
set -g status-justify ${opt_status_justify}
set -g status-left-length ${opt_status_left_length}
set -g status-right-length ${opt_status_right_length}
set -g status-style '${opt_status_style}'
set -g status-left '${opt_status_left}'
set -g status-right '${opt_status_right}'

# Pane borders
set -g pane-border-style ${opt_pane_border_style}
set -g pane-active-border-style ${opt_pane_active_border_style}

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

# Vi mode with clipboard
setw -g mode-keys ${opt_mode_keys}
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "${opt_copy_command}"
EOF

    # Dynamic window bindings
    local window_count
    window_count=$(yaml_get_windows | wc -l)
    local max=$((window_count > 20 ? 20 : window_count))
    for ((i=1; i<=max; i++)); do
        echo "bind -n M-$i select-window -t $i" >> "$conf"
    done

    cat >> "$conf" << 'EOF'

# Quick window switching
bind -n M-n next-window
bind -n M-p previous-window
EOF

    # Append any extra tmux.global options not already handled above.
    # This is a catch-all: if the user specifies a global option that is NOT
    # one of the known keys above, we emit it as a raw set-option -g line.
    local known_global_keys=(
        "prefix" "default-terminal" "terminal-overrides" "escape-time"
        "focus-events" "mouse" "set-clipboard" "copy-command"
        "base-index" "pane-base-index" "renumber-windows"
        "status" "status-interval" "status-position" "status-justify"
        "status-left-length" "status-right-length" "status-style"
        "status-left" "status-right"
        "pane-border-style" "pane-active-border-style" "mode-keys"
    )

    while IFS= read -r gkey; do
        [[ -z "$gkey" ]] && continue
        # Skip if it is one of the known keys (already handled above)
        local is_known=false
        for kk in "${known_global_keys[@]}"; do
            if [[ "$gkey" == "$kk" ]]; then
                is_known=true
                break
            fi
        done
        if [[ "$is_known" == false ]]; then
            local gval
            gval=$(yaml_get_tmux_global "$gkey")
            # Reject keys/values containing newlines or semicolons (tmux command injection)
            if [[ "$gkey" == *[$'\n;']* || "$gval" == *[$'\n;']* ]]; then
                log "Skipping unsafe tmux global option: $gkey"
                continue
            fi
            echo "set-option -g ${gkey} '${gval}'" >> "$conf"
        fi
    done < <(yaml_list_tmux_global_keys)
}

# Apply tmux options from YAML_VALUES by prefix to a tmux target.
# Iterates all keys matching the prefix and applies them via the given tmux command.
_apply_tmux_opts() {
    local target="$1" tmux_cmd="$2" prefix="$3"
    for key in "${!YAML_VALUES[@]}"; do
        if [[ "$key" == ${prefix}* ]]; then
            local opt="${key#${prefix}}"
            tmux "$tmux_cmd" -t "$target" "$opt" "${YAML_VALUES[$key]}" 2>/dev/null || \
                log "Failed to set option ($target): $opt"
        fi
    done
}

# Apply tmux session-level options from YAML tmux.session section
apply_tmux_session_options() {
    _apply_tmux_opts "$1" "set-option" "tmux_session_"
}

# Apply tmux window-level options from YAML
apply_tmux_window_options() {
    _apply_tmux_opts "$1:$2" "set-window-option" "tmux_window_${2}_"
}

# Exclude session from tmux-resurrect if available (per-session option)
exclude_from_resurrect() {
    tmux set-option -t "$1" @resurrect-exclude 1 2>/dev/null || true
}

# Apply session color scheme.
# The legacy `color:` top-level key is syntactic sugar for tmux.session status options.
# If tmux.session options are defined, they take priority over `color:`.
_apply_color_defaults() {
    local target="$1" color="$2" timezone_script="$3"
    local ov_style="$4" ov_left="$5" ov_right="$6"

    [[ -z "$color" ]] && return

    if [[ -z "$ov_style" ]]; then
        tmux set-option -t "$target" status-style "fg=${color},bg=default" 2>/dev/null || true
    fi
    if [[ -z "$ov_left" ]]; then
        tmux set-option -t "$target" status-left "#[fg=${color},bold] #S #[default]" 2>/dev/null || true
    fi
    if [[ -n "$timezone_script" && -z "$ov_right" ]]; then
        tmux set-option -t "$target" status-right "#[fg=${color}] #($timezone_script) #[default]" 2>/dev/null || true
    fi
}

apply_session_colors() {
    local session_name="$1"
    local timezone_script="$2"

    wait_for_target "$session_name" || { log "Skipping colors for $session_name"; return; }

    # Apply explicit tmux.session options first (these are authoritative)
    apply_tmux_session_options "$session_name"

    local session_color=$(yaml_get "color")
    [[ -z "$session_color" ]] && return

    _apply_color_defaults "$session_name" "$session_color" "$timezone_script" \
        "$(yaml_get_tmux_session "status-style")" \
        "$(yaml_get_tmux_session "status-left")" \
        "$(yaml_get_tmux_session "status-right")"

    if [[ -z "$(yaml_get_tmux_session "status-justify")" ]]; then
        tmux set-option -t "$session_name" status-justify centre 2>/dev/null || true
    fi

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
        width=$(tmux display-message -t "$target" -p "#{window_width}")
        height=$(tmux display-message -t "$target" -p "#{window_height}")
        log "Post-resize dimensions: ${width}x${height}"
    fi

    case $pane_count in
        1) return 0 ;;
        2)
            tmux split-window -h -t "$target" -c "$working_dir" 2>/dev/null || true
            ;;
        3)
            tmux split-window -h -t "$target" -c "$working_dir" 2>/dev/null || true
            tmux split-window -v -t "${target}.2" -c "$working_dir" 2>/dev/null || true
            ;;
        4)
            tmux split-window -v -t "$target" -c "$working_dir" 2>/dev/null || true
            tmux split-window -h -t "${target}.1" -c "$working_dir" 2>/dev/null || true
            tmux split-window -h -t "${target}.3" -c "$working_dir" 2>/dev/null || true
            tmux select-layout -t "$target" tiled 2>/dev/null || true
            ;;
        *)
            for ((i=1; i<pane_count; i++)); do
                tmux split-window -v -t "$target" -c "$working_dir" 2>/dev/null || break
            done
            tmux select-layout -t "$target" tiled 2>/dev/null || true
            ;;
    esac

    wait_for_target "$target" || true
    local actual=$(tmux list-panes -t "$target" | wc -l)
    log "Window $target: requested $pane_count, created $actual panes"
    if [[ $actual -lt $pane_count ]]; then
        echo "WARNING: Window $target: only $actual of $pane_count panes created (split-window may have failed)" >&2
    fi
}

# Setup individual pane
setup_pane() {
    local window_target="$1"
    local pane_index="$2"
    local window_name="$3"
    local pane_target="${window_target}.$((pane_index + 1))"

    local pane_type=$(yaml_get_pane "$window_name" "$pane_index" "type")

    case "$pane_type" in
        "subsession")
            local subsession_name=$(yaml_get_pane "$window_name" "$pane_index" "subsession")
            if [[ -n "$subsession_name" ]]; then
                local pane_cmd=$(yaml_get_pane "$window_name" "$pane_index" "cmd")
                ensure_subsession "$subsession_name"
                wait_for_target "$pane_target" || true
                attach_pane_to_subsession "$pane_target" "$subsession_name" "$pane_cmd"
            fi
            ;;
        "command")
            if ! tmux display-message -t "$pane_target" -p "#{pane_id}" &>/dev/null; then
                log "Pane $pane_target does not exist, skipping command setup"
                return
            fi

            local cmd=$(yaml_get_pane "$window_name" "$pane_index" "cmd")
            local execute=$(yaml_get_pane "$window_name" "$pane_index" "execute")
            local history=$(yaml_get_pane "$window_name" "$pane_index" "history")

            if [[ -n "$cmd" ]]; then
                if [[ "$execute" == "true" ]]; then
                    tmux send-keys -t "$pane_target" "${HIST_SKIP}$cmd" Enter 2>/dev/null || true

                    # Optionally add to history
                    if [[ "$history" == "true" ]]; then
                        echo "$cmd" >> ~/.bash_history
                    fi
                else
                    # Pre-fill command text, don't execute (wait for Enter)
                    tmux send-keys -t "$pane_target" "$cmd" 2>/dev/null || true
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
    # First window inherits cwd from new-session -c; subsequent windows use new-window -c
    if [[ "$is_first_window" == "true" ]]; then
        tmux rename-window -t "$session_name" "$window_name" 2>/dev/null || true
    else
        tmux new-window -t "$session_name" -n "$window_name" -c "$window_dir" || \
            { log "Failed to create window: $window_name"; return; }
    fi

    # Apply window colors from the legacy `color:` key
    if [[ -n "$window_color" ]]; then
        tmux set-window-option -t "$session_name:$window_name" window-status-current-style "fg=white,bg=$window_color,bold" 2>/dev/null || true
        tmux set-window-option -t "$session_name:$window_name" window-status-style "fg=$window_color,bg=default" 2>/dev/null || true
    fi

    # Apply per-window tmux options from YAML (overrides color: convenience styling)
    apply_tmux_window_options "$session_name" "$window_name"

    # Get pane count and create layout
    local pane_count=$(yaml_get_pane_count "$window_name")
    if [[ $pane_count -gt 1 ]]; then
        create_pane_layout "$session_name:$window_name" "$pane_count" "$window_dir"
    fi

    wait_for_target "$session_name:$window_name" || true

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

    # Regenerate config if missing (bin/session pre-generates, but restart deletes it)
    if [[ ! -f "${TOOLS_RUNTIME_DIR}/session-tmux.conf" ]]; then
        TIMEZONE_SCRIPT=$(create_timezone_script)
        create_tmux_config "$TIMEZONE_SCRIPT"
    fi

    # Warn about missing binaries referenced in pane commands and subsessions
    local _key _val _bin
    local -A _seen_bins
    for _key in "${!YAML_VALUES[@]}"; do
        case "$_key" in
            window_*_pane_*_cmd)    _val="${YAML_VALUES[$_key]}" ;;
            subsession_*_command)   _val="${YAML_VALUES[$_key]}" ;;
            *)                      continue ;;
        esac
        _bin="${_val%% *}"
        [[ -z "$_bin" || -n "${_seen_bins[$_bin]+x}" ]] && continue
        _seen_bins["$_bin"]=1
        command -v "$_bin" >/dev/null 2>&1 || \
            log "WARNING: '$_bin' not found in PATH (referenced in config)"
    done

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

    # Resolve first window dir so new-session starts with the right cwd natively
    local first_win_dir
    first_win_dir=$(yaml_get_window "$(yaml_get_windows | head -1)" "dir")
    [[ -z "$first_win_dir" ]] && first_win_dir="."
    first_win_dir=$(resolve_dir "$first_win_dir")

    # Create main session (-f bypasses ~/.tmux.conf on fresh server start)
    # bin/session already sourced config for existing servers; -f handles new servers
    tmux -f "${TOOLS_RUNTIME_DIR}/session-tmux.conf" new-session -d -s "$SESSION_NAME" -c "$first_win_dir" || \
        die "Failed to create tmux session: $SESSION_NAME"
    tmux set-option -u window-size 2>/dev/null || true
    exclude_from_resurrect "$SESSION_NAME"
    apply_session_colors "$SESSION_NAME" "$TIMEZONE_SCRIPT"

    # Pre-create all subsessions and apply their colors/options in one pass
    log "Pre-creating subsessions..."
    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue

        local sub_dir=$(yaml_get_subsession "$sub_name" "dir")
        local sub_cmd=$(yaml_get_subsession "$sub_name" "command")
        local sub_delay=$(yaml_get_subsession "$sub_name" "delay")
        local sub_env=$(yaml_get_subsession "$sub_name" "env")
        local sub_execute=$(yaml_get_subsession "$sub_name" "execute")
        local sub_history=$(yaml_get_subsession "$sub_name" "history")

        [[ -z "$sub_dir" ]] && sub_dir="."
        sub_dir=$(resolve_dir "$sub_dir")

        start_subsession "$sub_name" "$sub_dir" "$sub_cmd" "${sub_delay:-0}" "$sub_env" "$sub_execute" "$sub_history" || continue
        _apply_subsession_color "$sub_name"
        apply_tmux_subsession_options "$sub_name"
    done < <(yaml_get_subsessions)

    # Phase 1: Create all windows with direct command panes
    local first_window=true
    while IFS= read -r window_name; do
        [[ -z "$window_name" ]] && continue
        create_window "$SESSION_NAME" "$window_name" "$first_window"
        first_window=false
    done < <(yaml_get_windows)

    # Phase 2: Attach subsessions to panes (after windows are stable)
    log "Attaching subsessions to stable windows..."
    wait_for_target "$SESSION_NAME:1" || true
    while IFS= read -r window_name; do
        [[ -z "$window_name" ]] && continue
        attach_window_subsessions "$SESSION_NAME" "$window_name"
    done < <(yaml_get_windows)

    # Focus first window
    tmux select-window -t "$SESSION_NAME:1" 2>/dev/null || true
    tmux select-pane -t "$SESSION_NAME:1.1" 2>/dev/null || true

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
        tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

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

    rm -f "${TOOLS_RUNTIME_DIR}/session-tmux.conf" "${TOOLS_RUNTIME_DIR}/${SESSION_NAME}-time.sh"
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

# Refresh tmux settings for running session without restarting processes
refresh_session() {
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        die "Session '$SESSION_NAME' is not running"
    fi

    log "Refreshing session: $SESSION_NAME"

    # Regenerate timezone script and tmux config, then re-source
    TIMEZONE_SCRIPT=$(create_timezone_script)
    create_tmux_config "$TIMEZONE_SCRIPT"
    tmux source-file "${TOOLS_RUNTIME_DIR}/session-tmux.conf" 2>/dev/null || true

    # Re-apply session-level colors and options
    apply_session_colors "$SESSION_NAME" "$TIMEZONE_SCRIPT"

    # Re-apply per-window styling
    local running_windows
    running_windows=$(tmux list-windows -t "$SESSION_NAME" -F "#{window_name}" 2>/dev/null) || running_windows=""
    while IFS= read -r window_name; do
        [[ -z "$window_name" ]] && continue

        # Skip windows not present in the running session
        if ! grep -qxF "$window_name" <<< "$running_windows"; then
            log "Window '$window_name' not in running session, skipping"
            continue
        fi

        # Re-apply legacy color: styling
        local window_color
        window_color=$(yaml_get_window "$window_name" "color")
        if [[ -n "$window_color" ]]; then
            tmux set-window-option -t "$SESSION_NAME:$window_name" window-status-current-style "fg=white,bg=$window_color,bold" 2>/dev/null || true
            tmux set-window-option -t "$SESSION_NAME:$window_name" window-status-style "fg=$window_color,bg=default" 2>/dev/null || true
        fi

        # Re-apply per-window tmux options
        apply_tmux_window_options "$SESSION_NAME" "$window_name"
    done < <(yaml_get_windows)

    # Re-apply per-subsession styling
    while IFS= read -r sub_name; do
        [[ -z "$sub_name" ]] && continue

        if ! subsession_exists "$sub_name"; then
            log "Subsession '$sub_name' not running, skipping"
            continue
        fi

        _apply_subsession_color "$sub_name"
        apply_tmux_subsession_options "$sub_name"
    done < <(yaml_get_subsessions)

    echo "Refreshed session '$SESSION_NAME'"
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
            tmux kill-session -t "$sub_name" 2>/dev/null || true
        fi
    done < <(yaml_get_subsessions)

    # Kill main session
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log "Killing main session: $SESSION_NAME"
        tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    fi

    log "All sessions terminated"
    rm -f "${TOOLS_RUNTIME_DIR}/session-tmux.conf" "${TOOLS_RUNTIME_DIR}/${SESSION_NAME}-time.sh"
}
