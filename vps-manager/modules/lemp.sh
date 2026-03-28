#!/bin/bash

# modules/lemp.sh - LEMP Stack Installation

install_lemp_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          LEMP Stack Installation${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Install Full LEMP Stack (Recommended)"
    echo -e "2. Install Nginx Only"
    echo -e "3. Install MariaDB Only"
    echo -e "4. Install PHP Only"
    echo -e "5. Fix PHP Extensions (DOM/XML/MBSTRING/CLI symlinks)"
    echo -e "0. Back to Main Menu"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Enter your choice [0-5]: " choice

    case $choice in
        1)
            install_nginx
            install_mariadb
            install_php
            
            # Auto-install phpMyAdmin
            if [[ -f "$ROOT_DIR/modules/phpmyadmin.sh" ]]; then
                log_info "Tự động cài đặt phpMyAdmin..."
                source "$ROOT_DIR/modules/phpmyadmin.sh"
                install_phpmyadmin
            elif [[ -f "modules/phpmyadmin.sh" ]]; then
                log_info "Tự động cài đặt phpMyAdmin..."
                source "modules/phpmyadmin.sh"
                install_phpmyadmin
            fi
            
            # Hỗ trợ lựa chọn Object Cache (Valkey / Redis)
            echo ""
            echo -e "${YELLOW}Bạn có muốn cài đặt Memory Cache (Valkey/Redis) cho Server không?${NC}"
            echo -e "1. Valkey (Khuyên dùng - Nhanh hơn, thay thế Redis 100%)"
            echo -e "2. Redis (Truyền thống)"
            echo -e "0. Bỏ qua"
            read -p "Chọn [0-2]: " cache_choice
            
            if [[ "$cache_choice" == "1" || "$cache_choice" == "2" ]]; then
                if [[ -f "$ROOT_DIR/modules/wordpress_performance.sh" ]]; then
                    source "$ROOT_DIR/modules/wordpress_performance.sh"
                else
                    source "modules/wordpress_performance.sh" 2>/dev/null
                fi
                if [[ "$cache_choice" == "1" ]]; then
                     install_valkey
                else
                     install_redis
                fi
            fi
            
            pause
            ;;
        2)
            install_nginx
            pause
            ;;
        3)
            install_mariadb
            pause
            ;;
        4)
            install_php
            pause
            ;;
        5)
            fix_php_extensions
            pause
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            pause
            ;;
    esac
}

install_nginx() {
    if is_installed nginx; then
        log_warn "Nginx is already installed."
    else
        log_info "Installing Nginx..."
        pkg_update
        pkg_install nginx
        
        # Increase global upload limit right after install
        if [[ -f /etc/nginx/nginx.conf ]]; then
            sed -i '/http {/a \        client_max_body_size 128M;' /etc/nginx/nginx.conf
        fi
        
        systemctl enable nginx
        systemctl start nginx
        log_info "Nginx installed successfully."
    fi
}

install_mariadb() {
    if is_installed mariadb-server; then
        log_warn "MariaDB is already installed."
    else
        log_info "Installing MariaDB..."
        pkg_install mariadb-server
        systemctl enable mariadb
        systemctl start mariadb
        
        # Tự động tạo mật khẩu root an toàn và cấu hình
        local root_pass
        root_pass=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
        
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}';"
        mysql -e "DELETE FROM mysql.user WHERE User='';"
        mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        mysql -e "DROP DATABASE IF EXISTS test;"
        mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
        mysql -e "FLUSH PRIVILEGES;"
        
        # Lưu vào .my.cnf
        echo -e "[client]\nuser=root\npassword=\"${root_pass}\"" > /root/.my.cnf
        chmod 600 /root/.my.cnf
        
        log_info "MariaDB installed and secured! Tự động tạo cấu hình Root."
    fi
}

install_php() {
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        log_info "Adding PHP repository (Remi/EPEL)..."
        pkg_install epel-release dnf-utils >/dev/null 2>&1
        dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm >/dev/null 2>&1
        dnf module reset php -y >/dev/null 2>&1
    else
        log_info "Adding PHP repository (ondrej/php)..."
        pkg_install software-properties-common >/dev/null 2>&1
        add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
        pkg_update >/dev/null 2>&1
    fi

    local primary_ver="8.3"
    
    if [[ -n "$1" ]]; then
        primary_ver="$1"
    else
        echo -e "${YELLOW}Cài đặt PHP (Mặc định: PHP 8.3)${NC}"
    fi

    _install_single_php "$primary_ver"

    # Chỉ hỏi cài thêm nếu không điền tham số (khi chạy menu tương tác)
    if [[ -z "$1" ]]; then
        echo ""
        read -p "Bạn có muốn cài thêm phiên bản PHP phụ không? [y/N]: " install_more
        if [[ "$install_more" == "y" || "$install_more" == "Y" ]]; then
            echo -e "Chọn phiên bản PHP muốn cài thêm:"
            echo -e "1. PHP 8.1"
            echo -e "2. PHP 8.2"
            echo -e "3. PHP 8.4"
            echo -e "0. Bỏ qua"
            read -p "Chọn [0-3]: " extra_choice
            case $extra_choice in
                1) _install_single_php "8.1" ;;
                2) _install_single_php "8.2" ;;
                3) _install_single_php "8.4" ;;
                *) echo "Đã bỏ qua cài thêm PHP phụ." ;;
            esac
        fi
    fi
}

_install_single_php() {
    local ver=$1
    log_info "Installing PHP $ver..."
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf module enable php:remi-$ver -y >/dev/null 2>&1
        pkg_install php-fpm php-mysqlnd php-common php-cli \
            php-curl php-xml php-mbstring php-zip php-bcmath \
            php-intl php-gd php-pecl-imagick

        local php_ini="/etc/php.ini"
        if [[ -f "$php_ini" ]]; then
            sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
            sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
            sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
        fi

        local pool_conf="/etc/php-fpm.d/www.conf"
        if [[ -f "$pool_conf" ]]; then
            sed -i 's/^user = apache/user = nginx/' "$pool_conf"
            sed -i 's/^group = apache/group = nginx/' "$pool_conf"
            sed -i 's/^listen.owner = nobody/listen.owner = nginx/' "$pool_conf"
            sed -i 's/^listen.group = nobody/listen.group = nginx/' "$pool_conf"
        fi

        systemctl enable php-fpm >/dev/null 2>&1
        systemctl start php-fpm >/dev/null 2>&1
    else
        pkg_install php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli \
            php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath \
            php$ver-intl php$ver-gd php$ver-imagick

        # Configure PHP Upload Limits
        local php_ini="/etc/php/$ver/fpm/php.ini"
        if [[ -f "$php_ini" ]]; then
            sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
            sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
            sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
        fi

        systemctl enable php$ver-fpm >/dev/null 2>&1
        systemctl start php$ver-fpm >/dev/null 2>&1

        # Verify & auto-fix DOM/XML symlinks cho cả FPM và CLI
        _fix_php_ext_symlinks "$ver"
    fi

    log_info "PHP $ver installed successfully."
}

# Fix symlinks cho các PHP extension quan trọng (dom, xml, mbstring, ...)
# Đảm bảo cả CLI và FPM đều load đúng extension
_fix_php_ext_symlinks() {
    local ver=$1
    local mods_dir="/etc/php/$ver/mods-available"
    local fixed=0

    if [[ ! -d "$mods_dir" ]]; then
        log_warn "PHP $ver mods-available không tồn tại, bỏ qua."
        return
    fi

    # Danh sách extension quan trọng cần đảm bảo có trong cả CLI & FPM
    local critical_exts=("dom" "xml" "simplexml" "xmlreader" "xmlwriter" "mbstring" "curl")

    for ext in "${critical_exts[@]}"; do
        local ini_file="$mods_dir/${ext}.ini"
        [[ ! -f "$ini_file" ]] && continue  # Extension chưa được cài, bỏ qua

        for sapi in cli fpm; do
            local conf_dir="/etc/php/$ver/$sapi/conf.d"
            [[ ! -d "$conf_dir" ]] && continue

            # Tìm symlink hiện có (ví dụ: 20-dom.ini)
            local symlink
            symlink=$(find "$conf_dir" -name "*-${ext}.ini" 2>/dev/null | head -1)

            if [[ -z "$symlink" ]]; then
                # Symlink bị thiếu → tạo mới với priority 20
                ln -s "$ini_file" "$conf_dir/20-${ext}.ini" 2>/dev/null
                log_info "  [PHP $ver $sapi] Đã tạo symlink: 20-${ext}.ini"
                fixed=$((fixed + 1))
            fi
        done
    done

    if [[ $fixed -gt 0 ]]; then
        # Restart FPM để apply thay đổi
        systemctl restart php$ver-fpm >/dev/null 2>&1 && \
            log_info "PHP $ver FPM restarted để apply extension mới."
    fi
}

# Fix tất cả PHP versions đã cài trên server
fix_php_extensions() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}   Fix PHP Extensions (DOM/XML/MBSTRING/CLI symlinks)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Đang kiểm tra tất cả PHP versions..."
    echo ""

    if [[ ! -d /etc/php ]]; then
        log_warn "Không tìm thấy /etc/php. PHP chưa được cài?"
        return
    fi

    local versions=()
    for ver_dir in /etc/php/*/; do
        local ver
        ver=$(basename "$ver_dir")
        versions+=("$ver")
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_warn "Không tìm thấy PHP version nào."
        return
    fi

    echo -e "Tìm thấy ${#versions[@]} PHP version(s): ${versions[*]}"
    echo ""

    for ver in "${versions[@]}"; do
        echo -e "${YELLOW}--- PHP $ver ---${NC}"

        # Kiểm tra php-xml đã cài chưa, nếu chưa thì cài
        if [[ ! -f "/etc/php/$ver/mods-available/dom.ini" ]]; then
            log_info "PHP $ver: php${ver}-xml chưa được cài. Đang cài..."
            pkg_install php${ver}-xml >/dev/null 2>&1 && \
                log_info "PHP $ver: Đã cài php${ver}-xml thành công." || \
                log_warn "PHP $ver: Không thể cài php${ver}-xml (version không hỗ trợ?)"
        else
            echo -e "  ${GREEN}✓${NC} php${ver}-xml đã được cài."
        fi

        # Kiểm tra php-mbstring đã cài chưa, nếu chưa thì cài
        if [[ ! -f "/etc/php/$ver/mods-available/mbstring.ini" ]]; then
            log_info "PHP $ver: php${ver}-mbstring chưa được cài. Đang cài..."
            pkg_install php${ver}-mbstring >/dev/null 2>&1 && \
                log_info "PHP $ver: Đã cài php${ver}-mbstring thành công." || \
                log_warn "PHP $ver: Không thể cài php${ver}-mbstring (version không hỗ trợ?)"
        else
            echo -e "  ${GREEN}✓${NC} php${ver}-mbstring đã được cài."
        fi

        # Fix symlinks
        _fix_php_ext_symlinks "$ver"

        # Verify kết quả
        local cli_dom
        cli_dom=$(php$ver -m 2>/dev/null | grep -c "^dom$" || true)
        if [[ "$cli_dom" -ge 1 ]]; then
            echo -e "  ${GREEN}✓${NC} PHP $ver CLI: dom extension OK"
        else
            echo -e "  ${RED}✗${NC} PHP $ver CLI: dom extension vẫn thiếu!"
        fi

        local cli_mbstring
        cli_mbstring=$(php$ver -m 2>/dev/null | grep -c "^mbstring$" || true)
        if [[ "$cli_mbstring" -ge 1 ]]; then
            echo -e "  ${GREEN}✓${NC} PHP $ver CLI: mbstring extension OK"
        else
            echo -e "  ${RED}✗${NC} PHP $ver CLI: mbstring extension vẫn thiếu!"
        fi
    done

    echo ""
    echo -e "${GREEN}Hoàn tất kiểm tra và fix PHP extensions!${NC}"
}
