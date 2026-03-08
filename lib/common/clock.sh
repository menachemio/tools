#!/usr/bin/env bash
# Shared clock/timezone helpers for status-right scripts.
# Source this file; call clock_parse_args "$@" then clock_format.

CLOCK_SHOW_TIME=false
CLOCK_FORMAT="24h"
CLOCK_TIMEZONE=""

# Parse --with-time, --clock-format, --timezone, --timezone-from-config
# from an argument list. Unknown flags are silently skipped.
clock_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with-time)            CLOCK_SHOW_TIME=true;       shift ;;
            --clock-format)         CLOCK_FORMAT="${2:-$CLOCK_FORMAT}"; shift; [[ $# -gt 0 ]] && shift ;;
            --timezone)             CLOCK_TIMEZONE="${2:-$CLOCK_TIMEZONE}"; shift; [[ $# -gt 0 ]] && shift ;;
            --timezone-from-config)
                if [[ -z "$CLOCK_TIMEZONE" && -n "${2:-}" && -f "$2" ]]; then
                    local tz
                    tz=$(sed -n 's/^timezone:\s*//p' "$2" | tr -d '[:space:]')
                    [[ -n "$tz" ]] && CLOCK_TIMEZONE="$tz"
                fi
                shift; [[ $# -gt 0 ]] && shift ;;
            *)  shift ;;
        esac
    done
    CLOCK_TIMEZONE="${CLOCK_TIMEZONE:-UTC}"
}

# Print formatted current time. Returns empty string if --with-time wasn't set.
clock_format() {
    [[ "$CLOCK_SHOW_TIME" != "true" ]] && return

    if [[ "$CLOCK_FORMAT" == "12h" ]]; then
        TZ="$CLOCK_TIMEZONE" date "+%-I:%M %p %Z"
    else
        TZ="$CLOCK_TIMEZONE" date "+%H:%M %Z"
    fi
}

# Append " | <time>" to an output string if --with-time is set.
# Usage: output=$(clock_append "$output")
clock_append() {
    local output="$1"
    local time_str
    time_str=$(clock_format)
    if [[ -n "$time_str" ]]; then
        # Only add pipe separator if there's real content before the clock
        if [[ -n "$output" && "$output" != "»" ]]; then
            echo "${output} | ${time_str}"
        else
            echo "${output} ${time_str}"
        fi
    else
        echo "$output"
    fi
}
