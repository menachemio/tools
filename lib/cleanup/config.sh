#!/usr/bin/env bash
# Cleanup utility — YAML configuration loader
# Uses the shared yaml-parser from lib/common/

CLEANUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CLEANUP_LIB_DIR/../common/yaml-parser.sh"

# Defaults (overridden by YAML config)
declare -g CLEANUP_LOG_RETENTION_DAYS=7
declare -g CLEANUP_BACKUP_RETENTION_DAYS=30
declare -g -a CLEANUP_PROTECTED_DIRS=()
declare -g -a CLEANUP_PROTECTED_PATTERNS=()
declare -g -A CLEANUP_TARGETS=()
declare -g -a CLEANUP_CUSTOM_COMMANDS=()

# Load a cleanup YAML config file.
# Populates globals above from the parsed values.
load_cleanup_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_warning "Config file not found: $config_file (using defaults)"
        return 0
    fi

    if ! parse_yaml "$config_file"; then
        log_error "Failed to parse config: $config_file"
        return 1
    fi

    # General settings
    local val
    val=$(yaml_get "log_retention_days")
    [[ -n "$val" ]] && CLEANUP_LOG_RETENTION_DAYS="$val"

    val=$(yaml_get "backup_retention_days")
    [[ -n "$val" ]] && CLEANUP_BACKUP_RETENTION_DAYS="$val"

    # Target toggles (vscode, nodejs, docker, system, wrangler, dev_tools)
    for target in vscode nodejs docker system wrangler dev_tools; do
        val=$(yaml_get "${target}_enabled")
        if [[ -n "$val" ]]; then
            CLEANUP_TARGETS["$target"]="$val"
        else
            CLEANUP_TARGETS["$target"]="true"  # enabled by default
        fi
    done

    log_info "Loaded cleanup config from $config_file"
}

# Check if a cleanup target is enabled.
target_enabled() {
    local target="$1"
    local val="${CLEANUP_TARGETS[$target]:-true}"
    [[ "$val" == "true" ]]
}

# Initialize defaults (no config file).
init_cleanup_defaults() {
    for target in vscode nodejs docker system wrangler dev_tools; do
        CLEANUP_TARGETS["$target"]="true"
    done
}
