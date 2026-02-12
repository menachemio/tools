#!/usr/bin/env bash
# Cleanup module — System logs, journals, APT, pip, package caches

clean_system_logs() {
    log_info "Checking system logs and journals..."

    # systemd journal
    if command -v journalctl &>/dev/null; then
        log_info "Cleaning systemd journals to 100MB..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry "journalctl --vacuum-size=100M --vacuum-time=${CLEANUP_LOG_RETENTION_DAYS}d"
        else
            journalctl --vacuum-size=100M 2>/dev/null || true
            journalctl --vacuum-time="${CLEANUP_LOG_RETENTION_DAYS}d" 2>/dev/null || true
        fi
        log_success "Cleaned systemd journals"
    fi

    # APT cache
    if command -v apt-get &>/dev/null; then
        log_info "Cleaning APT cache and logs..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry "apt-get clean && apt-get autoremove -y"
        else
            apt-get clean 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            [[ -d /var/log/apt ]] && find /var/log/apt -name "*.log.*" -delete 2>/dev/null || true
        fi
        log_success "Cleaned APT cache and logs"
    fi

    # Rotated logs
    if [[ -d /var/log ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            local rotated
            rotated=$(find /var/log \( -name "*.gz" -o -name "*.old" -o -regex ".*\.[1-9]$" \) 2>/dev/null | wc -l)
            log_dry "remove $rotated rotated log files from /var/log"
        else
            find /var/log -name "*.gz" -delete 2>/dev/null || true
            find /var/log -name "*.old" -delete 2>/dev/null || true
            find /var/log -regex ".*\.[1-9]$" -delete 2>/dev/null || true
        fi

        # Very large logs
        local LARGE_LOGS
        LARGE_LOGS=$(find /var/log -name "*.log" -size +500M 2>/dev/null || true)
        if [[ -n "$LARGE_LOGS" ]]; then
            local count
            count=$(echo "$LARGE_LOGS" | wc -l)
            if confirm_action "Found $count very large log files (>500MB). Truncate to 50MB?"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_dry "truncate $count log files to 50MB"
                else
                    echo "$LARGE_LOGS" | xargs -I {} truncate -s 50M {} 2>/dev/null || true
                fi
            fi
        fi
        log_success "Cleaned system logs"
    fi
}

clean_package_caches() {
    log_info "Checking package manager caches..."

    # pip
    if command -v pip &>/dev/null; then
        local PIP_CACHE="$HOME/.cache/pip"
        if [[ -d "$PIP_CACHE" ]]; then
            local SIZE
            SIZE=$(get_size "$PIP_CACHE")
            log_info "pip cache is using: $SIZE"
            if confirm_action "Clear pip cache?"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_dry "pip cache purge"
                else
                    pip cache purge 2>/dev/null || rm -rf "$PIP_CACHE"/*
                fi
                log_success "Cleared pip cache"
            fi
        fi
    fi
}

clean_temp_files() {
    log_info "Checking temporary files..."

    local TMP_SIZE
    TMP_SIZE=$(get_size "/tmp")
    log_info "/tmp is using: $TMP_SIZE (clears on reboot — skipping)"

    local USER_CACHE="$HOME/.cache"
    if [[ -d "$USER_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$USER_CACHE")
        log_info "User cache is using: $SIZE"

        for CACHE_DIR in "$USER_CACHE"/*; do
            [[ -d "$CACHE_DIR" ]] || continue
            local DIRNAME
            DIRNAME=$(basename "$CACHE_DIR")
            case "$DIRNAME" in
                thumbnails|trash|*-old|*-backup)
                    local CSIZE
                    CSIZE=$(get_size "$CACHE_DIR")
                    if [[ "$CSIZE" != "0" ]]; then
                        log_info "Found $DIRNAME cache: $CSIZE"
                        if confirm_action "Remove $DIRNAME cache?"; then
                            safe_rm "$CACHE_DIR" "$DIRNAME cache"
                            log_success "Removed $DIRNAME cache"
                        fi
                    fi
                    ;;
            esac
        done
    fi
}

clean_user_logs() {
    log_info "Checking user log files..."
    local USER_LOGS="$HOME/.local/share"
    if [[ -d "$USER_LOGS" ]]; then
        while IFS= read -r logfile; do
            local SIZE
            SIZE=$(get_size "$logfile")
            log_info "Large log file: $logfile ($SIZE)"
            if confirm_action "Truncate this log file?"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_dry "truncate $logfile"
                else
                    > "$logfile"
                fi
                log_success "Truncated log file"
            fi
        done < <(find "$USER_LOGS" -name "*.log" -size +100M 2>/dev/null)
    fi
}
