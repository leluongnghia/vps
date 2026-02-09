#!/bin/bash

# core/nginx_helpers.sh - Nginx Configuration Helpers

# Backup Nginx config before modification
backup_nginx_config() {
    local conf=$1
    if [ -f "$conf" ]; then
        local backup="${conf}.bak_$(date +%s)"
        cp "$conf" "$backup"
        echo "$backup"  # Return backup path
    fi
}

# Restore Nginx config from backup
restore_nginx_config() {
    local backup=$1
    local original="${backup%.bak_*}"
    if [ -f "$backup" ]; then
        mv "$backup" "$original"
        log_info "Restored Nginx config from backup"
    fi
}

# Safe Nginx config modification with auto-rollback
safe_nginx_modify() {
    local conf=$1
    local modification_function=$2
    
    # Backup
    local backup=$(backup_nginx_config "$conf")
    
    # Apply modification
    $modification_function "$conf"
    
    # Test
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        rm -f "$backup"  # Remove backup if successful
        return 0
    else
        log_error "Nginx config test failed! Rolling back..."
        restore_nginx_config "$backup"
        nginx -t  # Show error
        return 1
    fi
}

# Apply Nginx snippet to site (Helper to reduce code duplication)
apply_nginx_snippet() {
    local domain=$1
    local snippet_path=$2
    local snippet_name=$(basename "$snippet_path")
    local conf="/etc/nginx/sites-available/$domain"
    
    if [ ! -f "$conf" ]; then
        log_error "Nginx config not found for $domain"
        return 1
    fi
    
    # Check if already applied
    if grep -q "$snippet_name" "$conf"; then
        log_warn "Snippet already applied to $domain"
        return 0
    fi
    
    # Backup and apply
    local backup=$(backup_nginx_config "$conf")
    
    # Insert include after server_name
    sed -i "/server_name/a \    include $snippet_path;" "$conf"
    
    # Test
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        rm -f "$backup"
        log_info "Applied $snippet_name to $domain"
        return 0
    else
        log_error "Nginx test failed! Restoring backup..."
        restore_nginx_config "$backup"
        return 1
    fi
}
