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

    echo ""
    echo -e "${YELLOW}Bạn có muốn cài đặt Memory Cache (Valkey/Redis) không?${NC}"
    echo -e "1. Valkey (Khuyên dùng - thay thế hoàn toàn Redis)"
    echo -e "2. Redis (Truyền thống)"
    echo -e "0. Bỏ qua"
    read -p "Chọn [0-2]: " cache_choice

    if [[ "$cache_choice" == "1" || "$cache_choice" == "2" ]]; then
        if [[ -f "$ROOT_DIR/modules/wordpress_performance.sh" ]]; then
            source "$ROOT_DIR/modules/wordpress_performance.sh"
        else
            source "modules/wordpress_performance.sh" 2>/dev/null
        fi
        [[ "$cache_choice" == "1" ]] && install_valkey || install_redis
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
        echo -e "4. Khởi động lại Nginx"
        echo -e "5. Cứu hộ Nginx (Fix lỗi Config tự động)"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn: " choice

        case $choice in
            1) edit_nginx_conf ;;
            2) edit_vhost ;;
            3) nginx -t; pause ;;
            4) systemctl restart nginx; pause ;;
            5) fix_nginx_config ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

edit_nginx_conf() {
    nano /etc/nginx/nginx.conf
    nginx -t && systemctl reload nginx
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

    nano "$conf"
    nginx -t && systemctl reload nginx
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
            echo -e "${YELLOW}Bạn có muốn xóa toàn bộ config trong conf.d/* để reset? (Chỉ giữ lại Vhost) [y/N]${NC}"
            read -p "Chọn: " r
            if [[ "$r" == "y" ]]; then
                mkdir -p /root/nginx_confd_backup
                mv /etc/nginx/conf.d/*.conf /root/nginx_confd_backup/ 2>/dev/null
                log_info "Đã backup conf.d ra /root/nginx_confd_backup và xóa sạch folder hiện tại."
                systemctl restart nginx
            fi
        fi
    else
        log_info "Nginx cấu hình OK. Không tìm thấy lỗi."
        systemctl restart nginx
    fi
    pause
}
