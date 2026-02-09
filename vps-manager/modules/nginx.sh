#!/bin/bash

# modules/nginx.sh - Nginx Management

nginx_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Nginx${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Chỉnh sửa cấu hình chung (nginx.conf)"
    echo -e "2. Chỉnh sửa cấu hình Vhost (Domain)"
    echo -e "3. Kiểm tra cấu hình (nginx -t)"
    echo -e "4. Khởi động lại Nginx"
    echo -e "5. Cứu hộ Nginx (Fix lỗi Config tự động)"
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) edit_nginx_conf ;;
        2) edit_vhost ;;
        3) nginx -t; pause ;;
        4) systemctl restart nginx; pause ;;
        5) fix_nginx_config ;;
        0) return ;;
    esac
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
    
    if [ ! -f "$conf" ]; then
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
