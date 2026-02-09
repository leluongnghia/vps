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
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) edit_nginx_conf ;;
        2) edit_vhost ;;
        3) nginx -t; pause ;;
        4) systemctl restart nginx; pause ;;
        0) return ;;
    esac
}

edit_nginx_conf() {
    nano /etc/nginx/nginx.conf
    nginx -t && systemctl reload nginx
    pause
}

edit_vhost() {
    read -p "Nhập domain cần sửa: " domain
    conf="/etc/nginx/sites-available/$domain"
    
    if [ ! -f "$conf" ]; then
        echo -e "${RED}File cấu hình không tồn tại!${NC}"
        pause; return
    fi
    
    nano "$conf"
    nginx -t && systemctl reload nginx
    pause
}
