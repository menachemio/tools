#!/usr/bin/env bash
# Migration script to convert bash session configs to YAML

set -euo pipefail

# Convert bash config to YAML
convert_bash_to_yaml() {
    local bash_config="$1"
    local output_file="$2"
    
    if [[ ! -f "$bash_config" ]]; then
        echo "Error: Bash config not found: $bash_config" >&2
        return 1
    fi
    
    echo "Converting $bash_config to $output_file"
    
    # Source the bash config to extract variables
    local temp_dir=$(mktemp -d)
    local extract_script="$temp_dir/extract.sh"
    
    cat > "$extract_script" << 'EOF'
#!/usr/bin/env bash
source "$1"

# Extract basic session info
echo "SESSION_NAME=${SESSION_NAME:-}"
echo "SESSION_COLOR=${SESSION_COLOR:-}"
echo "SESSION_TIMEZONE=${SESSION_TIMEZONE:-America/New_York}"
echo "SHOW_UTC=${SHOW_UTC:-true}"

# Extract windows
echo "WINDOWS=(${WINDOWS[*]:-})"

# Extract window directories and colors
for window in "${WINDOWS[@]:-}"; do
    if [[ -n "${WINDOW_DIRS[$window]:-}" ]]; then
        echo "WINDOW_DIR_${window^^}=${WINDOW_DIRS[$window]}"
    fi
    if [[ -n "${WINDOW_COLORS[$window]:-}" ]]; then
        echo "WINDOW_COLOR_${window^^}=${WINDOW_COLORS[$window]}"
    fi
    
    # Extract pane arrays
    local panes_var="${window^^}_PANES[@]"
    local sessions_var="${window^^}_SESSIONS[@]"
    
    if [[ -v "${window^^}_PANES" ]]; then
        echo "PANES_${window^^}=(${!panes_var:-})"
    fi
    if [[ -v "${window^^}_SESSIONS" ]]; then
        echo "SESSIONS_${window^^}=(${!sessions_var:-})"
    fi
done
EOF
    
    chmod +x "$extract_script"
    
    # Extract variables
    local vars_file="$temp_dir/vars"
    "$extract_script" "$bash_config" > "$vars_file" 2>/dev/null || {
        echo "Error: Failed to extract variables from bash config" >&2
        rm -rf "$temp_dir"
        return 1
    }
    
    # Source extracted variables
    source "$vars_file"
    
    # Start building YAML
    cat > "$output_file" << EOF
# Generated from $bash_config
name: ${SESSION_NAME}
timezone: ${SESSION_TIMEZONE:-America/New_York}
show_utc: ${SHOW_UTC:-true}
EOF
    
    if [[ -n "${SESSION_COLOR:-}" ]]; then
        echo "color: ${SESSION_COLOR}" >> "$output_file"
    fi
    
    echo "" >> "$output_file"
    
    # Build subsessions section
    local has_subsessions=false
    
    # First pass: collect all unique subsessions
    declare -A all_subsessions
    for window in ${WINDOWS[*]:-}; do
        local sessions_var="SESSIONS_${window^^}[@]"
        if [[ -v "SESSIONS_${window^^}" ]]; then
            local sessions_ref
            eval "sessions_ref=(\"\${$sessions_var}\")"
            for session in "${sessions_ref[@]}"; do
                if [[ -n "$session" ]]; then
                    all_subsessions["$session"]=1
                    has_subsessions=true
                fi
            done
        fi
    done
    
    if [[ "$has_subsessions" == true ]]; then
        echo "subsessions:" >> "$output_file"
        for subsession in "${!all_subsessions[@]}"; do
            # Try to infer subsession config
            local subsession_dir=""
            local subsession_cmd=""
            
            # Find which window this subsession belongs to
            for window in ${WINDOWS[*]:-}; do
                local sessions_var="SESSIONS_${window^^}[@]"
                if [[ -v "SESSIONS_${window^^}" ]]; then
                    local sessions_ref
                    eval "sessions_ref=(\"\${$sessions_var}\")"
                    for i in "${!sessions_ref[@]}"; do
                        if [[ "${sessions_ref[$i]}" == "$subsession" ]]; then
                            # Get corresponding pane command
                            local panes_var="PANES_${window^^}[@]"
                            if [[ -v "PANES_${window^^}" ]]; then
                                local panes_ref
                                eval "panes_ref=(\"\${$panes_var}\")"
                                if [[ $i -lt ${#panes_ref[@]} ]]; then
                                    subsession_cmd="${panes_ref[$i]}"
                                fi
                            fi
                            
                            # Get window directory
                            local dir_var="WINDOW_DIR_${window^^}"
                            if [[ -v "$dir_var" ]]; then
                                eval "subsession_dir=\$$dir_var"
                            fi
                            break 2
                        fi
                    done
                fi
            done
            
            cat >> "$output_file" << EOF
  $subsession:
    dir: ${subsession_dir:-.}
    command: ${subsession_cmd:-bash}
EOF
        done
        echo "" >> "$output_file"
    fi
    
    # Build windows section
    if [[ ${#WINDOWS[@]} -gt 0 ]]; then
        echo "windows:" >> "$output_file"
        
        for window in "${WINDOWS[@]}"; do
            echo "  - name: $window" >> "$output_file"
            
            # Add window directory
            local dir_var="WINDOW_DIR_${window^^}"
            if [[ -v "$dir_var" ]]; then
                eval "local window_dir=\$$dir_var"
                echo "    dir: $window_dir" >> "$output_file"
            fi
            
            # Add window color
            local color_var="WINDOW_COLOR_${window^^}"
            if [[ -v "$color_var" ]]; then
                eval "local window_color=\$$color_var"
                # Convert tmux color to simple name
                case "$window_color" in
                    "colour196"|"red") window_color="red" ;;
                    "colour46"|"green") window_color="green" ;;
                    "colour33"|"blue") window_color="blue" ;;
                    "colour226"|"yellow") window_color="yellow" ;;
                    "colour202"|"orange") window_color="orange" ;;
                    "colour201"|"magenta"|"purple") window_color="purple" ;;
                    "colour51"|"cyan") window_color="cyan" ;;
                esac
                echo "    color: $window_color" >> "$output_file"
            fi
            
            # Add panes
            local panes_var="PANES_${window^^}[@]"
            local sessions_var="SESSIONS_${window^^}[@]"
            
            if [[ -v "PANES_${window^^}" ]]; then
                eval "local panes_ref=(\"\${$panes_var}\")"
                local sessions_ref=()
                if [[ -v "SESSIONS_${window^^}" ]]; then
                    eval "sessions_ref=(\"\${$sessions_var}\")"
                fi
                
                echo "    panes:" >> "$output_file"
                
                for i in "${!panes_ref[@]}"; do
                    local cmd="${panes_ref[$i]}"
                    local session_name=""
                    if [[ $i -lt ${#sessions_ref[@]} ]]; then
                        session_name="${sessions_ref[$i]}"
                    fi
                    
                    if [[ -n "$session_name" ]]; then
                        # Subsession pane
                        cat >> "$output_file" << EOF
      - type: subsession
        subsession: $session_name
EOF
                    else
                        # Command pane
                        local execute="true"
                        local history="true"
                        
                        cat >> "$output_file" << EOF
      - type: command
        cmd: $cmd
        execute: $execute
        history: $history
EOF
                    fi
                done
            fi
            echo "" >> "$output_file"
        done
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    echo "Migration complete: $output_file"
}

# Main function
main() {
    local bash_config="$1"
    local output_file="${2:-}"
    
    if [[ $# -eq 0 ]]; then
        echo "Usage: migrate-to-yaml.sh <bash-config> [output-file]"
        echo ""
        echo "Converts bash session configuration to YAML format"
        echo ""
        echo "Examples:"
        echo "  migrate-to-yaml.sh myproject-config.sh"
        echo "  migrate-to-yaml.sh myproject-config.sh myproject.session.yaml"
        exit 1
    fi
    
    if [[ -z "$output_file" ]]; then
        # Generate output filename from input
        local basename=$(basename "$bash_config" .sh)
        basename=$(basename "$basename" -config)
        output_file="${basename}.session.yaml"
    fi
    
    convert_bash_to_yaml "$bash_config" "$output_file"
}

main "$@"