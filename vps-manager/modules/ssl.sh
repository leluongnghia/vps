#!/bin/bash

# modules/ssl.sh - SSL Management (Let's Encrypt)

install_ssl() {
    local domain=$1
    if [ -z "$domain" ]; then
        read -p "Nhập tên miền để cài SSL: " domain
    fi

    if [ ! -d "/var/www/$domain/public_html" ]; then
        echo -e "${RED}Website $domain chưa được thêm trên VPS này!${NC}"
        pause
        return
    fi

    log_info "Đang cài đặt Certbot..."
    if ! command -v certbot &> /dev/null; then
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi

    log_info "Đang yêu cầu chứng chỉ SSL cho $domain..."
    
    # Run certbot non-interactively
    certbot --nginx -d "$domain" -d "www.$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Cài đặt SSL thành công cho $domain!${NC}"
    else
        echo -e "${RED}Cài đặt SSL thất bại. Vui lòng kiểm tra DNS trỏ về IP VPS chưa.${NC}"
    fi
    
    if [ -z "$1" ]; then pause; fi
}
