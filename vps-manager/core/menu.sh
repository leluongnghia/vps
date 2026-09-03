#!/bin/bash

# core/menu.sh - Main Menu (Standardized on Nginx & LEMP Stack)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$DIR")"

# Import utils
source "$ROOT_DIR/core/utils.sh"

_nginx_sub_menu() {
    source "$ROOT_DIR/modules/nginx.sh"
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}     🌐 Quản lý Nginx & LEMP Stack${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài đặt / Cài lại LEMP Stack (Nginx + MariaDB + PHP)"
        echo -e "2. Quản lý cấu hình Nginx (nginx.conf, Vhost, Cứu hộ config)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn [0-2]: " n_choice
        case $n_choice in
            1) install_nginx_stack_menu ;;
            2) nginx_menu ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

_nginx_main_menu() {
    local script_version="$1"
    local vps_ip="$2"

    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       VPS MANAGEMENT SCRIPT v${script_version}${NC}"
    echo -e "${YELLOW}       🌐 Stack: Nginx + MariaDB + PHP-FPM${NC}"
    echo -e "${YELLOW}       Server IP: ${vps_ip}${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e " 1.  🌐 Quản lý Nginx & LEMP Stack (Cài đặt, Vhost, Tinh chỉnh)"
    echo -e " 2.  🌍 Quản lý Domain & Website (WP, PHP, Node.js, Docker)"
    echo -e " 3.  🔧 Quản lý WordPress (User, Plugins, WP-CLI, Bảo mật)"
    echo -e " 4.  🚀 Tối ưu WordPress Performance (FastCGI Cache, OPcache, TBT)"
    echo -e " 5.  🐘 Quản lý Phiên bản PHP (Cài đặt, Gỡ bỏ, php.ini Limits)"
    echo -e " 6.  🗃️  Quản lý Database (MariaDB, User, phpMyAdmin, Tối ưu DB)"
    echo -e " 7.  ⚡ Quản lý Cache (Valkey, Redis, KeyDB, Memcached, FastCGI)"
    echo -e " 8.  🔒 Quản lý SSL (Let's Encrypt, Auto-Renew, ZeroSSL, Cloudflare)"
    echo -e " 9.  💾 Sao lưu & Khôi phục (Backup Local/GDrive, Auto Backup Cron)"
    echo -e " 10. 🛡️  Bảo mật & Tường lửa (UFW/Firewalld, Fail2ban, WAF 7G/8G, SSH)"
    echo -e " 11. 🧠 Quản lý Bộ nhớ ảo (ZRAM Swap nén siêu tốc & File Swap đĩa)"
    echo -e " 12. ⏰ Quản lý Cronjob (Lập lịch hệ thống, Real WP-Cron, APRG Cron)"
    echo -e " 13. 💿 Quản lý Ổ đĩa & Logs (Quét file >100MB, Logrotate chống tràn)"
    echo -e " 14. 🔄 Quản lý Dịch vụ Hệ thống (Restart, Reload, Stop, Status)"
    echo -e " 15. 🏥 Chẩn đoán Hệ thống (Health Check, Port đang mở, Hạn SSL)"
    echo -e " 16. 🛠️  Công cụ Bổ trợ & AppAdmin (Tối ưu ảnh WebP, HTTP Auth)"
    echo -e " 17. 🛡️  Watchdog Giám sát Dịch vụ (Monit - Auto Recovery)"
    echo -e " 18. 🔄 Cập nhật VPS Manager (Đồng bộ từ GitHub)"
    echo -e " 0.  🚪 Thoát"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-18]: " choice

    case $choice in
        1)  _nginx_sub_menu ;;
        2)  source "$ROOT_DIR/modules/site.sh";                  manage_sites_menu     ;;
        3)  source "$ROOT_DIR/modules/wordpress_tool.sh";        wp_tool_menu          ;;
        4)  source "$ROOT_DIR/modules/wordpress_performance.sh"; wp_performance_menu  ;;
        5)  source "$ROOT_DIR/modules/php.sh";                   php_menu              ;;
        6)  source "$ROOT_DIR/modules/database.sh";              database_menu         ;;
        7)  source "$ROOT_DIR/modules/cache.sh";                 cache_menu            ;;
        8)  source "$ROOT_DIR/modules/ssl.sh";                   ssl_menu              ;;
        9)  source "$ROOT_DIR/modules/backup.sh";                backup_menu           ;;
        10) source "$ROOT_DIR/modules/security.sh";              security_menu         ;;
        11) source "$ROOT_DIR/modules/swap.sh";                  swap_menu             ;;
        12) source "$ROOT_DIR/modules/cron.sh";                  cron_menu             ;;
        13) source "$ROOT_DIR/modules/disk.sh";                  disk_menu             ;;
        14) source "$ROOT_DIR/modules/service.sh";               service_menu          ;;
        15) source "$ROOT_DIR/modules/diagnose.sh";              diagnose_system       ;;
        16) source "$ROOT_DIR/modules/appadmin.sh";              appadmin_menu         ;;
        17) source "$ROOT_DIR/modules/monit.sh";                 monit_menu            ;;
        18) source "$ROOT_DIR/modules/update.sh";                do_update             ;;
        0)  echo -e "${GREEN}Exiting... Goodbye!${NC}"; exit 0 ;;
        *)  echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
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

    while true; do
        _nginx_main_menu "$script_version" "$vps_ip"
    done
}

