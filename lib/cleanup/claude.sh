#!/usr/bin/env bash
# Cleanup module — Claude Code session data (~/.claude/)

# Protected paths that must never be deleted
readonly -a _CLAUDE_PROTECTED=(
    "CLAUDE.md"
    "settings.json"
    "settings.local.json"
    ".credentials.json"
    "history.jsonl"
    "plugins"
    "cache"
)

# Check if a filename is protected
_claude_is_protected() {
    local name="$1"
    local p
    for p in "${_CLAUDE_PROTECTED[@]}"; do
        [[ "$name" == "$p" ]] && return 0
    done
    return 1
}

# Clean old session files from ~/.claude/projects/
_clean_claude_projects() {
    local projects_dir="$HOME/.claude/projects"
    [[ -d "$projects_dir" ]] || return 0

    local retention="${CLEANUP_SESSION_RETENTION_DAYS:-14}"
    local removed=0

    log_info "Checking Claude project sessions (retention: ${retention}d)..."

    # Iterate each project directory
    local project_dir
    while IFS= read -r project_dir; do
        [[ -d "$project_dir" ]] || continue

        # Find old .jsonl session files (not history.jsonl)
        local old_session
        while IFS= read -r old_session; do
            [[ -z "$old_session" ]] && continue
            local basename_file
            basename_file=$(basename "$old_session")

            # Skip protected files
            _claude_is_protected "$basename_file" && continue

            # Extract UUID from filename (strip .jsonl extension)
            local uuid="${basename_file%.jsonl}"

            safe_rm "$old_session" "session $basename_file from $(basename "$project_dir")"
            ((removed++)) || true

            # Remove sibling session directory with same UUID if it exists
            if [[ -d "$project_dir/$uuid" ]]; then
                safe_rm "$project_dir/$uuid" "session dir $uuid"
                ((removed++)) || true
            fi
        done < <(find "$project_dir" -maxdepth 1 -name "*.jsonl" -not -name "history.jsonl" -mtime +"$retention" 2>/dev/null)
    done < <(find "$projects_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

    if [[ "$removed" -gt 0 ]]; then
        log_success "Cleaned $removed old Claude session files/dirs"
    else
        log_info "No old Claude project sessions found"
    fi
}

# Clean old debug logs from ~/.claude/debug/
_clean_claude_debug() {
    local debug_dir="$HOME/.claude/debug"
    [[ -d "$debug_dir" ]] || return 0

    local retention="${CLEANUP_LOG_RETENTION_DAYS:-7}"
    local old_files
    old_files=$(find "$debug_dir" -maxdepth 1 -type f -mtime +"$retention" 2>/dev/null || true)
    [[ -z "$old_files" ]] && return 0

    local count
    count=$(echo "$old_files" | wc -l)
    local total_size
    total_size=$(get_size "$debug_dir")

    log_info "Found $count old Claude debug logs ($total_size total dir)"
    while IFS= read -r f; do
        safe_rm "$f" "debug log: $(basename "$f")"
    done <<< "$old_files"
    log_success "Cleaned old Claude debug logs"
}

# Clean old file-history session dirs from ~/.claude/file-history/
_clean_claude_file_history() {
    local fh_dir="$HOME/.claude/file-history"
    [[ -d "$fh_dir" ]] || return 0

    local retention="${CLEANUP_SESSION_RETENTION_DAYS:-14}"
    local removed=0

    local session_dir
    while IFS= read -r session_dir; do
        [[ -d "$session_dir" ]] || continue

        # Only remove if ALL files inside are past retention
        local recent_count
        recent_count=$(find "$session_dir" -maxdepth 2 -type f -mtime -"$retention" 2>/dev/null | head -1 | wc -l || true)
        if [[ "$recent_count" -eq 0 ]]; then
            safe_rm "$session_dir" "file-history session: $(basename "$session_dir")"
            ((removed++)) || true
        fi
    done < <(find "$fh_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

    if [[ "$removed" -gt 0 ]]; then
        log_success "Cleaned $removed old Claude file-history sessions"
    fi
}

# Clean generic retention dirs (todos, tasks, session-env, shell-snapshots)
_clean_claude_retention_dirs() {
    local retention="${CLEANUP_SESSION_RETENTION_DAYS:-14}"

    local dir_name
    for dir_name in todos tasks session-env shell-snapshots; do
        local target_dir="$HOME/.claude/$dir_name"
        [[ -d "$target_dir" ]] || continue

        local old_files
        old_files=$(find "$target_dir" -maxdepth 1 -type f -mtime +"$retention" 2>/dev/null || true)
        [[ -z "$old_files" ]] && continue

        local count
        count=$(echo "$old_files" | wc -l)
        log_info "Found $count old files in Claude $dir_name"
        while IFS= read -r f; do
            safe_rm "$f" "$dir_name/$(basename "$f")"
        done <<< "$old_files"
        log_success "Cleaned old Claude $dir_name files"
    done
}

# Main orchestrator
clean_claude_sessions() {
    local claude_dir="$HOME/.claude"
    if [[ ! -d "$claude_dir" ]]; then
        log_info "No Claude data directory found"
        return 0
    fi

    local total_size
    total_size=$(get_size "$claude_dir")
    log_info "Claude data directory: $total_size"

    _clean_claude_projects
    _clean_claude_debug
    _clean_claude_file_history
    _clean_claude_retention_dirs
}
