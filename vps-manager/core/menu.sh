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
        echo -e "1. Install LEMP Stack (Nginx, MariaDB, PHP)"
        echo -e "2. Manage Domains & Websites"
        echo -e "3. Install WordPress"
        echo -e "4. Security & Optimization"
        echo -e "5. Backup & Restore"
        echo -e "6. System Tools (Update, Logs)"
        echo -e "7. PHP Version Management"
        echo -e "8. Manage Cronjobs"
        echo -e "9. Manage Services (Syntax)"
        echo -e "10. Database Management"
        echo -e "11. Cache Management"
        echo -e "12. Manage Swap"
        echo -e "13. Disk & Log Management"
        echo -e "14. AppAdmin & System Tools"
        echo -e "15. Nginx Management"
        echo -e "16. Performance Tuning (NEW)"
        echo -e "0. Exit"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Enter your choice [0-16]: " choice

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
