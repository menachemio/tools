#!/usr/bin/env bash
# YAML Parser for Tools Repository
# Parses session YAML configs without external dependencies

# Global variables for parsed YAML
declare -g -A YAML_VALUES
declare -g -a YAML_SUBSECTIONS
declare -g -a YAML_WINDOWS

# Stores tmux option keys per scope so we can iterate them later.
# Entries are: tmux_global_<option>, tmux_session_<option>,
#              tmux_subsession_<name>_<option>, tmux_window_<name>_<option>
# The keys themselves are stored in list arrays for enumeration.
declare -g -a YAML_TMUX_GLOBAL_KEYS
declare -g -a YAML_TMUX_SESSION_KEYS

# Strip YAML comments while preserving # inside quoted strings.
# Handles both single and double quotes.
_strip_yaml_comment() {
    local raw="$1"
    local in_sq=false in_dq=false
    local i=0 len=${#raw}
    local result=""

    while [[ $i -lt $len ]]; do
        local ch="${raw:$i:1}"

        if [[ "$ch" == "'" && "$in_dq" == false ]]; then
            [[ "$in_sq" == true ]] && in_sq=false || in_sq=true
        elif [[ "$ch" == '"' && "$in_sq" == false ]]; then
            [[ "$in_dq" == true ]] && in_dq=false || in_dq=true
        elif [[ "$ch" == '#' && "$in_sq" == false && "$in_dq" == false ]]; then
            # Unquoted # preceded by whitespace or at start -> comment
            if [[ $i -eq 0 || "${raw:$((i-1)):1}" == " " || "${raw:$((i-1)):1}" == "	" ]]; then
                break
            fi
        fi
        result+="$ch"
        ((i++)) || true
    done
    echo "$result"
}

# Parse a YAML file and populate global variables
parse_yaml() {
    local yaml_file="$1"
    [[ -f "$yaml_file" ]] || { echo "YAML file not found: $yaml_file" >&2; return 1; }

    # Reset
    YAML_VALUES=()
    YAML_SUBSECTIONS=()
    YAML_WINDOWS=()
    YAML_TMUX_GLOBAL_KEYS=()
    YAML_TMUX_SESSION_KEYS=()

    local section=""          # "subsessions", "windows", or "tmux"
    local subsession_name=""  # Current subsession being parsed
    local window_name=""      # Current window being parsed
    local pane_index=-1       # Current pane index within window
    local in_panes=false      # Whether we're inside a panes: block

    # tmux sub-section tracking
    local tmux_scope=""       # "global" or "session" (top-level tmux:)
                              # also used for window/subsession-level tmux blocks
    local tmux_owner=""       # The parent scope name (window name or subsession name)

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        # Strip comments while preserving # inside quoted values
        local line
        line=$(_strip_yaml_comment "$raw_line")

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
            tmux_scope=""
            tmux_owner=""

            if [[ "$line" == "subsessions:" ]]; then
                section="subsessions"
            elif [[ "$line" == "windows:" ]]; then
                section="windows"
            elif [[ "$line" == "tmux:" ]]; then
                section="tmux"
            elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                YAML_VALUES["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            fi

        # --- Indent 2 ---
        elif [[ $indent -eq 2 ]]; then

            # Top-level tmux: sub-sections (global: / session:)
            if [[ "$section" == "tmux" ]]; then
                pane_index=-1
                in_panes=false
                if [[ "$line" == "global:" ]]; then
                    tmux_scope="global"
                elif [[ "$line" == "session:" ]]; then
                    tmux_scope="session"
                fi
                continue
            fi

            in_panes=false
            pane_index=-1
            tmux_scope=""
            tmux_owner=""

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

        # --- Indent 4 ---
        elif [[ $indent -eq 4 ]]; then

            # Top-level tmux: > global:/session: key-value pairs
            if [[ "$section" == "tmux" && -n "$tmux_scope" ]]; then
                if [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    local tkey="${BASH_REMATCH[1]}"
                    local tval="${BASH_REMATCH[2]}"
                    # Strip surrounding quotes from value
                    tval="${tval#\"}" ; tval="${tval%\"}"
                    tval="${tval#\'}" ; tval="${tval%\'}"

                    YAML_VALUES["tmux_${tmux_scope}_${tkey}"]="$tval"
                    if [[ "$tmux_scope" == "global" ]]; then
                        YAML_TMUX_GLOBAL_KEYS+=("$tkey")
                    elif [[ "$tmux_scope" == "session" ]]; then
                        YAML_TMUX_SESSION_KEYS+=("$tkey")
                    fi
                fi
                continue
            fi

            if [[ "$section" == "subsessions" && -n "$subsession_name" ]]; then
                if [[ "$line" == "tmux:" ]]; then
                    tmux_scope="subsession_inline"
                    tmux_owner="$subsession_name"
                elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    YAML_VALUES["subsession_${subsession_name}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi

            elif [[ "$section" == "windows" && -n "$window_name" ]]; then
                if [[ "$line" == "panes:" ]]; then
                    in_panes=true
                    pane_index=-1
                    tmux_scope=""
                elif [[ "$line" == "tmux:" ]]; then
                    tmux_scope="window_inline"
                    tmux_owner="$window_name"
                    in_panes=false
                elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    YAML_VALUES["window_${window_name}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi
            fi

        # --- Indent 6 ---
        elif [[ $indent -eq 6 ]]; then

            # Inline tmux options for subsessions or windows
            if [[ "$tmux_scope" == "subsession_inline" && -n "$tmux_owner" ]]; then
                if [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    local tkey="${BASH_REMATCH[1]}"
                    local tval="${BASH_REMATCH[2]}"
                    tval="${tval#\"}" ; tval="${tval%\"}"
                    tval="${tval#\'}" ; tval="${tval%\'}"
                    YAML_VALUES["tmux_subsession_${tmux_owner}_${tkey}"]="$tval"
                fi
                continue
            fi

            if [[ "$tmux_scope" == "window_inline" && -n "$tmux_owner" ]]; then
                if [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    local tkey="${BASH_REMATCH[1]}"
                    local tval="${BASH_REMATCH[2]}"
                    tval="${tval#\"}" ; tval="${tval%\"}"
                    tval="${tval#\'}" ; tval="${tval%\'}"
                    YAML_VALUES["tmux_window_${tmux_owner}_${tkey}"]="$tval"
                fi
                continue
            fi

            # Pane list items
            if [[ "$in_panes" == true && -n "$window_name" ]]; then
                # New pane starts with "- type: ..."
                if [[ "$line" =~ ^-[[:space:]]*type:[[:space:]]*(.+)$ ]]; then
                    ((pane_index++)) || true
                    YAML_VALUES["window_${window_name}_pane_${pane_index}_type"]="${BASH_REMATCH[1]}"
                # Continuation property of current pane
                elif [[ $pane_index -ge 0 && "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
                    YAML_VALUES["window_${window_name}_pane_${pane_index}_${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
                fi
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
        ((count++)) || true
    done
    echo "$count"
}

# --- tmux option accessors ---

# Get a top-level tmux global option value
yaml_get_tmux_global() {
    local option="$1"
    echo "${YAML_VALUES["tmux_global_${option}"]:-}"
}

# Get a top-level tmux session option value
yaml_get_tmux_session() {
    local option="$1"
    echo "${YAML_VALUES["tmux_session_${option}"]:-}"
}

# Get a subsession-level tmux option value
yaml_get_tmux_subsession() {
    local subsession="$1" option="$2"
    echo "${YAML_VALUES["tmux_subsession_${subsession}_${option}"]:-}"
}

# Get a window-level tmux option value
yaml_get_tmux_window() {
    local window="$1" option="$2"
    echo "${YAML_VALUES["tmux_window_${window}_${option}"]:-}"
}

# List all tmux global option keys
yaml_list_tmux_global_keys() {
    printf '%s\n' "${YAML_TMUX_GLOBAL_KEYS[@]}"
}

# List all tmux session option keys
yaml_list_tmux_session_keys() {
    printf '%s\n' "${YAML_TMUX_SESSION_KEYS[@]}"
}

# List all tmux option keys for a specific subsession
yaml_list_tmux_subsession_keys() {
    local subsession="$1"
    local prefix="tmux_subsession_${subsession}_"
    for key in "${!YAML_VALUES[@]}"; do
        if [[ "$key" == ${prefix}* ]]; then
            echo "${key#${prefix}}"
        fi
    done
}

# List all tmux option keys for a specific window
yaml_list_tmux_window_keys() {
    local window="$1"
    local prefix="tmux_window_${window}_"
    for key in "${!YAML_VALUES[@]}"; do
        if [[ "$key" == ${prefix}* ]]; then
            echo "${key#${prefix}}"
        fi
    done
}

# Debug: dump all parsed values
yaml_dump() {
    echo "=== Parsed YAML ==="
    echo "Top-level:"
    for key in "${!YAML_VALUES[@]}"; do
        [[ "$key" != subsession_* && "$key" != window_* && "$key" != tmux_* ]] && echo "  $key = ${YAML_VALUES[$key]}"
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
    echo "Tmux global options:"
    for tkey in "${YAML_TMUX_GLOBAL_KEYS[@]}"; do
        echo "  $tkey = ${YAML_VALUES["tmux_global_${tkey}"]}"
    done
    echo "Tmux session options:"
    for tkey in "${YAML_TMUX_SESSION_KEYS[@]}"; do
        echo "  $tkey = ${YAML_VALUES["tmux_session_${tkey}"]}"
    done
    for sub in "${YAML_SUBSECTIONS[@]}"; do
        local keys
        keys=$(yaml_list_tmux_subsession_keys "$sub")
        if [[ -n "$keys" ]]; then
            echo "Tmux subsession '$sub' options:"
            while IFS= read -r tkey; do
                echo "  $tkey = $(yaml_get_tmux_subsession "$sub" "$tkey")"
            done <<< "$keys"
        fi
    done
    for win in "${YAML_WINDOWS[@]}"; do
        local keys
        keys=$(yaml_list_tmux_window_keys "$win")
        if [[ -n "$keys" ]]; then
            echo "Tmux window '$win' options:"
            while IFS= read -r tkey; do
                echo "  $tkey = $(yaml_get_tmux_window "$win" "$tkey")"
            done <<< "$keys"
        fi
    done
}
