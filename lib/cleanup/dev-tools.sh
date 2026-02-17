#!/usr/bin/env bash
# Cleanup module — Development tool artifacts, caches, Docker

clean_cached_installers() {
    log_info "Checking cached installer files and heavy caches..."

    local USER_CACHE="$HOME/.cache"
    [[ -d "$USER_CACHE" ]] || return 0

    # Playwright browsers
    local PLAYWRIGHT_CACHE="$USER_CACHE/ms-playwright"
    if [[ -d "$PLAYWRIGHT_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$PLAYWRIGHT_CACHE")
        if [[ "$SIZE" != "0" ]]; then
            log_info "Found Playwright browsers cache: $SIZE"
            if confirm_action "Remove Playwright cache (browsers re-download as needed)?"; then
                safe_rm "$PLAYWRIGHT_CACHE" "Playwright browser cache"
                mkdir -p "$PLAYWRIGHT_CACHE"
                log_success "Cleared Playwright cache"
            fi
        fi
    fi

    # code-server cache
    local CODE_SERVER_CACHE="$USER_CACHE/code-server"
    if [[ -d "$CODE_SERVER_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$CODE_SERVER_CACHE")
        if [[ "$SIZE" != "0" ]]; then
            log_info "Found code-server cache: $SIZE"
            if confirm_action "Remove code-server cache?"; then
                safe_rm "$CODE_SERVER_CACHE" "code-server cache"
                mkdir -p "$CODE_SERVER_CACHE"
                log_success "Cleared code-server cache"
            fi
        fi
    fi

    # Claude CLI cache (safe — rebuilds automatically)
    local CLAUDE_CACHE="$USER_CACHE/claude"
    if [[ -d "$CLAUDE_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$CLAUDE_CACHE")
        if [[ "$SIZE" != "0" ]]; then
            log_info "Removing Claude cache: $SIZE (rebuilds automatically)"
            safe_rm "$CLAUDE_CACHE" "Claude CLI cache"
            mkdir -p "$CLAUDE_CACHE"
            log_success "Cleared Claude cache"
        fi
    fi

    # TypeScript build cache (safe — rebuilds automatically)
    local TS_CACHE="$USER_CACHE/typescript"
    if [[ -d "$TS_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$TS_CACHE")
        if [[ "$SIZE" != "0" ]]; then
            log_info "Removing TypeScript build cache: $SIZE (rebuilds automatically)"
            safe_rm "$TS_CACHE" "TypeScript build cache"
            mkdir -p "$TS_CACHE"
            log_success "Cleared TypeScript build cache"
        fi
    fi

    # Claude CLI Node cache (safe — redownloads as needed)
    local CLAUDE_NODE_CACHE="$USER_CACHE/claude-cli-nodejs"
    if [[ -d "$CLAUDE_NODE_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$CLAUDE_NODE_CACHE")
        if [[ "$SIZE" != "0" ]]; then
            log_info "Removing Claude CLI Node cache: $SIZE (redownloads as needed)"
            safe_rm "$CLAUDE_NODE_CACHE" "Claude CLI Node cache"
            mkdir -p "$CLAUDE_NODE_CACHE"
            log_success "Cleared Claude CLI Node cache"
        fi
    fi

    # Cached installer packages
    local INSTALLERS
    INSTALLERS=$(find "$USER_CACHE" -type f \( -name "*.deb" -o -name "*.rpm" -o -name "*.AppImage" \) -size +10M 2>/dev/null || true)
    if [[ -n "$INSTALLERS" ]]; then
        local count
        count=$(echo "$INSTALLERS" | wc -l)
        log_info "Removing $count cached installer files"
        while IFS= read -r f; do
            safe_rm "$f" "cached installer: $(basename "$f")"
        done <<< "$INSTALLERS"
        log_success "Removed cached installer files"
    fi

    # Large archive files
    local CACHE_ARCHIVES
    CACHE_ARCHIVES=$(find "$USER_CACHE" -type f \( -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) -size +50M 2>/dev/null || true)
    if [[ -n "$CACHE_ARCHIVES" ]]; then
        local count
        count=$(echo "$CACHE_ARCHIVES" | wc -l)
        log_info "Removing $count large archive files from cache"
        while IFS= read -r f; do
            safe_rm "$f" "cached archive: $(basename "$f")"
        done <<< "$CACHE_ARCHIVES"
        log_success "Removed large cache archives"
    fi

    # Known problematic subdirectories
    for CACHE_SUBDIR in code vscode chromium; do
        local CACHE_PATH="$USER_CACHE/$CACHE_SUBDIR"
        if [[ -d "$CACHE_PATH" ]]; then
            local OLD_PACKAGES
            OLD_PACKAGES=$(find "$CACHE_PATH" -type f \( -name "*.deb" -o -name "*.rpm" -o -name "*.tar.gz" \) 2>/dev/null || true)
            if [[ -n "$OLD_PACKAGES" ]]; then
                local count
                count=$(echo "$OLD_PACKAGES" | wc -l)
                log_info "Removing $count old packages from $CACHE_SUBDIR cache"
                while IFS= read -r f; do
                    safe_rm "$f"
                done <<< "$OLD_PACKAGES"
                log_success "Removed old $CACHE_SUBDIR packages"
            fi
        fi
    done
}

clean_dev_tools() {
    log_info "Checking development tool artifacts..."

    # code-server backup
    local CODE_SERVER_BACKUP="$HOME/.local/share/code-server.backup"
    if [[ -d "$CODE_SERVER_BACKUP" ]]; then
        local SIZE
        SIZE=$(get_size "$CODE_SERVER_BACKUP")
        log_info "Code-server backup is using: $SIZE"
        if confirm_action "Remove code-server backup?"; then
            safe_rm "$CODE_SERVER_BACKUP" "code-server backup"
            log_success "Removed code-server backup"
        fi
    fi

    # Old Claude versions
    local CLAUDE_DIR="$HOME/.local/share/claude/versions"
    if [[ -d "$CLAUDE_DIR" ]]; then
        local LATEST_VERSION
        LATEST_VERSION=$(ls -v "$CLAUDE_DIR" 2>/dev/null | tail -1)
        local OLD_VERSIONS
        OLD_VERSIONS=$(ls -v "$CLAUDE_DIR" 2>/dev/null | head -n -1)
        local TOTAL_VERSIONS
        TOTAL_VERSIONS=$(ls "$CLAUDE_DIR" 2>/dev/null | wc -l)
        if [[ -n "$OLD_VERSIONS" && -n "$LATEST_VERSION" && "$TOTAL_VERSIONS" -gt 1 ]]; then
            log_info "Found old Claude versions (keeping: $LATEST_VERSION)"
            if confirm_action "Remove old Claude versions?"; then
                if [[ -e "$CLAUDE_DIR/$LATEST_VERSION" ]]; then
                    while IFS= read -r v; do
                        if [[ -n "$v" ]]; then
                            safe_rm "$CLAUDE_DIR/$v" "Claude version $v"
                        fi
                    done <<< "$OLD_VERSIONS"
                    log_success "Removed old Claude versions"
                fi
            fi
        fi
    fi

    # Duplicate Next.js binaries
    local NEXT_BINARIES
    NEXT_BINARIES=$(find "$HOME" -path "*/node_modules/@next/swc-*" -name "*.node" -size +100M 2>/dev/null || true)
    if [[ -n "$NEXT_BINARIES" ]]; then
        local KEEP_VARIANT REMOVE_VARIANT
        if ldd /bin/ls 2>/dev/null | grep -q musl; then
            KEEP_VARIANT="musl"; REMOVE_VARIANT="gnu"
        else
            KEEP_VARIANT="gnu"; REMOVE_VARIANT="musl"
        fi
        local REMOVABLE
        REMOVABLE=$(echo "$NEXT_BINARIES" | grep "$REMOVE_VARIANT" || true)
        if [[ -n "$REMOVABLE" ]]; then
            log_info "Found unnecessary Next.js $REMOVE_VARIANT binaries"
            if confirm_action "Remove unnecessary Next.js $REMOVE_VARIANT binaries (keeping $KEEP_VARIANT)?"; then
                while IFS= read -r f; do
                    safe_rm "$f" "Next.js binary: $(basename "$f")"
                done <<< "$REMOVABLE"
                log_success "Removed unnecessary Next.js binaries"
            fi
        fi
    fi

    # Old Volta Node versions
    local VOLTA_DIR="$HOME/.volta/tools/image"
    if [[ -d "$VOLTA_DIR/node" ]]; then
        local VERSION_COUNT
        VERSION_COUNT=$(ls "$VOLTA_DIR/node" 2>/dev/null | wc -l)
        if [[ "$VERSION_COUNT" -gt 1 ]]; then
            local CURRENT_VERSION
            CURRENT_VERSION=$(volta list node 2>/dev/null | grep current | awk '{print $2}' | sed 's/v//' || true)
            [[ -z "$CURRENT_VERSION" && -L "$HOME/.volta/bin/node" ]] && \
                CURRENT_VERSION=$(readlink "$HOME/.volta/bin/node" | grep -oP 'node/\K[^/]+' || true)
            [[ -z "$CURRENT_VERSION" ]] && CURRENT_VERSION=$(ls -v "$VOLTA_DIR/node" | tail -1)

            local OLD_VERSIONS
            OLD_VERSIONS=$(ls -v "$VOLTA_DIR/node" | grep -v "$CURRENT_VERSION" || true)
            if [[ -n "$OLD_VERSIONS" ]]; then
                log_info "Found old Node versions in Volta (active: $CURRENT_VERSION)"
                if confirm_action "Remove old Node versions from Volta?"; then
                    if [[ -d "$VOLTA_DIR/node/$CURRENT_VERSION" ]]; then
                        while IFS= read -r v; do
                            if [[ -n "$v" ]]; then
                                safe_rm "$VOLTA_DIR/node/$v" "Node $v"
                            fi
                        done <<< "$OLD_VERSIONS"
                        log_success "Removed old Node versions"
                    fi
                fi
            fi
        fi
    fi

    # Volta inventory tarballs (re-downloads as needed)
    local VOLTA_INVENTORY="$HOME/.volta/tools/inventory/node"
    if [[ -d "$VOLTA_INVENTORY" ]]; then
        local TARBALLS
        TARBALLS=$(find "$VOLTA_INVENTORY" -maxdepth 1 -name "*.tar.gz" 2>/dev/null || true)
        if [[ -n "$TARBALLS" ]]; then
            local count
            count=$(echo "$TARBALLS" | wc -l)
            local total_size
            total_size=$(echo "$TARBALLS" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
            log_info "Found $count Volta inventory tarballs ($total_size)"
            if confirm_action "Remove Volta inventory tarballs (re-downloads as needed)?"; then
                while IFS= read -r f; do
                    safe_rm "$f" "tarball: $(basename "$f")"
                done <<< "$TARBALLS"
                log_success "Removed Volta inventory tarballs"
            fi
        fi
    fi

    # Old Volta package manager versions
    if [[ -d "$VOLTA_DIR" ]]; then
        for PM in npm yarn pnpm; do
            if [[ -d "$VOLTA_DIR/$PM" ]]; then
                local PM_OLD
                PM_OLD=$(ls -v "$VOLTA_DIR/$PM" 2>/dev/null | head -n -1)
                if [[ -n "$PM_OLD" ]]; then
                    log_info "Found old $PM versions in Volta"
                    if confirm_action "Remove old $PM versions from Volta?"; then
                        while IFS= read -r v; do
                            if [[ -n "$v" ]]; then
                                safe_rm "$VOLTA_DIR/$PM/$v" "$PM $v"
                            fi
                        done <<< "$PM_OLD"
                        log_success "Removed old $PM versions"
                    fi
                fi
            fi
        done
    fi
}

clean_docker() {
    command -v docker &>/dev/null || return 0
    log_info "Checking Docker resources..."
    if confirm_action "Clean Docker unused resources (containers, images, volumes)?"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry "docker system prune -a --volumes -f"
        else
            docker system prune -a --volumes -f 2>/dev/null || true
        fi
        log_success "Cleaned Docker resources"
    fi
}

clean_wrangler() {
    log_info "Checking Cloudflare Wrangler files..."

    # Logs
    local WRANGLER_LOGS="$HOME/.config/.wrangler/logs"
    if [[ -d "$WRANGLER_LOGS" ]]; then
        local LOG_COUNT
        LOG_COUNT=$(find "$WRANGLER_LOGS" -name "*.log" -type f 2>/dev/null | wc -l)
        if [[ "$LOG_COUNT" -gt 0 ]]; then
            local TOTAL_SIZE
            TOTAL_SIZE=$(get_size "$WRANGLER_LOGS")
            log_info "Found $LOG_COUNT Wrangler log files using: $TOTAL_SIZE"

            local OLD_LOGS
            OLD_LOGS=$(find "$WRANGLER_LOGS" -name "*.log" -type f -mtime +"$CLEANUP_LOG_RETENTION_DAYS" 2>/dev/null || true)
            if [[ -n "$OLD_LOGS" ]]; then
                local count
                count=$(echo "$OLD_LOGS" | wc -l)
                if confirm_action "Remove $count Wrangler logs older than $CLEANUP_LOG_RETENTION_DAYS days?"; then
                    while IFS= read -r f; do
                        safe_rm "$f"
                    done <<< "$OLD_LOGS"
                    log_success "Removed old Wrangler logs"
                fi
            fi
        fi
    fi

    # Temp files
    local WRANGLER_TEMP="$HOME/.config/.wrangler/tmp"
    if [[ -d "$WRANGLER_TEMP" ]]; then
        local SIZE
        SIZE=$(get_size "$WRANGLER_TEMP")
        if [[ "$SIZE" != "0" ]]; then
            log_info "Removing Wrangler temp files: $SIZE"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_dry "remove Wrangler temp files ($SIZE)"
            else
                rm -rf "$WRANGLER_TEMP"/* 2>/dev/null || true
            fi
            log_success "Cleared Wrangler temp files"
        fi
    fi
}

clean_neovim_caches() {
    log_info "Checking Neovim caches and backups..."

    local found=false

    # Cache directories
    for cache_dir in "$HOME/.cache/nvim" "$HOME/.cache/nvim-vscode"; do
        if [[ -d "$cache_dir" ]]; then
            local SIZE
            SIZE=$(get_size "$cache_dir")
            if [[ "$SIZE" != "0" ]]; then
                found=true
                log_info "Found Neovim cache: $cache_dir ($SIZE)"
                if confirm_action "Remove $(basename "$cache_dir") cache (rebuilds on launch)?"; then
                    safe_rm "$cache_dir" "$(basename "$cache_dir") cache"
                    log_success "Removed $(basename "$cache_dir") cache"
                fi
            fi
        fi
    done

    # Data backups (~/.local/share/nvim.backup.*)
    local nvim_data_backups
    nvim_data_backups=$(find "$HOME/.local/share" -maxdepth 1 -name "nvim.backup.*" -type d 2>/dev/null || true)
    if [[ -n "$nvim_data_backups" ]]; then
        found=true
        local count
        count=$(echo "$nvim_data_backups" | wc -l)
        log_info "Found $count Neovim data backup(s)"
        if confirm_action "Remove Neovim data backups?"; then
            while IFS= read -r d; do
                safe_rm "$d" "nvim data backup: $(basename "$d")"
            done <<< "$nvim_data_backups"
            log_success "Removed Neovim data backups"
        fi
    fi

    # Config backups (~/.config/nvim.backup.*)
    local nvim_config_backups
    nvim_config_backups=$(find "$HOME/.config" -maxdepth 1 -name "nvim.backup.*" -type d 2>/dev/null || true)
    if [[ -n "$nvim_config_backups" ]]; then
        found=true
        local count
        count=$(echo "$nvim_config_backups" | wc -l)
        log_info "Found $count Neovim config backup(s)"
        if confirm_action "Remove Neovim config backups?"; then
            while IFS= read -r d; do
                safe_rm "$d" "nvim config backup: $(basename "$d")"
            done <<< "$nvim_config_backups"
            log_success "Removed Neovim config backups"
        fi
    fi

    if [[ "$found" == "false" ]]; then
        log_info "No Neovim caches or backups found"
    fi
}

clean_standalone_binaries() {
    log_info "Checking standalone node binaries..."

    local bin_dir="$HOME/.local/share/node-binaries"
    [[ -d "$bin_dir" ]] || return 0

    local SIZE
    SIZE=$(get_size "$bin_dir")
    if [[ "$SIZE" == "0" ]]; then
        log_info "No standalone node binaries found"
        return 0
    fi

    log_info "Found standalone node binaries: $SIZE"

    # Skip in auto mode — removing these can hurt dev velocity
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Skipping standalone binaries in auto mode"
        return 0
    fi

    if confirm_action "Remove standalone node binaries (next-swc, workerd, etc.)?"; then
        safe_rm "$bin_dir" "standalone node binaries"
        log_success "Removed standalone node binaries"
    fi
}
