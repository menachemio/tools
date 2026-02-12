#!/usr/bin/env bash
# Cleanup module — System and tool updates (apt, snap, flatpak, npm globals)

run_system_updates() {
    log_info "Running system updates..."

    # APT
    if command -v apt-get &>/dev/null; then
        log_info "Updating APT packages..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry "apt-get update && apt-get upgrade -y"
        else
            apt-get update -qq 2>/dev/null || true
            if confirm_action "Upgrade APT packages?"; then
                apt-get upgrade -y 2>/dev/null || log_warning "APT upgrade had issues"
                apt-get autoremove -y 2>/dev/null || true
                log_success "APT packages updated"
            fi
        fi
    fi

    # Snap
    if command -v snap &>/dev/null; then
        log_info "Checking snap packages..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry "snap refresh"
        else
            if confirm_action "Refresh snap packages?"; then
                snap refresh 2>/dev/null || log_warning "Snap refresh had issues"
                log_success "Snap packages refreshed"
            fi
        fi
    fi

    # Flatpak
    if command -v flatpak &>/dev/null; then
        log_info "Checking flatpak packages..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry "flatpak update -y"
        else
            if confirm_action "Update flatpak packages?"; then
                flatpak update -y 2>/dev/null || log_warning "Flatpak update had issues"
                log_success "Flatpak packages updated"
            fi
        fi
    fi

    # npm globals
    if command -v npm &>/dev/null; then
        log_info "Checking npm global packages..."
        local outdated
        outdated=$(npm outdated -g --parseable 2>/dev/null | wc -l)
        if [[ "$outdated" -gt 0 ]]; then
            log_info "Found $outdated outdated global npm packages"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_dry "npm update -g"
            else
                if confirm_action "Update $outdated global npm packages?"; then
                    npm update -g 2>/dev/null || log_warning "npm global update had issues"
                    log_success "npm global packages updated"
                fi
            fi
        else
            log_info "All global npm packages are up to date"
        fi
    fi

    # Volta tools
    if command -v volta &>/dev/null; then
        log_info "Volta is installed — managed tools update via 'volta install <tool>@latest'"
        log_info "  Skipping automatic Volta updates (pin-based management)"
    fi
}
