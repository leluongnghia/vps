#!/bin/bash

# modules/site.sh - Site & Domain Management

manage_sites_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Website & Tên miền${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Danh sách Tên miền"
    echo -e "2. Thêm Tên miền mới"
    echo -e "3. Xóa Tên miền"
    echo -e "4. Thay đổi Tên miền (Rename Domain)"
    echo -e "5. Cấu hình lại Nginx (Rewrite Vhost)"
    echo -e "6. Parked/Alias Domain"
    echo -e "7. Redirect Domain"
    echo -e "8. Đổi phiên bản PHP cho Website"
    echo -e "9. Clone/Nhân bản Website"
    echo -e "10. Đổi thông tin Database (wp-config)"
    echo -e "11. Đặt mật khẩu bảo vệ thư mục"
    echo -e "12. Fix Permissions"
    echo -e "13. Kiểm tra/Sửa lỗi WordPress Core"
    echo -e "14. Bật/Tắt FastCGI Cache (Dev Mode)"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-14]: " choice

    case $choice in
        1) list_sites ;;
        2) 
            echo -e "1. WordPress\n2. PHP Thuần"
            read -p "Chọn loại: " t
            if [[ "$t" == "1" ]]; then add_new_site "wordpress"; else add_new_site "php"; fi
            ;;
        3) delete_site ;;
        4) rename_site ;;
        5) rewrite_vhost_config ;;
        6) manage_parked_domains ;;
        7) manage_redirects ;;
        8) change_site_php ;;
        9) clone_site ;;
        10) update_site_db_info ;;
        11) protect_folder ;;
        12) fix_permissions ;;
        13) check_wp_core ;;
        14) toggle_site_cache ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

add_new_site() {
    local type=$1
    echo -e "${GREEN}--- Thêm Website Mới ($type) ---${NC}"
    read -p "Nhập tên miền (ví dụ: example.com): " domain
    
    # Validate domain format
    if ! validate_domain "$domain"; then
        pause; return
    fi
    
    # Check disk space (require 2GB free for WordPress)
    if ! check_disk_space "/var/www" 2048; then
        pause; return
    fi

    # Check if site exists
    if [ -d "/var/www/$domain" ]; then
        echo -e "${RED}Website $domain đã tồn tại!${NC}"
        pause; return
    fi

    echo -e "${YELLOW}Đang tạo cấu hình cho $domain...${NC}"
    
    # 1. Setup Global Cache if missing
    if [ ! -f /etc/nginx/conf.d/fastcgi_cache.conf ]; then
        log_info "Đang khởi tạo cấu hình FastCGI Cache Global..."
        mkdir -p /var/run/nginx-cache
        chown -R www-data:www-data /var/run/nginx-cache
        cat > /etc/nginx/conf.d/fastcgi_cache.conf <<EOF
fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=WORDPRESS:100m inactive=60m;
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;
EOF
        # Reload to apply global cache config first!
        nginx -t && systemctl reload nginx
    fi

    # 2. Create web root
    mkdir -p "/var/www/$domain/public_html"
    chown -R www-data:www-data "/var/www/$domain"
    chmod -R 755 "/var/www/$domain"

    # 3. Create Nginx Config
    create_nginx_config "$domain"

    # 4. Database & WP setup
    if [[ "$type" == "wordpress" ]]; then
        setup_database "$domain"
        
        echo -e "${YELLOW}Bạn có muốn cài đặt WordPress Core mặc định không?${NC}"
        echo -e "1. Có (Tải bản mới nhất từ WordPress.org)"
        echo -e "2. Không (Tôi sẽ tự upload code hoặc restore backup)"
        read -p "Chọn [1-2]: " wp_choice
        
        if [[ "$wp_choice" == "1" ]]; then
            install_wordpress "$domain"
        else
            echo -e "${GREEN}Đã bỏ qua bước cài đặt WordPress.${NC}"
            echo -e "Thư mục root: /var/www/$domain/public_html"
            echo -e "Thông tin Database đã tạo (dùng để cấu hình wp-config.php):"
            echo -e "DB Name: $WP_DB_NAME"
            echo -e "DB User: $WP_DB_USER"
            echo -e "DB Pass: $WP_DB_PASS"
        fi
    fi

    # 5. SSL Auto Setup
    echo -e "${YELLOW}Đang cấu hình SSL Let's Encrypt...${NC}"
    # Default to YES/Auto
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/ssl.sh" ]; then
         source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
         # Call install_ssl_auto without prompt if possible, or just call normal install_ssl
         # We'll invoke install_ssl but usually it might ask for email.
         # Let's assume install_ssl is interactive. If we want auto, we need non-interactive version.
         # For now, just call it.
         install_ssl "$domain"
    else
         log_warn "Module SSL chưa được cài đặt."
    fi

    log_info "Hoàn tất thêm website $domain."
    pause
}

create_nginx_config() {
    local domain=$1
    local config_file="/etc/nginx/sites-available/$domain"
    
    # Dynamic PHP socket detection using shared helper
    local php_sock
    php_sock=$(detect_php_socket 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$php_sock" ]; then
        log_error "Không tìm thấy PHP-FPM socket. Hãy cài PHP-FPM trước."
        return 1
    fi
    
    log_info "Using PHP socket: $php_sock"
    
    # Create Nginx configuration
    cat > "$config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    root /var/www/$domain/public_html;
    index index.php index.html index.htm;
    client_max_body_size 128M;

    # ============================================================
    # FastCGI Cache Skip Rules
    # Bỏ qua cache cho admin và login để tránh lỗi đăng nhập
    # ============================================================
    set \$skip_cache 0;
    if (\$request_method = POST) { set \$skip_cache 1; }
    if (\$query_string != "") { set \$skip_cache 1; }
    # Bỏ qua cache cho wp-admin/, wp-login.php, xmlrpc, feed, sitemap
    if (\$request_uri ~* "/wp-admin/|/wp-login\.php|/xmlrpc\.php|/wp-.*\.php|^/feed/|/tag/.*/feed/|/.*sitemap.*\.(xml|xsl)") {
        set \$skip_cache 1;
    }
    # Bỏ qua cache cho user đã đăng nhập (WordPress cookies)
    if (\$http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
        set \$skip_cache 1;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass $php_sock;
        
        # FastCGI Cache Settings
        fastcgi_cache WORDPRESS;
        fastcgi_cache_valid 200 301 302 60m;
        fastcgi_cache_use_stale error timeout updating invalid_header http_500 http_503;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        fastcgi_cache_bypass \$skip_cache;
        fastcgi_no_cache \$skip_cache;
        add_header X-FastCGI-Cache \$upstream_cache_status;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Make sure to remove the old symlink first so it doesn't cause "File exists" warning
    rm -f "/etc/nginx/sites-enabled/$domain"
    ln -s "$config_file" "/etc/nginx/sites-enabled/"
    nginx -t && systemctl reload nginx
}

setup_database() {
    local domain=$1
    # Remove dots and hyphens for db name, keep it simple
    local db_name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
    local db_user="${db_name}_u"
    # Use alphanumeric password to avoid sed issues and complexity
    local db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

    log_info "Creating database..."
    
    # Use new MySQL helper with proper credential handling
    if create_database "$db_name" "$db_user" "$db_pass"; then
        echo -e "${GREEN}DB Name: $db_name${NC}"
        echo -e "${GREEN}DB User: $db_user${NC}"
        echo -e "${GREEN}DB Pass: $db_pass${NC}"
        
        export WP_DB_NAME="$db_name"
        export WP_DB_USER="$db_user"
        export WP_DB_PASS="$db_pass"
        
        # SAVE TO LOCAL STORAGE (Persistent)
        local data_file="$HOME/.vps-manager/sites_data.conf"
        mkdir -p "$(dirname "$data_file")"
        
        # Remove old entry if exists
        if [ -f "$data_file" ]; then
            sed -i "/^$domain|/d" "$data_file"
        fi
        
        # Format: domain|db_name|db_user|db_pass
        echo "$domain|$db_name|$db_user|$db_pass" >> "$data_file"
        chmod 600 "$data_file"
    else
        log_error "Failed to create database"
        return 1
    fi
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
    
    # Use pipe | delimiter to avoid issues with special chars if any
    sed -i "s|database_name_here|$WP_DB_NAME|" wp-config.php
    sed -i "s|username_here|$WP_DB_USER|" wp-config.php
    sed -i "s|password_here|$WP_DB_PASS|" wp-config.php

    # Fix permissions again
    chown -R www-data:www-data "/var/www/$domain/public_html"
}

# Helper: Select Site
select_site() {
    echo -e "\n${CYAN}Danh sách Website trên VPS:${NC}"
    sites=()
    i=1
    for d in /var/www/*; do
        if [[ -d "$d" && "$(basename "$d")" != "html" ]]; then
            domain=$(basename "$d")
            sites+=("$domain")
            echo -e "$i. $domain"
            ((i++))
        fi
    done
    
    if [ ${#sites[@]} -eq 0 ]; then
        echo -e "${RED}Không tìm thấy website nào!${NC}"
        return 1
    fi
    
    read -p "Chọn website [1-${#sites[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#sites[@]}" ]; then
        echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
        return 1
    fi
    
    SELECTED_DOMAIN="${sites[$((choice-1))]}"
    echo -e "${GREEN}-> Đã chọn: $SELECTED_DOMAIN${NC}"
    return 0
}

delete_site() {
    echo -e "${YELLOW}--- Xóa Website ---${NC}"
    select_site || return
    domain="$SELECTED_DOMAIN"
    
    echo -e "${RED}CẢNH BÁO: Hành động này sẽ xóa toàn bộ mã nguồn và cơ sở dữ liệu của $domain!${NC}"
    read -p "Bạn có CHẮC CHẮN muốn xóa $domain không? (nhập 'y' để đồng ý): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Đã hủy thao tác xóa.${NC}"
        pause; return
    fi

    log_info "Đang xóa website $domain..."

    # Remove files
    rm -rf "/var/www/$domain"
    
    # Remove Nginx config
    rm -f "/etc/nginx/sites-available/$domain"
    rm -f "/etc/nginx/sites-enabled/$domain"
    systemctl reload nginx

    # Drop DB (Auto detect simple names)
    # MUST MATCH creation logic: tr -d '.-' | cut -c1-16
    local db_name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
    local db_user="${db_name}_u"
    
    if command -v mysql &> /dev/null; then
        mysql -e "DROP DATABASE IF EXISTS ${db_name};" 2>/dev/null
        mysql -e "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null
        mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    fi

    log_info "Đã xóa hoàn toàn website $domain."
    pause
}

clone_site() {
    echo -e "${YELLOW}--- Clone Website ---${NC}"
    select_site || return
    src_domain="$SELECTED_DOMAIN"
    
    read -p "Nhập domain ĐÍCH (Mới): " dest_domain
    
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
    # Limit db name length and complexity
    local new_db_name=$(echo "$dest_domain" | tr -d '.-' | cut -c1-16)
    local new_db_user="${new_db_name}_u"
    local new_db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    log_info "Đang tạo database mới cho $dest_domain..."
    mysql -e "CREATE DATABASE ${new_db_name};"
    mysql -e "CREATE USER '${new_db_user}'@'localhost' IDENTIFIED BY '${new_db_pass}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${new_db_name}.* TO '${new_db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # 4. Export & Import DB
    # Attempt to extract DB name using PHP for reliability (compatible with ' or " quotes)
    src_db_name=$(php -r "include '/var/www/$src_domain/public_html/wp-config.php'; echo DB_NAME;" 2>/dev/null)
    
    # Fallback to grep if PHP fails
    if [ -z "$src_db_name" ]; then
        src_db_name=$(grep "DB_NAME" "/var/www/$src_domain/public_html/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
    fi
    
    if [ -n "$src_db_name" ]; then
        log_info "Đang clone database ($src_db_name -> $new_db_name)..."
        mysqldump "$src_db_name" | mysql "$new_db_name"
        
        # 5. Search & Replace URL
        if ! command -v wp &> /dev/null; then
             curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
             chmod +x wp-cli.phar
             mv wp-cli.phar /usr/local/bin/wp
        fi
        
        log_info "Đang thay thế URL (Search-Replace)..."
        cd "/var/www/$dest_domain/public_html"
        
        # Create new wp-config
        cp "/var/www/$src_domain/public_html/wp-config.php" .
        sed -i "s|DB_NAME', '.*'|DB_NAME', '$new_db_name'|" wp-config.php
        sed -i "s|DB_USER', '.*'|DB_USER', '$new_db_user'|" wp-config.php
        sed -i "s|DB_PASSWORD', '.*'|DB_PASSWORD', '$new_db_pass'|" wp-config.php
        
        wp search-replace "http://$src_domain" "http://$dest_domain" --allow-root
        wp search-replace "https://$src_domain" "https://$dest_domain" --allow-root
        wp search-replace "$src_domain" "$dest_domain" --allow-root
        
        log_info "Đã clone xong Database & Config."
    else
        log_warn "Không tìm thấy cấu hình DB nguồn (hoặc không thể đọc wp-config.php). Chỉ copy code."
    fi
    
    chown -R www-data:www-data "/var/www/$dest_domain"
    log_info "Clone hoàn tất! Domain mới: $dest_domain"
    echo -e "DB Name: $new_db_name | User: $new_db_user | Pass: $new_db_pass"
    pause
}

rename_site() {
    echo -e "${YELLOW}--- Thay đổi Tên miền (Rename) ---${NC}"
    select_site || return
    old_domain="$SELECTED_DOMAIN"
    
    read -p "Nhập domain MỚI: " new_domain
    
    if [ -d "/var/www/$new_domain" ]; then echo -e "${RED}Domain mới đã tồn tại.${NC}"; pause; return; fi
    if [ -f "/etc/nginx/sites-available/$new_domain" ]; then echo -e "${RED}Config Nginx mới đã tồn tại.${NC}"; pause; return; fi
    
    log_info "Đổi tên thư mục..."
    mv "/var/www/$old_domain" "/var/www/$new_domain"
    
    log_info "Cập nhật Nginx..."
    # Config file rename to preserve custom snippets
    old_conf="/etc/nginx/sites-available/$old_domain"
    new_conf="/etc/nginx/sites-available/$new_domain"
    
    if [ -f "$old_conf" ]; then
        mv "$old_conf" "$new_conf"
        # Update server_name old.com www.old.com -> new.com www.new.com
        # Update root /var/www/old -> /var/www/new
        # Use delimiter | to avoid slash issues
        sed -i "s|root.*/var/www/$old_domain|root /var/www/$new_domain|" "$new_conf"
        sed -i "s|server_name.*$old_domain.*|server_name $new_domain www.$new_domain;|" "$new_conf"
        
        # Re-link
        rm -f "/etc/nginx/sites-enabled/$old_domain"
        ln -s "$new_conf" "/etc/nginx/sites-enabled/"
        
        nginx -t && systemctl reload nginx
    else
        log_warn "Không tìm thấy Nginx config cũ. Tạo mới..."
        create_nginx_config "$new_domain"
    fi
    
    log_info "Cập nhật URL trong Database (nếu là WP)..."
    if [ -f "/var/www/$new_domain/public_html/wp-config.php" ]; then
        cd "/var/www/$new_domain/public_html"
        if ! command -v wp &> /dev/null; then
             curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; chmod +x wp-cli.phar; mv wp-cli.phar /usr/local/bin/wp
        fi
        
        wp search-replace "http://$old_domain" "http://$new_domain" --allow-root
        wp search-replace "https://$old_domain" "https://$new_domain" --allow-root
        wp search-replace "$old_domain" "$new_domain" --allow-root
    fi
    
    log_info "Đổi tên thành công: $old_domain -> $new_domain"
    pause
}

rewrite_vhost_config() {
    select_site || return
    domain="$SELECTED_DOMAIN"
    
    create_nginx_config "$domain"
    log_info "Đã tạo lại file cấu hình Nginx cho $domain."
    
    # SSL Check/Restore
    echo -e "${YELLOW}Bạn có muốn cài đặt/khôi phục SSL cho $domain không?${NC}"
    echo -e "1. Có (Let's Encrypt - Auto)"
    echo -e "2. Không (Chỉ dùng HTTP 80)"
    read -p "Chọn [1-2]: " ssl_c
    
    if [[ "$ssl_c" == "1" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
        # Force non-interactive letsencrypt if possible
        if command -v certbot &> /dev/null; then
             certbot --nginx -d "$domain" -d "www.$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect
             echo -e "${GREEN}Đã khôi phục SSL thành công.${NC}"
        else
             install_ssl "$domain"
        fi
    fi
    pause
}

change_site_php() {
    select_site || return
    domain="$SELECTED_DOMAIN"
    conf="/etc/nginx/sites-available/$domain"
    
    if [ ! -f "$conf" ]; then echo -e "${RED}Config Nginx không tồn tại.${NC}"; pause; return; fi
    
    echo -e "Chọn phiên bản PHP:"
    echo "1. PHP 8.1"
    echo "2. PHP 8.2"
    echo "3. PHP 8.3"
    read -p "Chọn [1-3]: " v
    case $v in
        1) ver="8.1" ;;
        2) ver="8.2" ;;
        3) ver="8.3" ;;
        *) return ;;
    esac
    
    # Replace fastcgi_pass line
    sed -i "s|fastcgi_pass.*unix:.*|fastcgi_pass unix:/run/php/php$ver-fpm.sock;|" "$conf"
    
    nginx -t && systemctl reload nginx
    log_info "Đã chuyển $domain sang PHP $ver"
    pause
}

update_site_db_info() {
    select_site || return
    domain="$SELECTED_DOMAIN"
    wp_conf="/var/www/$domain/public_html/wp-config.php"
    
    if [ ! -f "$wp_conf" ]; then echo -e "${RED}Không tìm thấy wp-config.php${NC}"; pause; return; fi
    
    read -p "Database Name mới: " db_name
    read -p "Database User mới: " db_user
    read -p "Database Password mới: " db_pass
    
    sed -i "s|DB_NAME', '.*'|DB_NAME', '$db_name'|" "$wp_conf"
    sed -i "s|DB_USER', '.*'|DB_USER', '$db_user'|" "$wp_conf"
    sed -i "s|DB_PASSWORD', '.*'|DB_PASSWORD', '$db_pass'|" "$wp_conf"
    
    log_info "Đã cập nhật thông tin Database."
    pause
}

manage_parked_domains() {
    echo -e "1. Thêm Parked Domain (Alias)"
    echo -e "2. Xóa Parked Domain"
    read -p "Chọn: " c
    
    case $c in
        1)
            select_site || return
            main="$SELECTED_DOMAIN"
            conf="/etc/nginx/sites-available/$main"
            
            read -p "Domain ALIAS (Parked): " alias
            
            if grep -q "server_name .*$alias" "$conf"; then
                echo "Alias đã tồn tại."
            else
                sed -i "/server_name/ s/;/ $alias www.$alias;/" "$conf"
                nginx -t && systemctl reload nginx
                log_info "Đã thêm alias $alias cho $main"
                echo -e "${YELLOW}Lưu ý: Bạn cần cấp lại SSL để bao gồm cả domain alias!${NC}"
            fi
            ;;
        2)
            select_site || return
            main="$SELECTED_DOMAIN"
            conf="/etc/nginx/sites-available/$main"
            
            read -p "Domain ALIAS cần xóa: " alias
            sed -i "s/ $alias//" "$conf"
            sed -i "s/ www.$alias//" "$conf"
            nginx -t && systemctl reload nginx
            log_info "Đã gỡ alias."
            ;;
    esac
    pause
}

protect_folder() {
    select_site || return
    domain="$SELECTED_DOMAIN"
    conf="/etc/nginx/sites-available/$domain"
    
    read -p "Username: " user
    read -p "Password: " pass
    
    if ! command -v htpasswd &> /dev/null; then apt-get install -y apache2-utils; fi
    
    auth_file="/etc/nginx/.htpasswd_$domain"
    htpasswd -cb "$auth_file" "$user" "$pass"
    
    # Add auth_basic if not present
    if ! grep -q "auth_basic" "$conf"; then
        sed -i "/index index.php/a \    auth_basic \"Restricted Area\";\n    auth_basic_user_file $auth_file;" "$conf"
        nginx -t && systemctl reload nginx
        log_info "Đã bật mật khẩu bảo vệ cho $domain"
    else
        log_info "Cập nhật mật khẩu thành công (Config đã có sẵn)."
    fi
    pause
}

fix_permissions() {
    echo -e "1. Chọn Website cụ thể"
    echo -e "2. Fix tất cả (/var/www)"
    read -p "Chọn: " c
    
    if [[ "$c" == "1" ]]; then
        select_site || return
        target="/var/www/$SELECTED_DOMAIN"
    else
        target="/var/www"
    fi
    
    log_info "Đang thiết lập quyền chuẩn cho $target..."
    
    # REMOVE CONFLICTING CONFIGS (Critical for open_basedir errors)
    log_info "Đang xóa .user.ini và .htaccess để tránh conflict..."
    find "$target" -name ".user.ini" -delete 2>/dev/null
    find "$target" -name ".htaccess" -delete 2>/dev/null
    
    chown -R www-data:www-data "$target"
    find "$target" -type d -exec chmod 755 {} \;
    find "$target" -type f -exec chmod 644 {} \;
    
    log_info "Hoàn tất phân quyền."
    pause
}

check_wp_core() {
    select_site || return
    domain="$SELECTED_DOMAIN"
    
    echo -e "${YELLOW}--- Kiểm tra & Sửa lỗi WordPress Core ---${NC}"
    echo -e "Tính năng này sẽ tải lại bộ mã nguồn gốc của WordPress (wp-admin, wp-includes) để sửa lỗi thiếu file."
    echo -e "Các file config, wp-content (themes, plugins, uploads) sẽ KHÔNG bị ảnh hưởng."
    echo -e "${RED}Lưu ý: Nếu bạn đã sửa core WP (không khuyến khích), các thay đổi sẽ mất.${NC}"
    
    read -p "Tiếp tục? (y/n): " c
    if [[ "$c" != "y" ]]; then return; fi
    
    log_info "Đang tải WordPress Core mới nhất..."
    
    cd "/var/www/$domain/public_html"
    
    # Download
    wget -q https://wordpress.org/latest.tar.gz
    if [ ! -f latest.tar.gz ]; then
        log_error "Tải thất bại. Kiểm tra kết nối mạng."
        return
    fi
    
    tar -xzf latest.tar.gz
    
    log_info "Đang cập nhật Core Files..."
    
    # Copy core files, overwrite existing
    cp -r wordpress/* .
    
    # Clean up
    rm -rf wordpress latest.tar.gz
    
    # Fix permissions
    chown -R www-data:www-data .
    find . -type d -exec chmod 755 {} \;
    find . -type f -exec chmod 644 {} \;
    
    # Delete potentially dangerous cached configs if any
    rm -f .htaccess .user.ini
    
    
    log_info "Hoàn tất! Hãy thử truy cập lại website."
    pause
}

toggle_site_cache() {
    echo -e "${YELLOW}--- Bật/Tắt FastCGI Cache (Dev Mode) ---${NC}"
    echo -e "Chế độ Dev Mode sẽ buộc Nginx bỏ qua cache hoàn toàn cho website này."
    echo -e "Rất hữu ích khi bạn đang thiết kế hoặc chỉnh sửa code."
    
    select_site || return
    local domain="$SELECTED_DOMAIN"
    local conf="/etc/nginx/sites-available/$domain"
    
    if [ ! -f "$conf" ]; then 
        echo -e "${RED}Config Nginx không tồn tại: $conf${NC}"
        pause; return 
    fi
    
    # Kiểm tra trạng thái hiện tại
    if grep -q "set \$skip_cache 1; # DEV_MODE_ACTIVE" "$conf"; then
        echo -e "Trạng thái FastCGI Cache: ${RED}ĐANG TẮT (Dev Mode)${NC}"
        read -p "Bạn muốn BẬT LẠI cache không? (y/n): " c
        if [[ "$c" == "y" || "$c" == "Y" ]]; then
            sed -i 's/set \$skip_cache 1; # DEV_MODE_ACTIVE/set \$skip_cache 0;/' "$conf"
            nginx -t && systemctl reload nginx
            log_info "Đã BẬT LẠI Cache cho $domain. Web sẽ load nhanh như chớp!"
        fi
    elif grep -q "set \$skip_cache 0;" "$conf"; then
        echo -e "Trạng thái FastCGI Cache: ${GREEN}ĐANG BẬT (Production Mode)${NC}"
        read -p "Bạn muốn TẮT cache (chuyển sang Dev Mode) không? (y/n): " c
        if [[ "$c" == "y" || "$c" == "Y" ]]; then
            sed -i 's/set \$skip_cache 0;/set \$skip_cache 1; # DEV_MODE_ACTIVE/' "$conf"
            
            # Xóa sạch array cache local để chắc chắn thay đổi áp dụng liền
            rm -rf /var/run/nginx-cache/* 2>/dev/null
            
            nginx -t && systemctl reload nginx
            log_info "Đã TẮT Cache cho $domain. Phù hợp để chỉnh sửa code/giao diện."
        fi
    else
        echo -e "${RED}Không tìm thấy cấu hình \$skip_cache trong file config của Nginx!${NC}"
        echo -e "Bạn có thể thử dùng tính năng '14. Cấu hình lại Nginx (Rewrite Vhost)' để thiết lập lại file chuẩn."
    fi
    
    pause
}
