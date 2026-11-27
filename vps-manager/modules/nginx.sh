#!/bin/bash

# modules/nginx.sh - Nginx Management & Installation

# ==============================================================================
# INSTALL NGINX STACK
# ==============================================================================

install_nginx_stack_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🌐 Cài đặt LEMP Stack (Nginx)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Stack bao gồm:"
    echo -e "  • Nginx (Web Server hiệu năng cao)"
    echo -e "  • MariaDB (Cơ sở dữ liệu)"
    echo -e "  • PHP-FPM (Xử lý PHP)"
    echo -e "  • phpMyAdmin (Quản lý database)"
    echo -e "  • Valkey/Redis (Object Cache - tuỳ chọn)"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. 🚀 Cài đặt Full Stack (Khuyên dùng)"
    echo -e "2. 🌐 Chỉ cài Nginx"
    echo -e "3. 🗄️  Chỉ cài MariaDB"
    echo -e "4. 🐘 Chỉ cài PHP"
    echo -e "5. 🔧 Fix PHP Extensions (DOM/XML/MBSTRING)"
    echo -e "0. ↩ Quay lại"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Chọn [0-5]: " choice

    case $choice in
        1) _nginx_full_install ;;
        2) source "$(dirname "${BASH_SOURCE[0]}")/lemp.sh"; install_nginx; pause ;;
        3) source "$(dirname "${BASH_SOURCE[0]}")/lemp.sh"; install_mariadb; pause ;;
        4) source "$(dirname "${BASH_SOURCE[0]}")/lemp.sh"; install_php; pause ;;
        5) source "$(dirname "${BASH_SOURCE[0]}")/lemp.sh"; fix_php_extensions; pause ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

_nginx_full_install() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}  🚀 Cài đặt Full LEMP Stack (Nginx)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "  • Nginx + MariaDB + PHP + phpMyAdmin"
    echo -e ""
    read -p "Bắt đầu cài đặt? [Y/n]: " confirm
    [[ "${confirm,,}" == "n" ]] && return

    source "$(dirname "${BASH_SOURCE[0]}")/lemp.sh"

    log_info "[1/4] Cài đặt Nginx..."
    install_nginx

    log_info "[2/4] Cài đặt MariaDB..."
    install_mariadb

    log_info "[3/4] Cài đặt PHP..."
    install_php

    log_info "[4/4] Cài đặt phpMyAdmin..."
    if [[ -f "$ROOT_DIR/modules/phpmyadmin.sh" ]]; then
        source "$ROOT_DIR/modules/phpmyadmin.sh"
        install_phpmyadmin
    fi

    # (nginx.conf đã được tối ưu/bảo mật ngay trong install_nginx -> _configure_nginx_global)

    echo ""
    echo -e "${YELLOW}Bạn có muốn cài đặt Memory Cache (Valkey/Redis) không?${NC}"
    echo -e "1. Valkey (Khuyên dùng - thay thế hoàn toàn Redis)"
    echo -e "2. Redis (Truyền thống)"
    echo -e "0. Bỏ qua"
    read -p "Chọn [0-2]: " cache_choice

    # Dùng chung 1 bộ cài object cache duy nhất trong lemp.sh (đã source ở trên)
    if [[ "$cache_choice" == "1" ]]; then
        _install_object_cache_nginx valkey || log_warn "Cài Valkey chưa thành công. Kiểm tra log phía trên."
    elif [[ "$cache_choice" == "2" ]]; then
        _install_object_cache_nginx redis || log_warn "Cài Redis chưa thành công. Kiểm tra log phía trên."
    fi

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}✅ LEMP Stack (Nginx) đã cài đặt hoàn tất!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    pause
}

# ==============================================================================
# NGINX MANAGEMENT MENU
# ==============================================================================

nginx_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          ⚙️  Quản lý Nginx${NC}"
        echo -e "${BLUE}=================================================${NC}"

        # Hiển thị trạng thái
        if systemctl is-active --quiet nginx 2>/dev/null; then
            local ng_ver
            ng_ver=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+' || echo "Unknown")
            echo -e "${GREEN}  ✓ Nginx đang chạy: v${ng_ver}${NC}"
        else
            echo -e "${YELLOW}  ⚠ Nginx chưa chạy hoặc chưa được cài đặt${NC}"
        fi
        echo ""
        echo -e "1. Chỉnh sửa cấu hình chung (nginx.conf)"
        echo -e "2. Chỉnh sửa cấu hình Vhost (Domain)"
        echo -e "3. Kiểm tra cấu hình (nginx -t)"
        echo -e "4. Cứu hộ Nginx (Fix lỗi Config tự động)"
        echo -e "0. Quay lại"
        echo -e "   (Restart/Reload Nginx: Menu chính → 14. Quản lý Dịch vụ Hệ thống)"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn [0-4]: " choice

        case $choice in
            1) edit_nginx_conf ;;
            2) edit_vhost ;;
            3) nginx -t; pause ;;
            4) fix_nginx_config ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

edit_nginx_conf() {
    local conf="/etc/nginx/nginx.conf"
    local bak
    bak=$(backup_nginx_config "$conf")
    nano "$conf"
    if nginx_test_reload; then
        rm -f "$bak"
        log_info "Đã áp dụng nginx.conf."
    else
        read -p "Config lỗi. Khôi phục bản trước khi sửa? [Y/n]: " r
        if [[ "${r,,}" != "n" ]] && [[ -n "$bak" && -f "$bak" ]]; then
            mv -f "$bak" "$conf"
            log_warn "Đã khôi phục nginx.conf về bản trước khi sửa."
        else
            log_warn "Giữ nguyên file đang lỗi. Bản backup: $bak"
        fi
    fi
    pause
}

edit_vhost() {
    # Select site from list
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
    conf="/etc/nginx/sites-available/$domain"

    if [[ ! -f "$conf" ]]; then
        echo -e "${RED}File cấu hình không tồn tại!${NC}"
        pause; return
    fi

    local bak
    bak=$(backup_nginx_config "$conf")
    nano "$conf"
    if nginx_test_reload; then
        rm -f "$bak"
        log_info "Đã áp dụng cấu hình vhost $domain."
    else
        read -p "Config lỗi. Khôi phục bản trước khi sửa? [Y/n]: " r
        if [[ "${r,,}" != "n" ]] && [[ -n "$bak" && -f "$bak" ]]; then
            mv -f "$bak" "$conf"
            log_warn "Đã khôi phục vhost $domain về bản trước khi sửa."
        else
            log_warn "Giữ nguyên file đang lỗi. Bản backup: $bak"
        fi
    fi
    pause
}

fix_nginx_config() {
    log_info "Đang chẩn đoán lỗi Nginx..."

    # Try basic cleanup of known bad files from our script
    if ! nginx -t 2>/dev/null; then
        echo -e "${YELLOW}Phát hiện lỗi config. Đang tự động xử lý...${NC}"

        # 1. Fix location in http block error (cache_headers.conf / browser_caching.conf in conf.d)
        if nginx -t 2>&1 | grep -q "location.*not allowed.*conf.d"; then
            log_info "Phát hiện lỗi 'location' nằm sai chỗ (trong conf.d). Đang xóa file rác..."
            rm -f /etc/nginx/conf.d/cache_headers.conf
            rm -f /etc/nginx/conf.d/browser_caching.conf
        fi

        # 2. Fix duplicate gzip
        if nginx -t 2>&1 | grep -q "gzip.*duplicate"; then
            log_info "Phát hiện lỗi Duplicate Gzip. Đang xóa cấu hình gzip trùng lặp..."
            rm -f /etc/nginx/conf.d/gzip.conf
        fi

        # 3. Check again after auto-fix
        if nginx -t; then
            systemctl restart nginx
            log_info "Đã sửa lỗi và khởi động lại Nginx thành công!"
        else
            echo -e "${RED}Vẫn còn lỗi chưa thể tự sửa:${NC}"
            nginx -t
            echo -e "${YELLOW}Bạn có muốn tạm gỡ các config trong conf.d/* để reset? (Giữ lại Vhost và các file cache bắt buộc) [y/N]${NC}"
            read -p "Chọn: " r
            if [[ "$r" == "y" ]]; then
                local bk_dir="/root/nginx_confd_backup/$(date +%Y%m%d_%H%M%S)"
                mkdir -p "$bk_dir"
                local f base moved=()
                for f in /etc/nginx/conf.d/*.conf; do
                    [[ -f "$f" ]] || continue
                    base=$(basename "$f")
                    # Các vhost đều tham chiếu keys_zone WORDPRESS -> gỡ 2 file này là sập toàn bộ site
                    case "$base" in
                        # File do VPS Manager quản lý và được các vhost tham chiếu (cache zone, biến làm mới cache,
                        # vùng limit_req, map chặn quốc gia): gỡ chúng đi sẽ làm MỌI vhost lỗi theo.
                        fastcgi_cache.conf|fastcgi-buffer.conf|vps-manager-*.conf|ddos_limit.conf|geoip_block.conf) continue ;;
                    esac
                    mv "$f" "$bk_dir/" && moved+=("$base")
                done
                log_info "Đã chuyển ${#moved[@]} file conf.d sang $bk_dir (giữ lại các file do VPS Manager quản lý)."

                if nginx -t; then
                    systemctl reload nginx 2>/dev/null || systemctl restart nginx
                    log_info "Nginx đã chạy lại với conf.d tối giản."
                else
                    log_error "Vẫn lỗi sau khi gỡ conf.d - khôi phục lại các file vừa gỡ, KHÔNG restart Nginx."
                    for base in "${moved[@]}"; do
                        mv "$bk_dir/$base" /etc/nginx/conf.d/ 2>/dev/null
                    done
                    echo -e "${YELLOW}Lỗi nằm ở nginx.conf hoặc vhost. Xem chi tiết: nginx -t${NC}"
                fi
            fi
        fi
    else
        log_info "Nginx cấu hình OK. Không tìm thấy lỗi."
        systemctl reload nginx 2>/dev/null || systemctl restart nginx
    fi
    pause
}
