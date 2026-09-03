#!/bin/bash

# modules/service.sh - Manage System & LEMP Services

_detect_cache_service() {
    for svc in valkey keydb redis-server redis; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            echo "$svc"
            return 0
        fi
    done
    echo "none"
    return 1
}

service_menu() {
    local cache_svc
    cache_svc=$(_detect_cache_service)
    local cache_label="Cache Server"
    [[ "$cache_svc" != "none" ]] && cache_label="$cache_svc"

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🔄 Quản lý Dịch vụ Hệ thống${NC}"
        echo -e "${BLUE}=================================================${NC}"
        
        # Display live status badges
        _service_print_mini_status "nginx" "Nginx"
        _service_print_php_status
        _service_print_mini_status "mariadb" "MariaDB"
        if [[ "$cache_svc" != "none" ]]; then
            _service_print_mini_status "$cache_svc" "Cache ($cache_svc)"
        fi
        
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Khởi động lại Nginx (Restart)"
        echo -e "2. Nạp lại Nginx không gián đoạn (Reload - Khuyên dùng)"
        echo -e "3. Khởi động lại PHP-FPM (Tất cả phiên bản)"
        echo -e "4. Khởi động lại MariaDB"
        echo -e "5. Khởi động lại ${cache_label}"
        echo -e "6. 🚀 Khởi động lại TẤT CẢ dịch vụ (Full Stack)"
        echo -e "7. Dừng (Stop) một dịch vụ"
        echo -e "8. Bật (Start) một dịch vụ"
        echo -e "9. 📊 Xem trạng thái chi tiết (Systemd Status)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-9]: " choice

        case $choice in
            1) 
                log_info "Kiểm tra cấu hình Nginx..."
                if nginx -t; then
                    log_info "Restarting Nginx..."
                    systemctl restart nginx
                    log_info "Nginx đã khởi động lại thành công!"
                else
                    log_error "Cấu hình Nginx có lỗi! Không restart để tránh sập web."
                fi
                pause
                ;;
            2)
                log_info "Kiểm tra cấu hình Nginx..."
                if nginx -t; then
                    log_info "Reloading Nginx (Zero-downtime)..."
                    systemctl reload nginx
                    log_info "Nginx đã nạp lại cấu hình thành công!"
                else
                    log_error "Cấu hình Nginx có lỗi! Không reload."
                fi
                pause
                ;;
            3)
                log_info "Restarting PHP-FPM..."
                if [[ "$OS_FAMILY" == "rhel" ]]; then
                    systemctl restart php-fpm 2>/dev/null || systemctl restart php*-fpm 2>/dev/null || true
                else
                    systemctl restart php*-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
                fi
                log_info "PHP-FPM đã khởi động lại hoàn tất!"
                pause
                ;;
            4)
                log_info "Restarting MariaDB..."
                systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null
                log_info "MariaDB đã khởi động lại hoàn tất!"
                pause
                ;;
            5)
                local c_svc
                c_svc=$(_detect_cache_service)
                if [[ "$c_svc" != "none" ]]; then
                    log_info "Restarting $c_svc..."
                    systemctl restart "$c_svc"
                    log_info "$c_svc đã khởi động lại hoàn tất!"
                else
                    log_warn "Chưa tìm thấy dịch vụ Cache (Valkey/Redis/KeyDB) nào đang chạy."
                fi
                pause
                ;;
            6)
                log_info "Đang kiểm tra và khởi động lại toàn bộ dịch vụ..."
                nginx -t && systemctl restart nginx
                systemctl restart php*-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
                systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null
                local c_svc2
                c_svc2=$(_detect_cache_service)
                [[ "$c_svc2" != "none" ]] && systemctl restart "$c_svc2" 2>/dev/null
                log_info "✅ Toàn bộ LEMP Stack đã khởi động lại thành công!"
                pause
                ;;
            7)
                _service_stop_interactive
                ;;
            8)
                _service_start_interactive
                ;;
            9)
                _service_detailed_status
                ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

_service_print_mini_status() {
    local svc="$1"
    local name="$2"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "  • %-18s: ${GREEN}● Đang chạy (Active)${NC}\n" "$name"
    else
        printf "  • %-18s: ${RED}○ Đang tắt (Stopped)${NC}\n" "$name"
    fi
}

_service_print_php_status() {
    local running_phps=()
    for v in 7.4 8.0 8.1 8.2 8.3 8.4 8.5; do
        if systemctl is-active --quiet "php${v}-fpm" 2>/dev/null || systemctl is-active --quiet "php${v//./}-php-fpm" 2>/dev/null; then
            running_phps+=("v$v")
        fi
    done
    if systemctl is-active --quiet "php-fpm" 2>/dev/null && [[ ${#running_phps[@]} -eq 0 ]]; then
        running_phps+=("default")
    fi
    if [[ ${#running_phps[@]} -gt 0 ]]; then
        printf "  • %-18s: ${GREEN}● Đang chạy (%s)${NC}\n" "PHP-FPM" "${running_phps[*]}"
    else
        printf "  • %-18s: ${RED}○ Đang tắt${NC}\n" "PHP-FPM"
    fi
}

_service_stop_interactive() {
    echo -e "${YELLOW}Chọn dịch vụ muốn DỪNG (STOP):${NC}"
    echo "1. Nginx"
    echo "2. MariaDB"
    echo "3. PHP-FPM"
    local c_svc; c_svc=$(_detect_cache_service)
    [[ "$c_svc" != "none" ]] && echo "4. Cache ($c_svc)"
    echo "0. Hủy"
    read -p "Chọn: " s_choice
    case $s_choice in
        1) systemctl stop nginx; log_info "Đã dừng Nginx." ;;
        2) systemctl stop mariadb 2>/dev/null || systemctl stop mysql 2>/dev/null; log_info "Đã dừng MariaDB." ;;
        3) systemctl stop php*-fpm 2>/dev/null || systemctl stop php-fpm 2>/dev/null; log_info "Đã dừng PHP-FPM." ;;
        4) [[ "$c_svc" != "none" ]] && systemctl stop "$c_svc" && log_info "Đã dừng $c_svc." ;;
        *) return ;;
    esac
    pause
}

_service_start_interactive() {
    echo -e "${YELLOW}Chọn dịch vụ muốn BẬT (START):${NC}"
    echo "1. Nginx"
    echo "2. MariaDB"
    echo "3. PHP-FPM"
    local c_svc; c_svc=$(_detect_cache_service)
    [[ "$c_svc" != "none" ]] && echo "4. Cache ($c_svc)"
    echo "0. Hủy"
    read -p "Chọn: " s_choice
    case $s_choice in
        1) nginx -t && systemctl start nginx; log_info "Đã bật Nginx." ;;
        2) systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null; log_info "Đã bật MariaDB." ;;
        3) systemctl start php*-fpm 2>/dev/null || systemctl start php-fpm 2>/dev/null; log_info "Đã bật PHP-FPM." ;;
        4) [[ "$c_svc" != "none" ]] && systemctl start "$c_svc" && log_info "Đã bật $c_svc." ;;
        *) return ;;
    esac
    pause
}

_service_detailed_status() {
    clear
    echo -e "${GREEN}=== TRẠNG THÁI CHI TIẾT SYSTEMD ===${NC}"
    echo ""
    echo -e "${CYAN}--- Nginx ---${NC}"
    systemctl status nginx --no-pager -l 2>/dev/null | head -n 12
    echo ""
    echo -e "${CYAN}--- MariaDB ---${NC}"
    systemctl status mariadb --no-pager -l 2>/dev/null | head -n 12 || systemctl status mysql --no-pager -l 2>/dev/null | head -n 12
    echo ""
    local c_svc; c_svc=$(_detect_cache_service)
    if [[ "$c_svc" != "none" ]]; then
        echo -e "${CYAN}--- Cache ($c_svc) ---${NC}"
        systemctl status "$c_svc" --no-pager -l 2>/dev/null | head -n 12
        echo ""
    fi
    pause
}

