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
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-12]: " choice

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
        install_wordpress "$domain"
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
    
    # Detect PHP Version Socket
    if [ -S /run/php/php8.3-fpm.sock ]; then
        php_sock="unix:/run/php/php8.3-fpm.sock"
    elif [ -S /run/php/php8.2-fpm.sock ]; then
        php_sock="unix:/run/php/php8.2-fpm.sock"
    elif [ -S /run/php/php8.1-fpm.sock ]; then
        php_sock="unix:/run/php/php8.1-fpm.sock"
    else
        # Default fallback
        php_sock="unix:/run/php/php8.1-fpm.sock"
    fi

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
        fastcgi_pass $php_sock;
        
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
    echo -e "${GREEN}Danh sách các website có thể xóa:${NC}"
    
    # Get all directories in /var/www/
    sites=()
    i=1
    for dir in /var/www/*; do
        if [ -d "$dir" ]; then
            domain=$(basename "$dir")
            # Filter out html or default if necessary, generally we keep user created ones
            if [[ "$domain" != "html" ]]; then
                sites+=("$domain")
                echo -e "$i. $domain"
                ((i++))
            fi
        fi
    done
    
    if [ ${#sites[@]} -eq 0 ]; then
        echo -e "${YELLOW}Không tìm thấy website nào.${NC}"
        pause
        return
    fi
    
    echo -e "0. Quay lại"
    read -p "Chọn website cần xóa [1-${#sites[@]}]: " choice
    
    if [[ "$choice" == "0" || -z "$choice" ]]; then
        return
    fi
    
    # Validate selection
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#sites[@]}" ]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
        pause
        return
    fi
    
    # Get domain from array (index start at 0, so choice-1)
    domain="${sites[$((choice-1))]}"
    
    echo -e "${RED}CẢNH BÁO: Hành động này sẽ xóa toàn bộ mã nguồn và cơ sở dữ liệu của $domain!${NC}"
    read -p "Bạn có CHẮC CHẮN muốn xóa $domain không? (nhập 'y' để đồng ý): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Đã hủy thao tác xóa.${NC}"
        pause
        return
    fi

    log_info "Đang xóa website $domain..."

    # Remove files
    rm -rf "/var/www/$domain"
    
    # Remove Nginx config
    rm -f "/etc/nginx/sites-available/$domain"
    rm -f "/etc/nginx/sites-enabled/$domain"
    systemctl reload nginx

    # Drop DB
    local db_name=$(echo "$domain" | tr -d '.')
    local db_user="${db_name}_user"
    
    # Check if mysql command works (might need password if not configured for root socket auth)
    if command -v mysql &> /dev/null; then
        mysql -e "DROP DATABASE IF EXISTS ${db_name};" 2>/dev/null
        mysql -e "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null
        mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    fi

    log_info "Đã xóa hoàn toàn website $domain."
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
        sed -i "s/DB_NAME', '.*'/DB_NAME', '$new_db_name'/" wp-config.php
        sed -i "s/DB_USER', '.*'/DB_USER', '$new_db_user'/" wp-config.php
        sed -i "s/DB_PASSWORD', '.*'/DB_PASSWORD', '$new_db_pass'/" wp-config.php
        
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
    read -p "Nhập domain CŨ: " old_domain
    read -p "Nhập domain MỚI: " new_domain
    
    if [ ! -d "/var/www/$old_domain" ]; then echo -e "${RED}Không tìm thấy domain cũ.${NC}"; pause; return; fi
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
    read -p "Nhập domain cần cấu hình lại Nginx: " domain
    if [ ! -d "/var/www/$domain" ]; then echo -e "${RED}Site không tồn tại.${NC}"; pause; return; fi
    
    create_nginx_config "$domain"
    log_info "Đã tạo lại file cấu hình Nginx cho $domain."
    pause
}

change_site_php() {
    read -p "Nhập domain: " domain
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then echo -e "${RED}Config Nginx không tồn tại.${NC}"; pause; return; fi
    
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
    
    conf="/etc/nginx/sites-available/$domain"
    # Replace fastcgi_pass line
    sed -i "s|fastcgi_pass.*unix:.*|fastcgi_pass unix:/run/php/php$ver-fpm.sock;|" "$conf"
    
    nginx -t && systemctl reload nginx
    log_info "Đã chuyển $domain sang PHP $ver"
    pause
}

update_site_db_info() {
    read -p "Nhập domain: " domain
    wp_conf="/var/www/$domain/public_html/wp-config.php"
    if [ ! -f "$wp_conf" ]; then echo -e "${RED}Không tìm thấy wp-config.php${NC}"; pause; return; fi
    
    read -p "Database Name mới: " db_name
    read -p "Database User mới: " db_user
    read -p "Database Password mới: " db_pass
    
    sed -i "s/DB_NAME', '.*'/DB_NAME', '$db_name'/" "$wp_conf"
    sed -i "s/DB_USER', '.*'/DB_USER', '$db_user'/" "$wp_conf"
    sed -i "s/DB_PASSWORD', '.*'/DB_PASSWORD', '$db_pass'/" "$wp_conf"
    
    log_info "Đã cập nhật thông tin Database."
    pause
}

manage_parked_domains() {
    echo -e "1. Thêm Parked Domain (Alias)"
    echo -e "2. Xóa Parked Domain"
    read -p "Chọn: " c
    
    case $c in
        1)
            read -p "Domain GỐC (Main): " main
            read -p "Domain ALIAS (Parked): " alias
            conf="/etc/nginx/sites-available/$main"
            if [ ! -f "$conf" ]; then echo "${RED}Domain gốc sai.${NC}"; pause; return; fi
            
            # Edit server_name line to append alias
            # Assuming server_name line looks like "server_name a.com www.a.com;"
            if grep -q "server_name .*$alias" "$conf"; then
                echo "Alias đã tồn tại."
            else
                sed -i "/server_name/ s/;/ $alias www.$alias;/" "$conf"
                nginx -t && systemctl reload nginx
                log_info "Đã thêm alias $alias cho $main"
                
                # Setup SSL for alias if needed? 
                echo -e "${YELLOW}Lưu ý: Bạn cần cấp lại SSL để bao gồm cả domain alias!${NC}"
                # Could offer to run certbot --expand
            fi
            ;;
        2)
            read -p "Domain GỐC (Main): " main
            read -p "Domain ALIAS cần xóa: " alias
            conf="/etc/nginx/sites-available/$main"
            sed -i "s/ $alias//" "$conf"
            sed -i "s/ www.$alias//" "$conf"
            nginx -t && systemctl reload nginx
            log_info "Đã gỡ alias."
            ;;
    esac
    pause
}

protect_folder() {
    read -p "Nhập domain muốn đặt mật khẩu: " domain
    read -p "Username: " user
    read -p "Password: " pass
    
    if ! command -v htpasswd &> /dev/null; then apt-get install -y apache2-utils; fi
    
    auth_file="/etc/nginx/.htpasswd_$domain"
    htpasswd -cb "$auth_file" "$user" "$pass"
    
    conf="/etc/nginx/sites-available/$domain"
    # Insert auth_basic into the beginning of server block or / location
    # Simple approach: Auth whole site
    if ! grep -q "auth_basic" "$conf"; then
        # Insert after "index ..." line for example
        sed -i "/index index.php/a \    auth_basic \"Restricted Area\";\n    auth_basic_user_file $auth_file;" "$conf"
        nginx -t && systemctl reload nginx
        log_info "Đã bật mật khẩu bảo vệ cho $domain"
    else
        log_info "Cập nhật mật khẩu thành công (Config đã có sẵn)."
    fi
    pause
}
