#!/bin/bash

# core/menu.sh - Main Menu

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$DIR")"

# Import utils
source "$ROOT_DIR/core/utils.sh"

main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          VPS MANAGEMENT SCRIPT v1.0${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài đặt LEMP Stack (Nginx, MariaDB, PHP)"
        echo -e "2. Quản lý Domain & Website"
        echo -e "3. Cài đặt WordPress (Mới)"
        echo -e "4. Bảo mật & Tối ưu hóa"
        echo -e "5. Sao lưu & Khôi phục (Backup/Restore)"
        echo -e "6. Công cụ Hệ thống (Update, Logs)"
        echo -e "7. Quản lý Phiên bản PHP"
        echo -e "8. Quản lý Cronmodel (Lịch biểu)"
        echo -e "9. Quản lý Services (Khởi động lại/Stop)"
        echo -e "10. Quản lý Database (Cơ sở dữ liệu)"
        echo -e "11. Quản lý Cache (Redis/FastCGI)"
        echo -e "12. Quản lý Swap (RAM ảo)"
        echo -e "13. Quản lý Ổ đĩa & Dọn dẹp Logs"
        echo -e "14. AppAdmin & Công cụ bổ trợ"
        echo -e "15. Quản lý Nginx (Cấu hình)"
        echo -e "16. Tối ưu hóa Hiệu năng (High Performance)"
        echo -e "17. Cập nhật Script (Từ GitHub)"
        echo -e "0. Thoát"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn của bạn [0-17]: " choice

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
                source "$ROOT_DIR/modules/site.sh"
                add_new_site "wordpress"
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
                 source "$ROOT_DIR/modules/optimize.sh"
                 optimize_menu
                 ;;
            7)
                source "$ROOT_DIR/modules/php.sh"
                php_menu
                ;;
            8)
                source "$ROOT_DIR/modules/cron.sh"
                cron_menu
                ;;
            9)
                source "$ROOT_DIR/modules/service.sh"
                service_menu
                ;;
            10)
                source "$ROOT_DIR/modules/database.sh"
                database_menu
                ;;
            11)
                source "$ROOT_DIR/modules/cache.sh"
                cache_menu
                ;;
            12)
                source "$ROOT_DIR/modules/swap.sh"
                swap_menu
                ;;
            13)
                source "$ROOT_DIR/modules/disk.sh"
                disk_menu
                ;;
            14)
                source "$ROOT_DIR/modules/appadmin.sh"
                appadmin_menu
                ;;
            15)
                source "$ROOT_DIR/modules/nginx.sh"
                nginx_menu
                ;;
            16)
                source "$ROOT_DIR/modules/performance.sh"
                performance_menu
                ;;
            17)
                source "$ROOT_DIR/modules/update.sh"
                do_update
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
