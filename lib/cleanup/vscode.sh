#!/usr/bin/env bash
# Cleanup module — VS Code Server

clean_vscode_server() {
    log_info "Checking VS Code Server files..."

    local VSCODE_DIR="$HOME/.vscode-server"
    [[ -d "$VSCODE_DIR" ]] || { log_info "VS Code Server directory not found"; return 0; }

    local SIZE
    SIZE=$(get_size "$VSCODE_DIR")
    log_info "VS Code Server is using: $SIZE"

    # Remove old extension versions (keep latest of each)
    if [[ -d "$VSCODE_DIR/extensions" ]]; then
        log_info "Cleaning old extension versions..."
        local OLD_EXTENSIONS=""
        for ext_base in $(ls "$VSCODE_DIR/extensions" 2>/dev/null | sed -E 's/-[0-9]+\.[0-9]+.*//' | sort -u); do
            local versions
            mapfile -t versions < <(ls -d "$VSCODE_DIR/extensions/$ext_base"* 2>/dev/null | sort -V)
            if [[ ${#versions[@]} -gt 1 ]]; then
                for ((i=0; i<${#versions[@]}-1; i++)); do
                    OLD_EXTENSIONS+="${versions[$i]}\n"
                done
            fi
        done

        if [[ -n "$OLD_EXTENSIONS" ]]; then
            local count
            count=$(echo -e "$OLD_EXTENSIONS" | grep -c "^/" || true)
            log_info "Removing $count old extension versions"
            while IFS= read -r ext_dir; do
                if [[ -n "$ext_dir" && -d "$ext_dir" ]]; then
                    safe_rm "$ext_dir" "old extension: $(basename "$ext_dir")"
                fi
            done < <(echo -e "$OLD_EXTENSIONS")
        fi
    fi

    # CLI folder
    if [[ -d "$VSCODE_DIR/cli" ]]; then
        local CLI_SIZE
        CLI_SIZE=$(get_size "$VSCODE_DIR/cli")
        [[ "$CLI_SIZE" != "0" ]] && { log_info "Removing VS Code CLI folder: $CLI_SIZE"; safe_rm "$VSCODE_DIR/cli"; }
    fi

    # Old code installations
    local OLD_SERVERS
    OLD_SERVERS=$(find "$VSCODE_DIR" -maxdepth 1 -name "code-*" -type d 2>/dev/null || true)
    if [[ -n "$OLD_SERVERS" ]]; then
        local count
        count=$(echo "$OLD_SERVERS" | wc -l)
        log_info "Removing $count old server installation(s)"
        while IFS= read -r srv; do
            safe_rm "$srv" "old server: $(basename "$srv")"
        done <<< "$OLD_SERVERS"
    fi

    # Cached data (safe)
    if [[ -d "$VSCODE_DIR/data" ]]; then
        for cache_dir in CachedData CachedExtensionVSIXs; do
            if [[ -d "$VSCODE_DIR/data/$cache_dir" ]]; then
                local CS
                CS=$(get_size "$VSCODE_DIR/data/$cache_dir")
                if [[ "$CS" != "0" ]]; then
                    log_info "Clearing VS Code $cache_dir: $CS"
                    safe_rm "$VSCODE_DIR/data/$cache_dir"
                    [[ "$DRY_RUN" != "true" ]] && mkdir -p "$VSCODE_DIR/data/$cache_dir"
                fi
            fi
        done

        # Old logs
        if [[ -d "$VSCODE_DIR/data/logs" ]]; then
            local OLD_LOGS
            OLD_LOGS=$(find "$VSCODE_DIR/data/logs" -maxdepth 1 -type d -mtime +"$CLEANUP_LOG_RETENTION_DAYS" 2>/dev/null || true)
            if [[ -n "$OLD_LOGS" ]]; then
                local count
                count=$(echo "$OLD_LOGS" | wc -l)
                log_info "Removing $count old VS Code log folders"
                while IFS= read -r d; do
                    safe_rm "$d"
                done <<< "$OLD_LOGS"
            fi
        fi

        # Old workspace storage
        if [[ -d "$VSCODE_DIR/data/User/workspaceStorage" ]]; then
            local OLD_WS
            OLD_WS=$(find "$VSCODE_DIR/data/User/workspaceStorage" -maxdepth 1 -type d -mtime +"$CLEANUP_BACKUP_RETENTION_DAYS" 2>/dev/null || true)
            if [[ -n "$OLD_WS" ]]; then
                local count
                count=$(echo "$OLD_WS" | wc -l)
                log_info "Removing $count old workspace folders >$CLEANUP_BACKUP_RETENTION_DAYS days"
                while IFS= read -r d; do
                    safe_rm "$d"
                done <<< "$OLD_WS"
            fi
        fi

        # User caches
        if [[ -d "$VSCODE_DIR/data/User" ]]; then
            for cache_subdir in "caches/workbench" "caches/chromium"; do
                if [[ -d "$VSCODE_DIR/data/User/$cache_subdir" ]]; then
                    local CS
                    CS=$(get_size "$VSCODE_DIR/data/User/$cache_subdir")
                    if [[ "$CS" != "0" ]]; then
                        log_info "Clearing VS Code $cache_subdir: $CS"
                        safe_rm "$VSCODE_DIR/data/User/$cache_subdir"
                        [[ "$DRY_RUN" != "true" ]] && mkdir -p "$VSCODE_DIR/data/User/$cache_subdir"
                    fi
                fi
            done

            # Old history (confirm)
            if [[ -d "$VSCODE_DIR/data/User/History" ]]; then
                local OLD_HISTORY
                OLD_HISTORY=$(find "$VSCODE_DIR/data/User/History" -maxdepth 1 -type d -mtime +"$CLEANUP_BACKUP_RETENTION_DAYS" 2>/dev/null || true)
                if [[ -n "$OLD_HISTORY" ]]; then
                    local count
                    count=$(echo "$OLD_HISTORY" | wc -l)
                    if confirm_action "Remove $count old VS Code history folders?"; then
                        while IFS= read -r d; do
                            safe_rm "$d"
                        done <<< "$OLD_HISTORY"
                    fi
                fi
            fi

            # Old backups (confirm)
            if [[ -d "$VSCODE_DIR/data/User/Backups" ]]; then
                local OLD_BACKUPS
                OLD_BACKUPS=$(find "$VSCODE_DIR/data/User/Backups" -maxdepth 1 -type d -mtime +"$CLEANUP_BACKUP_RETENTION_DAYS" 2>/dev/null || true)
                if [[ -n "$OLD_BACKUPS" ]]; then
                    local count
                    count=$(echo "$OLD_BACKUPS" | wc -l)
                    if confirm_action "Remove $count old VS Code backups older than $CLEANUP_BACKUP_RETENTION_DAYS days?"; then
                        while IFS= read -r d; do
                            safe_rm "$d"
                        done <<< "$OLD_BACKUPS"
                    fi
                fi
            fi
        fi
    fi

    # Bin folder
    if [[ -d "$VSCODE_DIR/bin" ]]; then
        local BIN_SIZE
        BIN_SIZE=$(get_size "$VSCODE_DIR/bin")
        if [[ "$BIN_SIZE" != "0" ]]; then
            log_info "Clearing VS Code bin folder: $BIN_SIZE"
            safe_rm "$VSCODE_DIR/bin"
            [[ "$DRY_RUN" != "true" ]] && mkdir -p "$VSCODE_DIR/bin"
        fi
    fi

    # Obsolete markers
    [[ "$DRY_RUN" != "true" ]] && find "$VSCODE_DIR" -name ".obsolete" -delete 2>/dev/null || true
}
