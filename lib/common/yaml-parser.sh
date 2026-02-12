#!/usr/bin/env bash
# YAML Parser for Tools Repository
# Parses session YAML configs without external dependencies

# Global variables for parsed YAML
declare -g -A YAML_VALUES
declare -g -a YAML_SUBSECTIONS
declare -g -a YAML_WINDOWS

# Parse a YAML file and populate global variables
parse_yaml() {
    local yaml_file="$1"
    [[ -f "$yaml_file" ]] || { echo "YAML file not found: $yaml_file" >&2; return 1; }

    # Reset
    YAML_VALUES=()
    YAML_SUBSECTIONS=()
    YAML_WINDOWS=()

    local section=""          # "subsessions" or "windows"
    local subsession_name=""  # Current subsession being parsed
    local window_name=""      # Current window being parsed
    local pane_index=-1       # Current pane index within window
    local in_panes=false      # Whether we're inside a panes: block

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        # Strip comments (but not inside quoted strings - good enough for our configs)
        local line="${raw_line%%#*}"

        # Skip empty/whitespace-only lines
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Measure indent: count leading spaces
        local stripped="${line#"${line%%[! ]*}"}"
        local indent=$(( ${#line} - ${#stripped} ))
        line="$stripped"

        # Also strip trailing whitespace
        line="${line%"${line##*[! ]}"}"

        # --- Indent 0: top-level keys ---
        if [[ $indent -eq 0 ]]; then
            subsession_name=""
            window_name=""
            pane_index=-1
            in_panes=false

            if [[ "$line" == "subsessions:" ]]; then
                section="subsessions"
            elif [[ "$line" == "windows:" ]]; then
                section="windows"
            elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                YAML_VALUES["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi

        # --- Indent 2: subsession names OR window list items ---
        elif [[ $indent -eq 2 ]]; then
            in_panes=false
            pane_index=-1

            if [[ "$section" == "subsessions" ]]; then
                # e.g. "api-shell:"
                if [[ "$line" =~ ^([^:]+):$ ]]; then
                    subsession_name="${BASH_REMATCH[1]}"
                    YAML_SUBSECTIONS+=("$subsession_name")
                fi

            elif [[ "$section" == "windows" ]]; then
                # e.g. "- name: api"
                if [[ "$line" =~ ^-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
                    window_name="${BASH_REMATCH[1]}"
                    YAML_WINDOWS+=("$window_name")
                fi
            fi

        # --- Indent 4: subsession props OR window props OR pane list items ---
        elif [[ $indent -eq 4 ]]; then
            if [[ "$section" == "subsessions" && -n "$subsession_name" ]]; then
                # e.g. "dir: ./api"
                if [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    YAML_VALUES["subsession_${subsession_name}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi

            elif [[ "$section" == "windows" && -n "$window_name" ]]; then
                if [[ "$line" == "panes:" ]]; then
                    in_panes=true
                    pane_index=-1
                elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    YAML_VALUES["window_${window_name}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi
            fi

        # --- Indent 6: pane list items (- type: ...) OR pane properties ---
        elif [[ $indent -eq 6 && "$in_panes" == true && -n "$window_name" ]]; then
            # New pane starts with "- type: ..."
            if [[ "$line" =~ ^-[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
                ((pane_index++))
                YAML_VALUES["window_${window_name}_pane_${pane_index}_type"]="${BASH_REMATCH[1]}"
            # Continuation property of current pane
            elif [[ $pane_index -ge 0 && "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                YAML_VALUES["window_${window_name}_pane_${pane_index}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi

        # --- Indent 8: pane properties when "- type:" was at indent 6 ---
        elif [[ $indent -eq 8 && "$in_panes" == true && $pane_index -ge 0 ]]; then
            if [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                YAML_VALUES["window_${window_name}_pane_${pane_index}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi
        fi
    done < "$yaml_file"

    return 0
}

# Get a top-level value
yaml_get() {
    echo "${YAML_VALUES[$1]:-}"
}

# Get all subsession names
yaml_get_subsessions() {
    printf '%s\n' "${YAML_SUBSECTIONS[@]}"
}

# Get all window names
yaml_get_windows() {
    printf '%s\n' "${YAML_WINDOWS[@]}"
}

# Get subsession property
yaml_get_subsession() {
    local subsession="$1" property="$2"
    echo "${YAML_VALUES["subsession_${subsession}_${property}"]:-}"
}

# Get window property
yaml_get_window() {
    local window="$1" property="$2"
    echo "${YAML_VALUES["window_${window}_${property}"]:-}"
}

# Get pane property
yaml_get_pane() {
    local window="$1" pane_index="$2" property="$3"
    echo "${YAML_VALUES["window_${window}_pane_${pane_index}_${property}"]:-}"
}

# Get pane count for a window
yaml_get_pane_count() {
    local window="$1"
    local count=0
    while [[ -n "${YAML_VALUES["window_${window}_pane_${count}_type"]:-}" ]]; do
        ((count++))
    done
    echo "$count"
}

# Debug: dump all parsed values
yaml_dump() {
    echo "=== Parsed YAML ==="
    echo "Top-level:"
    for key in "${!YAML_VALUES[@]}"; do
        [[ "$key" != subsession_* && "$key" != window_* ]] && echo "  $key = ${YAML_VALUES[$key]}"
    done
    echo "Subsessions: ${YAML_SUBSECTIONS[*]}"
    for sub in "${YAML_SUBSECTIONS[@]}"; do
        echo "  $sub:"
        for key in "${!YAML_VALUES[@]}"; do
            [[ "$key" == "subsession_${sub}_"* ]] && echo "    ${key#subsession_${sub}_} = ${YAML_VALUES[$key]}"
        done
    done
    echo "Windows: ${YAML_WINDOWS[*]}"
    for win in "${YAML_WINDOWS[@]}"; do
        echo "  $win:"
        for key in "${!YAML_VALUES[@]}"; do
            [[ "$key" == "window_${win}_"* ]] && echo "    ${key#window_${win}_} = ${YAML_VALUES[$key]}"
        done
    done
}