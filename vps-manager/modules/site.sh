#!/bin/bash

# modules/site.sh - Site & Domain Management

manage_sites_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Website & Tên miền${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Thêm Website mới (WordPress)"
    echo -e "2. Thêm Website mới (PHP thuan/Static)"
    echo -e "3. Xóa Website"
    echo -e "4. Danh sách Website"
    echo -e "5. Quản lý Redirect (301/302)"
    echo -e "6. Fix Permissions (Phân quyền)"
    echo -e "7. Clone/Nhân bản Website"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-7]: " choice

    case $choice in
        1) add_new_site "wordpress" ;;
        2) add_new_site "php" ;;
        3) delete_site ;;
        4) list_sites ;;
        5) manage_redirects ;;
        6) fix_permissions ;;
        7) clone_site ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

add_new_site() {
    local type=$1
    echo -e "${GREEN}--- Thêm Website Mới ($type) ---${NC}"
    read -p "Nhập tên miền (ví dụ: example.com): " domain
    
    # Check domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Định dạng tên miền không hợp lệ!${NC}"
        pause
        return
    fi

    # Check if site exists
    if [ -d "/var/www/$domain" ]; then
        echo -e "${RED}Website $domain đã tồn tại!${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}Đang tạo cấu hình cho $domain...${NC}"
    
    # Create web root
    mkdir -p "/var/www/$domain/public_html"
    chown -R www-data:www-data "/var/www/$domain"
    chmod -R 755 "/var/www/$domain"

    # Create Nginx Config
    create_nginx_config "$domain"

    # Database setup if needed
    if [[ "$type" == "wordpress" ]]; then
        setup_database "$domain"
        install_wordpress "$domain"
    fi

    # SSL Setup Prompt
    read -p "Bạn có muốn cài đặt SSL Let's Encrypt ngay bây giờ không? (y/n): " ssl_confirm
    if [[ "$ssl_confirm" == "y" || "$ssl_confirm" == "Y" ]]; then
        if [ -f "$(dirname "${BASH_SOURCE[0]}")/ssl.sh" ]; then
             source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
             install_ssl "$domain"
        else
             log_warn "Module SSL chưa được cài đặt."
        fi
    fi

    log_info "Hoàn tất thêm website $domain."
    pause
}

create_nginx_config() {
    local domain=$1
    local config_file="/etc/nginx/sites-available/$domain"
    
    # Simple PHP-FPM config
    cat > "$config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    root /var/www/$domain/public_html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        
        # FastCGI Cache Settings
        fastcgi_cache WORDPRESS;
        fastcgi_cache_valid 200 301 302 60m;
        fastcgi_cache_use_stale error timeout updating invalid_header http_500 http_503;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        add_header X-FastCGI-Cache \$upstream_cache_status;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -s "$config_file" "/etc/nginx/sites-enabled/"
    nginx -t && systemctl reload nginx
}

setup_database() {
    local domain=$1
    # Remove dots for db name
    local db_name=$(echo "$domain" | tr -d '.')
    local db_user="${db_name}_user"
    local db_pass=$(openssl rand -base64 12)

    log_info "Đang tạo cơ sở dữ liệu..."
    
    # This requires .my.cnf or root access without password, or prompting. 
    # For script simplicity, we assume root setup or use 'mysql' command if unix_socket auth is on.
    mysql -e "CREATE DATABASE ${db_name};"
    mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"

    echo -e "${GREEN}DB Name: $db_name${NC}"
    echo -e "${GREEN}DB User: $db_user${NC}"
    echo -e "${GREEN}DB Pass: $db_pass${NC}"
    
    # Save these credentials for WP config
    export WP_DB_NAME="$db_name"
    export WP_DB_USER="$db_user"
    export WP_DB_PASS="$db_pass"
}

install_wordpress() {
    local domain=$1
    log_info "Đang tải và cài đặt WordPress..."
    cd "/var/www/$domain/public_html"
    wget -q https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    mv wordpress/* .
    rm -rf wordpress latest.tar.gz

    # Setup wp-config.php
    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/$WP_DB_NAME/" wp-config.php
    sed -i "s/username_here/$WP_DB_USER/" wp-config.php
    sed -i "s/password_here/$WP_DB_PASS/" wp-config.php

    # Fix permissions again
    chown -R www-data:www-data "/var/www/$domain/public_html"
}

delete_site() {
    read -p "Nhập tên miền cần xóa: " domain
    if [ -z "$domain" ]; then return; fi
    
    read -p "Bạn có chắc chắn muốn xóa $domain không? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    # Remove files
    rm -rf "/var/www/$domain"
    
    # Remove Nginx config
    rm "/etc/nginx/sites-available/$domain"
    rm "/etc/nginx/sites-enabled/$domain"
    systemctl reload nginx

    # Drop DB (Optional - simplistic approach)
    local db_name=$(echo "$domain" | tr -d '.')
    local db_user="${db_name}_user"
    mysql -e "DROP DATABASE IF EXISTS ${db_name};"
    mysql -e "DROP USER IF EXISTS '${db_user}'@'localhost';"

    log_info "Đã xóa website $domain."
    pause
}

list_sites() {
    echo -e "${GREEN}Danh sách các website:${NC}"
    # Improved listing with size
    printf "%-30s %-15s\n" "Domain" "Size"
    echo "----------------------------------------------"
    for dir in /var/www/*; do
        if [ -d "$dir" ]; then
            domain=$(basename "$dir")
            size=$(du -sh "$dir" | awk '{print $1}')
            printf "%-30s %-15s\n" "$domain" "$size"
        fi
    done
    pause
}

manage_redirects() {
    echo -e "${GREEN}--- Quản lý Redirect ---${NC}"
    echo -e "1. Thêm Redirect (Domain sang Domain/URL)"
    echo -e "2. Xóa Redirect"
    read -p "Chọn [1-2]: " rd_choice
    
    case $rd_choice in
        1)
            read -p "Nhập domain nguồn (đang trỏ về VPS này): " source_domain
            read -p "Nhập URL đích (ví dụ https://newdomain.com): " target_url
            read -p "Loại redirect (301 - Vĩnh viễn, 302 - Tạm thời): " code
            
            if [[ "$code" != "301" && "$code" != "302" ]]; then
                 echo "Mã lỗi không hợp lệ. Mặc định 301."
                 code="301"
            fi
            
            conf_file="/etc/nginx/sites-available/${source_domain}_redirect"
            cat > "$conf_file" <<EOF
server {
    listen 80;
    server_name $source_domain www.$source_domain;
    return $code $target_url\$request_uri;
}
EOF
            ln -s "$conf_file" "/etc/nginx/sites-enabled/"
            nginx -t && systemctl reload nginx
            log_info "Đã thêm redirect: $source_domain -> $target_url ($code)"
            ;;
        2)
            read -p "Nhập domain redirect muốn xóa: " del_domain
            rm "/etc/nginx/sites-available/${del_domain}_redirect"
            rm "/etc/nginx/sites-enabled/${del_domain}_redirect"
            systemctl reload nginx
            log_info "Đã xóa redirect cho $del_domain"
            ;;
    esac
    pause
}

fix_permissions() {
    read -p "Nhập domain cần phân quyền (để trống để fix tất cả): " domain
    
    if [ -z "$domain" ]; then
        target="/var/www"
    else
        target="/var/www/$domain"
    fi
    
    log_info "Đang thiết lập quyền chuẩn cho $target..."
    chown -R www-data:www-data "$target"
    find "$target" -type d -exec chmod 755 {} \;
    find "$target" -type f -exec chmod 644 {} \;
    
    log_info "Hoàn tất phân quyền."
    pause
}

clone_site() {
    echo -e "${YELLOW}--- Clone Website ---${NC}"
    read -p "Nhập domain NGUỒN: " src_domain
    read -p "Nhập domain ĐÍCH (Mới): " dest_domain
    
    if [ ! -d "/var/www/$src_domain" ]; then
        echo -e "${RED}Domain nguồn không tồn tại!${NC}"
        pause; return
    fi
    
    if [ -d "/var/www/$dest_domain" ]; then
        echo -e "${RED}Domain đích đã tồn tại! Vui lòng xóa trước.${NC}"
        pause; return
    fi
    
    # 1. Clone Files
    log_info "Đang copy mã nguồn..."
    mkdir -p "/var/www/$dest_domain"
    rsync -av --exclude 'wp-config.php' "/var/www/$src_domain/" "/var/www/$dest_domain/"
    
    # 2. Config Nginx for Dest
    create_nginx_config "$dest_domain"
    
    # 3. Create New DB
    local new_db_name=$(echo "$dest_domain" | tr -d '.')
    local new_db_user="${new_db_name}_user"
    local new_db_pass=$(openssl rand -base64 12)
    
    log_info "Đang tạo database mới cho $dest_domain..."
    mysql -e "CREATE DATABASE ${new_db_name};"
    mysql -e "CREATE USER '${new_db_user}'@'localhost' IDENTIFIED BY '${new_db_pass}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${new_db_name}.* TO '${new_db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # 4. Export & Import DB
    # Need to find source DB creds? Or just dump if we have root/socket access
    # Parsing wp-config.php of source to get DB Name
    src_db_name=$(grep "DB_NAME" "/var/www/$src_domain/public_html/wp-config.php" | cut -d "'" -f 4)
    
    if [ -n "$src_db_name" ]; then
        log_info "Đang clone database ($src_db_name -> $new_db_name)..."
        mysqldump "$src_db_name" | mysql "$new_db_name"
        
        # 5. Search & Replace URL
        # Using WP-CLI if available, else sed on dump?
        # Recommend installing WP-CLI in setup??
        # Simple sed on DB dump is risky for serialized data. 
        # But for script simplicity without WP-CLI:
        # A better way: Use a php script or just warn user.
        # Let's try installing wp-cli locally if not present?
        
        if ! command -v wp &> /dev/null; then
             curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
             chmod +x wp-cli.phar
             mv wp-cli.phar /usr/local/bin/wp
        fi
        
        log_info "Đang thay thế URL (Search-Replace)..."
        cd "/var/www/$dest_domain/public_html"
        
        # Create new wp-config
        cp "/var/www/$src_domain/public_html/wp-config.php" .
        sed -i "s/DB_NAME', '.*'/DB_NAME', '$new_db_name'/" wp-config.php
        sed -i "s/DB_USER', '.*'/DB_USER', '$new_db_user'/" wp-config.php
        sed -i "s/DB_PASSWORD', '.*'/DB_PASSWORD', '$new_db_pass'/" wp-config.php
        
        # Allow root wp-cli
        wp search-replace "http://$src_domain" "http://$dest_domain" --allow-root
        wp search-replace "https://$src_domain" "https://$dest_domain" --allow-root
        wp search-replace "$src_domain" "$dest_domain" --allow-root
        
        log_info "Đã clone xong Database & Config."
    else
        log_warn "Không tìm thấy cấu hình DB nguồn. Chỉ copy code."
    fi
    
    # Fix Permissions
    chown -R www-data:www-data "/var/www/$dest_domain"
    
    log_info "Clone hoàn tất! Domain mới: $dest_domain"
    pause
}
