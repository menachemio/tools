#!/usr/bin/env bash
# Cleanup module — Node.js / NPM / pnpm caches and orphaned node_modules

clean_npm_cache() {
    log_info "Checking NPM cache..."

    local NPM_CACHE="$HOME/.npm"
    if [[ -d "$NPM_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$NPM_CACHE")
        log_info "NPM cache is using: $SIZE"
        if confirm_action "Clear NPM cache?"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_dry "npm cache clean --force"
            else
                npm cache clean --force 2>/dev/null || true
            fi
            log_success "Cleared NPM cache"
        fi
    fi

    local PNPM_CACHE="$HOME/.pnpm-store"
    if [[ -d "$PNPM_CACHE" ]]; then
        local SIZE
        SIZE=$(get_size "$PNPM_CACHE")
        log_info "pnpm cache is using: $SIZE"
        if confirm_action "Clear pnpm cache?"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_dry "pnpm store prune"
            else
                pnpm store prune 2>/dev/null || safe_rm "$PNPM_CACHE"
            fi
            log_success "Cleared pnpm cache"
        fi
    fi
}

clean_build_artifacts() {
    log_info "Checking for Next.js build artifacts..."

    # Skip in auto mode — build caches hurt dev velocity if removed unexpectedly
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Skipping build artifacts in auto mode"
        return 0
    fi

    # .next/ directories
    local next_dirs
    next_dirs=$(find "$HOME" -maxdepth 4 -type d -name ".next" -not -path "*/node_modules/*" 2>/dev/null || true)
    if [[ -n "$next_dirs" ]]; then
        local count
        count=$(echo "$next_dirs" | wc -l)
        log_info "Found $count .next/ build directories"
        while IFS= read -r d; do
            local SIZE
            SIZE=$(get_size "$d")
            echo "  $SIZE - $d"
        done <<< "$next_dirs"

        if confirm_action "Remove .next/ build directories?"; then
            while IFS= read -r d; do
                safe_rm "$d" ".next build: $d"
            done <<< "$next_dirs"
            log_success "Removed .next/ build directories"
        fi
    fi

    # .open-next/ directories
    local open_next_dirs
    open_next_dirs=$(find "$HOME" -maxdepth 4 -type d -name ".open-next" -not -path "*/node_modules/*" 2>/dev/null || true)
    if [[ -n "$open_next_dirs" ]]; then
        local count
        count=$(echo "$open_next_dirs" | wc -l)
        log_info "Found $count .open-next/ build directories"
        while IFS= read -r d; do
            local SIZE
            SIZE=$(get_size "$d")
            echo "  $SIZE - $d"
        done <<< "$open_next_dirs"

        if confirm_action "Remove .open-next/ build directories?"; then
            while IFS= read -r d; do
                safe_rm "$d" ".open-next build: $d"
            done <<< "$open_next_dirs"
            log_success "Removed .open-next/ build directories"
        fi
    fi

    if [[ -z "$next_dirs" && -z "$open_next_dirs" ]]; then
        log_info "No Next.js build artifacts found"
    fi
}

clean_orphaned_node_modules() {
    log_info "Checking for orphaned node_modules directories..."

    # Home-root node_modules (common mistake)
    if [[ -d "$HOME/node_modules" && ! -f "$HOME/package.json" ]]; then
        local SIZE
        SIZE=$(get_size "$HOME/node_modules")
        log_warning "Found node_modules in \$HOME root without package.json ($SIZE)"
        if confirm_action "Remove \$HOME/node_modules?"; then
            safe_rm "$HOME/node_modules"
            log_success "Removed \$HOME/node_modules"
        fi
    fi

    local tmp_orphans
    tmp_orphans=$(mktemp)

    # Search for orphaned node_modules
    while IFS= read -r nm_dir; do
        local PARENT_DIR
        PARENT_DIR=$(dirname "$nm_dir")
        if [[ ! -f "$PARENT_DIR/package.json" ]]; then
            local GRANDPARENT_DIR
            GRANDPARENT_DIR=$(dirname "$PARENT_DIR")
            if [[ ! -f "$GRANDPARENT_DIR/package.json" ]]; then
                local SIZE
                SIZE=$(get_size "$nm_dir")
                echo "$nm_dir|$SIZE" >> "$tmp_orphans"
            fi
        fi
    done < <(find "$HOME" -maxdepth 5 -type d -name "node_modules" -not -path "*/node_modules/*/node_modules" 2>/dev/null)

    if [[ -s "$tmp_orphans" ]]; then
        local count
        count=$(wc -l < "$tmp_orphans")
        log_info "Found $count potentially orphaned node_modules directories"
        while IFS='|' read -r dir size; do
            echo "  $size - $dir"
        done < "$tmp_orphans"

        if confirm_action "Remove orphaned node_modules directories?"; then
            while IFS='|' read -r dir size; do
                safe_rm "$dir" "orphaned node_modules: $dir ($size)"
            done < "$tmp_orphans"
            log_success "Removed orphaned node_modules"
        fi
    else
        log_info "No orphaned node_modules directories found"
    fi

    rm -f "$tmp_orphans"
}
