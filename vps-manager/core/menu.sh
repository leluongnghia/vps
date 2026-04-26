#!/bin/bash

# core/menu.sh - Main Menu (Dynamic — Nginx or OpenLiteSpeed)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$DIR")"

# Import utils
source "$ROOT_DIR/core/utils.sh"

# Import Dashboard
if [[ -f "$ROOT_DIR/core/dashboard.sh" ]]; then
    source "$ROOT_DIR/core/dashboard.sh"
fi

# ==============================================================================
# Stack Detection
# ==============================================================================

VPS_STACK_CONF="$HOME/.vps-manager/stack.conf"

# Ghi nhớ stack đã chọn (gọi từ install-nginx.sh / install-ols.sh)
save_active_stack() {
    local stack="$1"  # "nginx" | "ols"
    mkdir -p "$HOME/.vps-manager"
    echo "ACTIVE_STACK=${stack}" > "$VPS_STACK_CONF"
}

# Detect stack đang active (ưu tiên file config, fallback theo service)
detect_active_stack() {
    # 1. Đọc từ file config (được ghi khi cài)
    if [[ -f "$VPS_STACK_CONF" ]]; then
        local saved_stack
        saved_stack=$(grep "^ACTIVE_STACK=" "$VPS_STACK_CONF" 2>/dev/null | cut -d= -f2)
        if [[ "$saved_stack" == "ols" || "$saved_stack" == "nginx" ]]; then
            echo "$saved_stack"
            return
        fi
    fi

    # 2. Fallback: detect theo service đang chạy
    if systemctl is-active --quiet lshttpd 2>/dev/null; then
        echo "ols"
    elif systemctl is-active --quiet nginx 2>/dev/null; then
        echo "nginx"
    # 3. Detect theo binary đã cài (dù service chưa start)
    elif [[ -f /usr/local/lsws/bin/lshttpd ]]; then
        echo "ols"
    elif command -v nginx &>/dev/null; then
        echo "nginx"
    else
        echo "nginx"  # default
    fi
}

# ==============================================================================
# Shared Case Handler (items giống nhau ở cả 2 menu)
# ==============================================================================

_handle_common_choice() {
    local choice="$1"
    case $choice in
        2)  source "$ROOT_DIR/modules/site.sh";              manage_sites_menu     ;;
        3)  source "$ROOT_DIR/modules/wordpress_tool.sh";    wp_tool_menu          ;;
        4)  source "$ROOT_DIR/modules/security.sh";          security_menu         ;;
        5)  source "$ROOT_DIR/modules/backup.sh";            backup_menu           ;;
        6)  source "$ROOT_DIR/modules/php.sh";               php_menu              ;;
        7)  source "$ROOT_DIR/modules/cron.sh";              cron_menu             ;;
        8)  source "$ROOT_DIR/modules/service.sh";           service_menu          ;;
        9)  source "$ROOT_DIR/modules/database.sh";          database_menu         ;;
        10) source "$ROOT_DIR/modules/cache.sh";             cache_menu            ;;
        11) source "$ROOT_DIR/modules/swap.sh";              swap_menu             ;;
        12) source "$ROOT_DIR/modules/disk.sh";              disk_menu             ;;
        13) source "$ROOT_DIR/modules/appadmin.sh";          appadmin_menu         ;;
        15) source "$ROOT_DIR/modules/update.sh";            do_update             ;;
        16) source "$ROOT_DIR/modules/diagnose.sh";          diagnose_system       ;;
        17) source "$ROOT_DIR/modules/wordpress_performance.sh"; wp_performance_menu ;;
        18) source "$ROOT_DIR/modules/phpmyadmin.sh";        phpmyadmin_menu       ;;
        19) source "$ROOT_DIR/modules/ssl.sh";               ssl_menu              ;;
        20) source "$ROOT_DIR/modules/backup.sh";            auto_backup_menu      ;;
        22) source "$ROOT_DIR/modules/zram.sh";              zram_menu             ;;
        23) source "$ROOT_DIR/modules/monit.sh";             monit_menu            ;;
        24) source "$ROOT_DIR/modules/switch.sh";            switch_webserver_menu ;;
        0)  echo -e "${GREEN}Exiting... Goodbye!${NC}"; exit 0 ;;
        *)  echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

# ==============================================================================
# Menu khi dùng Nginx Stack
# ==============================================================================

_nginx_main_menu() {
    local script_version="$1"
    local vps_ip="$2"

    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       VPS MANAGEMENT SCRIPT v${script_version}${NC}"
    echo -e "${YELLOW}       🌐 Stack: Nginx + MariaDB + PHP-FPM${NC}"
    echo -e "${YELLOW}       Server IP: ${vps_ip}${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1.  🌐 Cài đặt / Quản lý LEMP Stack (Nginx)"
    echo -e "2.  🌍 Quản lý Domain & Website"
    echo -e "3.  🔧 Quản lý WordPress (User, Plugins, Security...)"
    echo -e "4.  🛡️  Bảo mật & Tối ưu hóa"
    echo -e "5.  💾 Sao lưu & Khôi phục (Backup/Restore)"
    echo -e "6.  🐘 Quản lý Phiên bản PHP"
    echo -e "7.  ⏰ Quản lý Cronjob (Lịch biểu)"
    echo -e "8.  🔄 Quản lý Services (Khởi động lại/Stop)"
    echo -e "9.  🗃️  Quản lý Database (Cơ sở dữ liệu)"
    echo -e "10. ⚡ Quản lý Cache (Valkey/Redis/FastCGI)"
    echo -e "11. 🧠 Quản lý Swap (RAM ảo - File Swap)"
    echo -e "12. 💿 Quản lý Ổ đĩa & Dọn dẹp Logs"
    echo -e "13. 🛠️  AppAdmin & Công cụ bổ trợ"
    echo -e "14. ⚙️  Quản lý Nginx (nginx.conf / Vhost / Fix)"
    echo -e "15. 🔄 Cập nhật Script (Từ GitHub)"
    echo -e "16. 🏥 Chẩn đoán Hệ thống (Health Check)"
    echo -e "17. 🚀 Tối ưu WordPress Performance (Chuyên sâu)"
    echo -e "18. 🗄️  Quản lý phpMyAdmin"
    echo -e "19. 🔒 Quản lý SSL (Let's Encrypt / Renew)"
    echo -e "20. ⏰ Backup Tự động (Auto Backup Cron)"
    echo -e "${YELLOW}21. ⚡ Cài đặt & Quản lý OpenLiteSpeed (Chuyển stack)${NC}"
    echo -e "22. ⚡ ZRAM Swap (Swap nén trên RAM - Nhanh x1000)"
    echo -e "23. 🛡️  Watchdog Giám sát Dịch vụ (Monit)"
    echo -e "24. 🔄 Di chuyển Máy chủ Web (Nginx <==> OLS)"
    echo -e "0.  🚪 Thoát"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-24]: " choice

    case $choice in
        1)  # Nginx Stack menu
            source "$ROOT_DIR/modules/nginx.sh"
            install_nginx_stack_menu
            ;;
        14) # Nginx config management
            source "$ROOT_DIR/modules/nginx.sh"
            nginx_menu
            ;;
        21) # OLS — ít dùng hơn khi đang chạy Nginx
            source "$ROOT_DIR/modules/ols.sh"
            source "$ROOT_DIR/modules/lemp.sh"
            ols_menu
            ;;
        *)  _handle_common_choice "$choice" ;;
    esac
}

# ==============================================================================
# Menu khi dùng OpenLiteSpeed Stack
# ==============================================================================

_ols_main_menu() {
    local script_version="$1"
    local vps_ip="$2"

    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       VPS MANAGEMENT SCRIPT v${script_version}${NC}"
    echo -e "${YELLOW}       ⚡ Stack: OpenLiteSpeed + LSPHP + LSCache${NC}"
    echo -e "${YELLOW}       Server IP: ${vps_ip}${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1.  ⚡ Cài đặt & Quản lý OpenLiteSpeed (OLS + LSCache + LSPHP)"
    echo -e "2.  🌍 Quản lý Domain & Website"
    echo -e "3.  🔧 Quản lý WordPress (User, Plugins, Security...)"
    echo -e "4.  🛡️  Bảo mật & Tối ưu hóa"
    echo -e "5.  💾 Sao lưu & Khôi phục (Backup/Restore)"
    echo -e "6.  🐘 Quản lý Phiên bản LSPHP"
    echo -e "7.  ⏰ Quản lý Cronjob (Lịch biểu)"
    echo -e "8.  🔄 Quản lý Services (Khởi động lại/Stop)"
    echo -e "9.  🗃️  Quản lý Database (Cơ sở dữ liệu)"
    echo -e "10. ⚡ Quản lý Cache (Valkey/Redis/LSCache)"
    echo -e "11. 🧠 Quản lý Swap (RAM ảo - File Swap)"
    echo -e "12. 💿 Quản lý Ổ đĩa & Dọn dẹp Logs"
    echo -e "13. 🛠️  AppAdmin & Công cụ bổ trợ"
    echo -e "14. ⚡ Quản lý LSCache (Bật/Tắt/Purge/Plugin)"
    echo -e "15. 🔄 Cập nhật Script (Từ GitHub)"
    echo -e "16. 🏥 Chẩn đoán Hệ thống (Health Check)"
    echo -e "17. 🚀 Tối ưu WordPress Performance (Chuyên sâu)"
    echo -e "18. 🗄️  Quản lý phpMyAdmin"
    echo -e "19. 🔒 Quản lý SSL (Let's Encrypt / Renew)"
    echo -e "20. ⏰ Backup Tự động (Auto Backup Cron)"
    echo -e "${YELLOW}21. 🌐 Cài đặt LEMP Stack Nginx (Chuyển stack)${NC}"
    echo -e "22. ⚡ ZRAM Swap (Swap nén trên RAM - Nhanh x1000)"
    echo -e "23. 🛡️  Watchdog Giám sát Dịch vụ (Monit)"
    echo -e "24. 🔄 Di chuyển Máy chủ Web (Nginx <==> OLS)"
    echo -e "0.  🚪 Thoát"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-24]: " choice

    case $choice in
        1)  # OLS full menu
            source "$ROOT_DIR/modules/ols.sh"
            source "$ROOT_DIR/modules/lemp.sh"
            ols_menu
            ;;
        14) # LSCache management (thay Nginx config)
            source "$ROOT_DIR/modules/ols.sh"
            lscache_menu
            ;;
        21) # Nginx LEMP — ít dùng hơn khi đang chạy OLS
            source "$ROOT_DIR/modules/nginx.sh"
            install_nginx_stack_menu
            ;;
        *)  _handle_common_choice "$choice" ;;
    esac
}

# ==============================================================================
# Main Entry Point
# ==============================================================================

main_menu() {
    local script_version="1.0.0"
    if [[ -f "$ROOT_DIR/VERSION" ]]; then
        script_version=$(cat "$ROOT_DIR/VERSION")
    fi

    # Lấy IP của VPS
    local vps_ip
    vps_ip=$(curl -s -m 3 ifconfig.me 2>/dev/null || curl -s -m 3 ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    [[ -z "$vps_ip" ]] && vps_ip="Unknown"

    # Detect stack một lần duy nhất trước vòng lặp
    local active_stack
    active_stack=$(detect_active_stack)

    while true; do
        # Hiển thị Real-time Dashboard trước menu
        if type run_dashboard &>/dev/null; then
            run_dashboard
        fi

        # Re-detect stack mỗi vòng (để phản ánh sau khi switch)
        active_stack=$(detect_active_stack)

        if [[ "$active_stack" == "ols" ]]; then
            _ols_main_menu "$script_version" "$vps_ip"
        else
            _nginx_main_menu "$script_version" "$vps_ip"
        fi
    done
}
