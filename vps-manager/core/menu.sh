#!/bin/bash

# core/menu.sh - Main Menu

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$DIR")"

# Import utils
source "$ROOT_DIR/core/utils.sh"

main_menu() {
    local script_version="1.0.0"
    if [[ -f "$ROOT_DIR/VERSION" ]]; then
        script_version=$(cat "$ROOT_DIR/VERSION")
    fi

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          VPS MANAGEMENT SCRIPT v${script_version}${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài đặt LEMP Stack (Nginx, MariaDB, PHP)"
        echo -e "2. Quản lý Domain & Website"
        echo -e "3. Quản lý WordPress (User, Plugins, Security...)"
        echo -e "4. Bảo mật & Tối ưu hóa"
        echo -e "5. Sao lưu & Khôi phục (Backup/Restore)"
        echo -e "6. Quản lý Phiên bản PHP"
        echo -e "7. Quản lý Cronjob (Lịch biểu)"
        echo -e "8. Quản lý Services (Khởi động lại/Stop)"
        echo -e "9. Quản lý Database (Cơ sở dữ liệu)"
        echo -e "10. Quản lý Cache (Redis/FastCGI)"
        echo -e "11. Quản lý Swap (RAM ảo)"
        echo -e "12. Quản lý Ổ đĩa & Dọn dẹp Logs"
        echo -e "13. AppAdmin & Công cụ bổ trợ"
        echo -e "14. Quản lý Nginx (Cấu hình)"
        echo -e "15. Cập nhật Script (Từ GitHub)"
        echo -e "16. Chẩn đoán Hệ thống (Health Check)"
        echo -e "17. 🚀 Tối ưu WordPress Performance (Chuyên sâu)"
        echo -e "18. 🗄️  Quản lý phpMyAdmin"
        echo -e "19. 🔒 Quản lý SSL (Let's Encrypt / Renew)"
        echo -e "20. ⏰ Backup Tự động (Auto Backup Cron)"
        echo -e "0. Thoát"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn của bạn [0-20]: " choice

        case $choice in
            1)
                source "$ROOT_DIR/modules/lemp.sh"
                install_lemp_menu
                ;;
            2)
                source "$ROOT_DIR/modules/site.sh"
                manage_sites_menu
                ;;
            3)
                source "$ROOT_DIR/modules/wordpress_tool.sh"
                wp_tool_menu
                ;;
            4)
                source "$ROOT_DIR/modules/security.sh"
                security_menu
                ;;
            5)
                source "$ROOT_DIR/modules/backup.sh"
                backup_menu
                ;;
            6)
                source "$ROOT_DIR/modules/php.sh"
                php_menu
                ;;
            7)
                source "$ROOT_DIR/modules/cron.sh"
                cron_menu
                ;;
            8)
                source "$ROOT_DIR/modules/service.sh"
                service_menu
                ;;
            9)
                source "$ROOT_DIR/modules/database.sh"
                database_menu
                ;;
            10)
                source "$ROOT_DIR/modules/cache.sh"
                cache_menu
                ;;
            11)
                source "$ROOT_DIR/modules/swap.sh"
                swap_menu
                ;;
            12)
                source "$ROOT_DIR/modules/disk.sh"
                disk_menu
                ;;
            13)
                source "$ROOT_DIR/modules/appadmin.sh"
                appadmin_menu
                ;;
            14)
                source "$ROOT_DIR/modules/nginx.sh"
                nginx_menu
                ;;
            15)
                source "$ROOT_DIR/modules/update.sh"
                do_update
                ;;
            16)
                source "$ROOT_DIR/modules/diagnose.sh"
                diagnose_system
                ;;
            17)
                source "$ROOT_DIR/modules/wordpress_performance.sh"
                wp_performance_menu
                ;;
            18)
                source "$ROOT_DIR/modules/phpmyadmin.sh"
                phpmyadmin_menu
                ;;
            19)
                source "$ROOT_DIR/modules/ssl.sh"
                ssl_menu
                ;;
            20)
                source "$ROOT_DIR/modules/backup.sh"
                auto_backup_menu
                ;;
            0)
                echo -e "${GREEN}Exiting... Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice!${NC}"
                pause
                ;;
        esac
    done
}
