#!/bin/bash

# modules/php.sh - Multi-PHP Version Management & Tuning

php_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🐘 Quản lý Đa phiên bản PHP${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài đặt thêm phiên bản PHP (7.4, 8.0, 8.1, 8.2, 8.3, 8.4)"
        echo -e "2. Thay đổi phiên bản PHP cho Website"
        echo -e "3. Kiểm tra các phiên bản PHP đang cài đặt"
        echo -e "4. ⚙️  Tinh chỉnh cấu hình PHP (php.ini: Upload, Memory, Timeout)"
        echo -e "5. 🗑️  Gỡ cài đặt (Uninstall) phiên bản PHP"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-5]: " choice

        case $choice in
            1) install_additional_php ;;
            2) 
                source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
                change_site_php 
                ;;
            3) list_php_versions ;;
            4) tune_php_ini ;;
            5) uninstall_php_version ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

install_additional_php() {
    local ver="$1"
    if [[ -z "$ver" ]]; then
        echo -e "Chọn phiên bản PHP muốn cài đặt:"
        echo -e "1) PHP 7.4 (Legacy - mã nguồn cũ)"
        echo -e "2) PHP 8.0"
        echo -e "3) PHP 8.1"
        echo -e "4) PHP 8.2"
        echo -e "5) PHP 8.3 (Ổn định)"
        echo -e "6) PHP 8.4 (Mới nhất)"
        read -p "Nhập lựa chọn [1-6]: " ver_choice

        case $ver_choice in
            1) ver="7.4" ;;
            2) ver="8.0" ;;
            3) ver="8.1" ;;
            4) ver="8.2" ;;
            5) ver="8.3" ;;
            6) ver="8.4" ;;
            *) echo -e "${RED}Phiên bản không hợp lệ!${NC}"; pause; return ;;
        esac
    fi

    if [[ "$OS_FAMILY" == "rhel" ]]; then
        local rhel_pkg="php${ver//./}-php-fpm"
        if is_installed "$rhel_pkg"; then
            echo -e "${YELLOW}PHP $ver đã được cài đặt.${NC}"
            pause
            return
        fi
        log_info "Đang cài đặt PHP $ver và các module phổ biến qua Remi..."
        pkg_install "php${ver//./}-php-fpm" "php${ver//./}-php-mysqlnd" "php${ver//./}-php-common" "php${ver//./}-php-cli" "php${ver//./}-php-gd" "php${ver//./}-php-mbstring" "php${ver//./}-php-xml" "php${ver//./}-php-pecl-zip"
        
        systemctl enable "php${ver//./}-php-fpm"
        systemctl start "php${ver//./}-php-fpm"
    else
        if is_installed "php$ver-fpm"; then
            echo -e "${YELLOW}PHP $ver đã được cài đặt.${NC}"
            pause
            return
        fi

        log_info "Đang cài đặt PHP $ver và các module phổ biến..."
        pkg_update
        pkg_install php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath php$ver-intl php$ver-gd php$ver-imagick
        
        # Check if redis/valkey module is installed
        if is_installed php-redis; then
            pkg_install php$ver-redis 2>/dev/null || true
        fi

        systemctl enable php$ver-fpm 2>/dev/null || true
        systemctl start php$ver-fpm 2>/dev/null || true
    fi

    # Áp cấu hình chuẩn upload & timeout cho phiên bản mới cài
    _apply_default_php_limits "$ver"

    log_info "Cài đặt PHP $ver thành công."
    pause
}

_apply_default_php_limits() {
    local ver="$1"
    local ini_path="/etc/php/$ver/fpm/php.ini"
    [[ "$OS_FAMILY" == "rhel" ]] && ini_path="/etc/opt/remi/php${ver//./}/php.ini"

    if [[ -f "$ini_path" ]]; then
        sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$ini_path"
        sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$ini_path"
        sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$ini_path"
        sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$ini_path"
        sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$ini_path"
        systemctl restart php$ver-fpm 2>/dev/null || systemctl restart php${ver//./}-php-fpm 2>/dev/null || true
    fi
}

list_php_versions() {
    echo -e "${GREEN}Các phiên bản PHP đã cài đặt trên VPS:${NC}"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        rpm -qa | grep -E "^php[0-9]+-php-fpm" | awk '{print $1}'
    else
        dpkg --get-selections | grep -E "php[0-9]\.[0-9]-fpm" | awk '{print $1}'
    fi
    echo ""
    echo -e "${CYAN}Phiên bản PHP CLI hiện tại:${NC} $(php -v 2>/dev/null | head -n 1)"
    pause
}

tune_php_ini() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    ⚙️  Tinh chỉnh Cấu hình PHP (php.ini)${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Liệt kê các version đang có
    local available_vers=()
    if [[ -d /etc/php ]]; then
        for p in /etc/php/*; do
            if [[ -d "$p" && -f "$p/fpm/php.ini" ]]; then
                available_vers+=($(basename "$p"))
            fi
        done
    fi

    if [[ ${#available_vers[@]} -eq 0 ]]; then
        # Check RHEL
        for v in 74 80 81 82 83 84; do
            if [[ -f "/etc/opt/remi/php$v/php.ini" ]]; then
                available_vers+=("${v:0:1}.${v:1:1}")
            fi
        done
    fi

    if [[ ${#available_vers[@]} -eq 0 ]]; then
        echo -e "${RED}Không tìm thấy file cấu hình php.ini nào! Vui lòng cài đặt PHP trước.${NC}"
        pause; return
    fi

    echo -e "Chọn phiên bản PHP muốn cấu hình:"
    local idx=1
    for v in "${available_vers[@]}"; do
        echo "$idx) PHP $v"
        ((idx++))
    done
    echo "a) Áp dụng cho TẤT CẢ phiên bản"
    echo "0) Quay lại"
    read -p "Chọn: " p_choice

    [[ "$p_choice" == "0" ]] && return

    local target_vers=()
    if [[ "$p_choice" == "a" || "$p_choice" == "A" ]]; then
        target_vers=("${available_vers[@]}")
    elif [[ "$p_choice" =~ ^[0-9]+$ ]] && [[ "$p_choice" -le ${#available_vers[@]} ]]; then
        target_vers=("${available_vers[$((p_choice-1))]}")
    else
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi

    # Display current settings from first selected version
    local sample_ini="/etc/php/${target_vers[0]}/fpm/php.ini"
    [[ "$OS_FAMILY" == "rhel" ]] && sample_ini="/etc/opt/remi/php${target_vers[0]//./}/php.ini"

    echo ""
    echo -e "${CYAN}Thông số hiện tại (PHP ${target_vers[0]}):${NC}"
    grep -E "^(upload_max_filesize|post_max_size|memory_limit|max_execution_time|max_input_vars)" "$sample_ini" 2>/dev/null
    echo -e "${BLUE}-------------------------------------------------${NC}"

    read -p "upload_max_filesize (ví dụ 128M, 256M, 512M) [Enter giữ nguyên]: " up_size
    read -p "post_max_size (thường bằng hoặc lớn hơn upload size) [Enter giữ nguyên]: " post_size
    read -p "memory_limit (ví dụ 256M, 512M, 1024M) [Enter giữ nguyên]: " mem_limit
    read -p "max_execution_time (giây, ví dụ 300, 600) [Enter giữ nguyên]: " max_time
    read -p "max_input_vars (ví dụ 3000, 5000) [Enter giữ nguyên]: " max_vars

    for v in "${target_vers[@]}"; do
        local cur_ini="/etc/php/$v/fpm/php.ini"
        local cur_svc="php$v-fpm"
        if [[ "$OS_FAMILY" == "rhel" ]]; then
            cur_ini="/etc/opt/remi/php${v//./}/php.ini"
            cur_svc="php${v//./}-php-fpm"
        fi

        if [[ -f "$cur_ini" ]]; then
            [[ -n "$up_size" ]] && sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = $up_size/" "$cur_ini"
            [[ -n "$post_size" ]] && sed -i -E "s/^[; ]*post_max_size.*/post_max_size = $post_size/" "$cur_ini"
            [[ -n "$mem_limit" ]] && sed -i -E "s/^[; ]*memory_limit.*/memory_limit = $mem_limit/" "$cur_ini"
            [[ -n "$max_time" ]] && sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = $max_time/" "$cur_ini"
            [[ -n "$max_vars" ]] && sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = $max_vars/" "$cur_ini"
            
            systemctl restart "$cur_svc" 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
            log_info "Đã cập nhật cấu hình và restart service: $cur_svc"
        fi
    done

    log_info "Hoàn tất tinh chỉnh php.ini!"
    pause
}

uninstall_php_version() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${RED}       🗑️  Gỡ cài đặt Phiên bản PHP${NC}"
    echo -e "${BLUE}=================================================${NC}"

    local installed_vers=()
    if [[ -d /etc/php ]]; then
        for p in /etc/php/*; do
            if [[ -d "$p" ]]; then
                installed_vers+=($(basename "$p"))
            fi
        done
    fi

    if [[ ${#installed_vers[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Không tìm thấy phiên bản PHP nào có thể gỡ.${NC}"
        pause; return
    fi

    echo -e "Chọn phiên bản PHP muốn GỠ BỎ:"
    local i=1
    for v in "${installed_vers[@]}"; do
        echo "$i) PHP $v"
        ((i++))
    done
    echo "0) Quay lại"
    read -p "Chọn: " del_choice

    [[ "$del_choice" == "0" || -z "$del_choice" ]] && return

    if ! [[ "$del_choice" =~ ^[0-9]+$ ]] || [[ "$del_choice" -gt ${#installed_vers[@]} ]]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi

    local target_ver="${installed_vers[$((del_choice-1))]}"

    # Check if any vhost is currently using this PHP version
    local using_sites
    using_sites=$(grep -rn "php${target_ver}-fpm" /etc/nginx/sites-available/ 2>/dev/null | awk -F: '{print $1}' | sort -u)
    if [[ -n "$using_sites" ]]; then
        echo -e "${RED}CẢNH BÁO: Phiên bản PHP $target_ver đang được sử dụng bởi các website sau:${NC}"
        echo "$using_sites"
        echo -e "${YELLOW}Nếu gỡ bỏ, các website trên sẽ bị lỗi 502 Bad Gateway!${NC}"
        read -p "Bạn có chắc chắn 100% muốn gỡ bỏ PHP $target_ver? [y/N]: " confirm_del
        [[ "$confirm_del" != "y" && "$confirm_del" != "Y" ]] && return
    else
        read -p "Xác nhận gỡ bỏ PHP $target_ver khỏi VPS? [y/N]: " confirm_del
        [[ "$confirm_del" != "y" && "$confirm_del" != "Y" ]] && return
    fi

    log_info "Đang dừng dịch vụ php$target_ver-fpm..."
    systemctl stop php$target_ver-fpm 2>/dev/null || true
    systemctl disable php$target_ver-fpm 2>/dev/null || true

    log_info "Đang gỡ bỏ các gói liên quan đến PHP $target_ver..."
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf remove -y "php${target_ver//./}*" 2>/dev/null || true
    else
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "php${target_ver}*" 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf "/etc/php/$target_ver" 2>/dev/null || true
    fi

    log_info "Đã gỡ bỏ hoàn toàn PHP $target_ver khỏi hệ thống."
    pause
}

