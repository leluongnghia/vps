#!/bin/bash

# core/nginx_helpers.sh - Nginx Configuration Helpers

# Backup Nginx config before modification
backup_nginx_config() {
    local conf=$1
    if [[ -f "$conf" ]]; then
        local backup="${conf}.bak_$(date +%s)"
        cp "$conf" "$backup"
        echo "$backup"  # Return backup path
    fi
}

# Test config rồi reload. Config lỗi -> in lỗi, KHÔNG reload, trả về 1.
nginx_test_reload() {
    local out
    if out=$(nginx -t 2>&1); then
        systemctl reload nginx 2>/dev/null || systemctl restart nginx
        return $?
    fi
    log_error "Nginx config có lỗi - chưa reload:"
    echo "$out" | tail -8
    return 1
}

# Chốt 1 lần sửa vhost: test OK -> reload + xoá backup; lỗi -> khôi phục backup, trả về 1.
# Dùng:
#   local bak; bak=$(backup_nginx_config "$conf")
#   sed -i ... "$conf"
#   nginx_commit "$conf" "$bak" || return 1
# Nếu $bak rỗng (file vừa được tạo mới) thì khi lỗi file sẽ bị gỡ khỏi sites-enabled.
nginx_commit() {
    local conf=$1 backup=${2:-}
    local out
    if out=$(nginx -t 2>&1); then
        systemctl reload nginx 2>/dev/null || systemctl restart nginx
        [[ -n "$backup" ]] && rm -f "$backup"
        return 0
    fi
    log_error "Nginx config có lỗi sau khi sửa $(basename "$conf") - đang hoàn tác:"
    echo "$out" | tail -8
    if [[ -n "$backup" && -f "$backup" ]]; then
        mv -f "$backup" "$conf"
        log_warn "Đã khôi phục $(basename "$conf") về bản trước khi sửa."
    else
        rm -f "/etc/nginx/sites-enabled/$(basename "$conf")"
        log_warn "Đã gỡ $(basename "$conf") khỏi sites-enabled (file mới bị lỗi, giữ lại trong sites-available để kiểm tra)."
    fi
    return 1
}

# Thêm 1 dòng include vào server block của vhost (idempotent, có rollback).
# Dùng: nginx_add_include <conf> <đường dẫn snippet>
nginx_add_include() {
    local conf=$1 snippet=$2
    [[ -f "$conf" ]] || { log_error "Không tìm thấy vhost: $conf"; return 1; }
    [[ -f "$snippet" ]] || { log_error "Không tìm thấy snippet: $snippet"; return 1; }
    grep -qF "include $snippet;" "$conf" && return 0
    local bak
    bak=$(backup_nginx_config "$conf")
    sed -i "/server_name/a \    include $snippet;" "$conf"
    nginx_commit "$conf" "$bak"
}

# Gỡ dòng include khỏi vhost (có rollback)
nginx_remove_include() {
    local conf=$1 snippet=$2
    [[ -f "$conf" ]] || return 1
    grep -qF "$snippet" "$conf" || return 0
    local bak pat
    bak=$(backup_nginx_config "$conf")
    pat=$(printf '%s' "$snippet" | sed -e 's/[][\\.*^$/|]/\\&/g')
    sed -i "\|include[[:space:]]\+${pat};|d" "$conf"
    nginx_commit "$conf" "$bak"
}

