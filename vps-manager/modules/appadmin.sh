#!/bin/bash

# modules/appadmin.sh - AppAdmin Protection & Tools

appadmin_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý AppAdmin & Tiện ích${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Bảo vệ Tools (HTTP Auth - User/Pass)"
    echo -e "2. Thay đổi Port Admin (Nginx)"
    echo -e "3. Tối ưu hóa Ảnh (Image Optimize)"
    echo -e "4. Cập nhật Hệ thống (System Update)"
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) setup_http_auth ;;
        2) change_admin_port ;;
        3) optimize_images ;;
        4) update_system ;;
        0) return ;;
    esac
}

setup_http_auth() {
    echo "Tính năng này sẽ tạo user/pass cho các folder admin (như /phpmyadmin)."
    read -p "Nhập Username mới: " user
    
    if ! command -v htpasswd &> /dev/null; then
        apt-get install -y apache2-utils
    fi
    
    mkdir -p /etc/nginx/auth
    htpasswd -c /etc/nginx/auth/.htpasswd "$user"
    
    log_info "Đã tạo file auth. Vui lòng thêm cấu hình sau vào Nginx location cần bảo vệ:"
    echo -e "${YELLOW}auth_basic \"Restricted Area\";"
    echo -e "auth_basic_user_file /etc/nginx/auth/.htpasswd;${NC}"
    pause
}

change_admin_port() {
    # Placeholder: requires a dedicated admin vhost
    log_info "Tính năng này yêu cầu bạn có file config admin riêng (ví dụ 22222.conf)."
    pause
}

optimize_images() {
    read -p "Nhập tên miền cần tối ưu ảnh: " domain
    target="/var/www/$domain/public_html"
    
    if [ ! -d "$target" ]; then return; fi
    
    log_info "Đang cài đặt tools..."
    apt-get install -y jpegoptim optipng
    
    log_info "Đang tối ưu JPG..."
    find "$target" -name "*.jpg" -exec jpegoptim --strip-all --all-progressive {} \;
    find "$target" -name "*.jpeg" -exec jpegoptim --strip-all --all-progressive {} \;
    
    log_info "Đang tối ưu PNG..."
    find "$target" -name "*.png" -exec optipng -o7 {} \;
    
    log_info "Hoàn tất."
    pause
}

update_system() {
    log_info "Đang cập nhật hệ thống..."
    apt-get update
    apt-get upgrade -y
    
    log_info "Đang update script..."
    cd /root/vps-manager && git pull 2>/dev/null || echo "Git pull skipped."
    
    log_info "Update hoàn tất."
    pause
}
