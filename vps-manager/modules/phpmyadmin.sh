#!/bin/bash

# modules/phpmyadmin.sh - Install & Manage phpMyAdmin

phpmyadmin_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý phpMyAdmin${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Cài đặt phpMyAdmin"
    echo -e "2. Xóa phpMyAdmin"
    echo -e "3. Secure phpMyAdmin (Đổi URL/Protected)"
    echo -e "4. Xem User/Pass HTTP Auth"
    echo -e "0. Quay lại"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Chọn: " c
    
    case $c in
        1) install_phpmyadmin ;;
        2) uninstall_phpmyadmin ;;
        3) secure_phpmyadmin ;;
        4) view_phpmyadmin_auth ;;
        0) return ;;
        *) echo -e "${RED}Sai lựa chọn.${NC}"; pause ;;
    esac
}

install_phpmyadmin() {
    echo -e "${GREEN}--- Cài đặt phpMyAdmin ---${NC}"
    
    PMA_DIR="/var/www/html/phpmyadmin"
    
    # Check dependencies
    if ! dpkg -l | grep -q php-mbstring; then
        log_info "Cài đặt dependencies..."
        apt-get update
        apt-get install -y php-mbstring php-zip php-gd php-json php-curl
    fi
    
    # Download
    log_info "Đang tải phpMyAdmin..."
    PMA_VER="5.2.1"
    cd /tmp
    wget -q https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/phpMyAdmin-${PMA_VER}-all-languages.tar.gz
    
    if [ ! -f "phpMyAdmin-${PMA_VER}-all-languages.tar.gz" ]; then
        log_error "Tải thất bại."
        return
    fi
    
    mkdir -p /var/www/html
    tar xzf phpMyAdmin-${PMA_VER}-all-languages.tar.gz
    rm -rf "$PMA_DIR"
    mv phpMyAdmin-${PMA_VER}-all-languages "$PMA_DIR"
    rm phpMyAdmin-${PMA_VER}-all-languages.tar.gz
    
    # Config
    cp "$PMA_DIR/config.sample.inc.php" "$PMA_DIR/config.inc.php"
    
    # Generate secret
    SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9')
    sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '$SECRET';/" "$PMA_DIR/config.inc.php"
    
    # Permissions
    chown -R www-data:www-data "$PMA_DIR"
    find "$PMA_DIR" -type d -exec chmod 755 {} \;
    find "$PMA_DIR" -type f -exec chmod 644 {} \;
    
    # Nginx Config Check
    # Ensure default site or specific location exists
    # We will append a location block to the default site if it exists, or suggest URL
    
    # Create a snippet for phpMyAdmin with HTTP Basic Auth
    # Generate Http Auth Password
    if ! command -v htpasswd &> /dev/null; then apt-get install -y apache2-utils; fi
    
    PMA_AUTH_USER="pma_admin"
    PMA_AUTH_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')
    htpasswd -cb /etc/nginx/.phpmyadmin_htpasswd "$PMA_AUTH_USER" "$PMA_AUTH_PASS"

    cat > /etc/nginx/snippets/phpmyadmin.conf <<EOF
location /phpmyadmin {
    root /var/www/html;
    index index.php index.html index.htm;
    try_files \$uri \$uri/ =404;

    # HTTP Basic Auth Protection
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.phpmyadmin_htpasswd;

    location ~ ^/phpmyadmin/(.+\.php)$ {
        alias /var/www/html/phpmyadmin/\$1;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock; 
        fastcgi_param SCRIPT_FILENAME \$request_filename;
    }

    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
        root /var/www/html;
    }
}
EOF

    # Detect PHP version for socket
    PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    if [ -S "/run/php/php$PHP_VER-fpm.sock" ]; then
         sed -i "s|fastcgi_pass.*;|fastcgi_pass unix:/run/php/php$PHP_VER-fpm.sock;|" /etc/nginx/snippets/phpmyadmin.conf
    elif [ -S "/run/php/php8.1-fpm.sock" ]; then
         sed -i "s|fastcgi_pass.*;|fastcgi_pass unix:/run/php/php8.1-fpm.sock;|" /etc/nginx/snippets/phpmyadmin.conf
    elif [ -S "/run/php/php8.2-fpm.sock" ]; then
         sed -i "s|fastcgi_pass.*;|fastcgi_pass unix:/run/php/php8.2-fpm.sock;|" /etc/nginx/snippets/phpmyadmin.conf
    elif [ -S "/run/php/php8.3-fpm.sock" ]; then
         sed -i "s|fastcgi_pass.*;|fastcgi_pass unix:/run/php/php8.3-fpm.sock;|" /etc/nginx/snippets/phpmyadmin.conf
    fi

    # Detect IP
    VPS_IP=$(curl -s https://ifconfig.me || hostname -I | awk '{print $1}')
    # Sanitize IP (remove newlines/spaces)
    VPS_IP=$(echo "$VPS_IP" | tr -d '\n' | tr -d ' ')

    # Create a dedicated vhost for IP access (Default Server)
    # This guarantees that accessing via IP (or any unmatched domain) hits this block
    
    # 1. Disable original default if exists to avoid conflict
    if [ -L "/etc/nginx/sites-enabled/default" ]; then
        rm /etc/nginx/sites-enabled/default
    fi
    
    # 2. Create new default-pma
    cat > /etc/nginx/sites-available/000-phpmyadmin <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Priority for phpmyadmin
    include snippets/phpmyadmin.conf;
    
    # PHP handling for root (if needed)
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VER-fpm.sock;
    }
}
EOF
    # Enable it
    ln -sf /etc/nginx/sites-available/000-phpmyadmin /etc/nginx/sites-enabled/000-phpmyadmin

    if nginx -t; then
        systemctl reload nginx
        log_info "Cài đặt phpMyAdmin hoàn tất!"
        echo -e "${YELLOW}--- THÔNG TIN TRUY CẬP ---${NC}"
        echo -e "URL: http://$VPS_IP/phpmyadmin"
        echo -e "${CYAN}[Bảo mật lớp 1] HTTP Auth:${NC}"
        echo -e "  User: $PMA_AUTH_USER"
        echo -e "  Pass: $PMA_AUTH_PASS"
        echo -e "${CYAN}[Bảo mật lớp 2] Database Login:${NC}"
        
        # Display Root Pass
        if [ -f /root/.my.cnf ]; then
            root_pass=$(grep "password" /root/.my.cnf | cut -d'=' -f2 | tr -d ' "')
            echo -e "  ► User: root | Pass: $root_pass"
        fi
        
        # Display Website Users
        data_file="$HOME/.vps-manager/sites_data.conf"
        if [ -f "$data_file" ]; then
            echo -e "  ► Users Website (Đã lưu):"
            while IFS='|' read -r domain db_name db_user db_pass; do
                if [ -n "$domain" ]; then
                    echo -e "    - $domain: User: $db_user | Pass: $db_pass"
                fi
            done < "$data_file"
        fi
    else
        log_error "Lỗi cấu hình Nginx. Vui lòng kiểm tra lại 'nginx -t'"
        # Rollback faulty vhost to avoid breaking Nginx
        rm -f /etc/nginx/sites-enabled/000-phpmyadmin
    fi
    pause
}

uninstall_phpmyadmin() {
    read -p "Xác nhận gỡ bỏ phpMyAdmin? (y/n): " c
    if [[ "$c" == "y" ]]; then
        rm -rf /var/www/html/phpmyadmin
        log_info "Đã gỡ bỏ."
    fi
    pause
}

secure_phpmyadmin() {
    echo -e "${YELLOW}Tính năng này sẽ đổi tên thư mục để che giấu URL.${NC}"
    read -p "Nhập tên đường dẫn mới (ví dụ: sequalo): " new_alias
    
    if [ -z "$new_alias" ]; then return; fi
    
    if [ -d "/var/www/html/phpmyadmin" ]; then
        mv "/var/www/html/phpmyadmin" "/var/www/html/$new_alias"
        log_info "Đã đổi thành: http://<IP_VPS>/$new_alias"
    elif [ -d "/var/www/html/$new_alias" ]; then
        log_warn "Thư mục đã tồn tại."
    else
        log_error "Không tìm thấy thư mục gốc phpMyAdmin."
    fi
    pause
}

view_phpmyadmin_auth() {
    echo -e "${YELLOW}--- Thông tin phpMyAdmin HTTP Auth ---${NC}"
    
    if [ ! -f /etc/nginx/.phpmyadmin_htpasswd ]; then
        echo -e "${RED}Không tìm thấy file mật khẩu! (Bạn đã cài đặt phpMyAdmin chưa?)${NC}"
    else
        echo -e "User: pma_admin"
        echo -e "${YELLOW}Lưu ý: Mật khẩu này đã được mã hóa trong file htpasswd và KHÔNG THỂ xem lại được.${NC}"
        echo -e "Nếu bạn quên mật khẩu lớp 1, hãy reset lại."
        
        echo -e ""
        read -p "Bạn có muốn Đặt lại (Reset) mật khẩu lớp 1 không? (y/n): " rs
        if [[ "$rs" == "y" ]]; then
             if ! command -v htpasswd &> /dev/null; then apt-get install -y apache2-utils; fi
             
             read -p "Nhập mật khẩu mới (Để trống sẽ sinh ngẫu nhiên): " new_pass
             if [ -z "$new_pass" ]; then
                new_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9')
             fi
             
             htpasswd -cb /etc/nginx/.phpmyadmin_htpasswd "pma_admin" "$new_pass"
             echo -e "${GREEN}Đã đặt lại mật khẩu thành công!${NC}"
             echo -e "User: pma_admin"
             echo -e "Pass: $new_pass"
        fi
    fi
    fi
    
    echo -e "\n${YELLOW}--- [Bảo mật lớp 2] Database Login Info ---${NC}"
    
    # 1. ROOT Credential
    if [ -f /root/.my.cnf ]; then
        root_pass=$(grep "password" /root/.my.cnf | cut -d'=' -f2 | tr -d ' "')
        echo -e "${RED}► MySQL ROOT:${NC}"
        echo -e "   User: root"
        echo -e "   Pass: $root_pass"
    else
        echo -e "${RED}MySQL Root:${NC} Không tìm thấy file .my.cnf (Pass rỗng hoặc đã đổi)"
    fi
    
    # 2. Website Users
    data_file="$HOME/.vps-manager/sites_data.conf"
    if [ -f "$data_file" ]; then
        echo -e "\n${CYAN}► Website Users (Từ hệ thống):${NC}"
        while IFS='|' read -r domain db_name db_user db_pass; do
            if [ -n "$domain" ]; then
                echo -e "   🌐 $domain:"
                echo -e "      User: $db_user"
                echo -e "      Pass: $db_pass"
            fi
        done < "$data_file"
    else
        echo -e "\n${CYAN}► Website Users:${NC} Chưa có dữ liệu website nào."
    fi
    
    pause
}
