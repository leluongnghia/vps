#!/bin/bash

# modules/service.sh - Manage Services (Syntax)

service_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Dịch vụ (Syntax)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Restart Nginx"
    echo -e "2. Restart PHP-FPM (All versions)"
    echo -e "3. Restart MariaDB/MySQL"
    echo -e "4. Restart Redis"
    echo -e "5. Xem trạng thái các dịch vụ"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-5]: " choice

    case $choice in
        1) 
            log_info "Restarting Nginx..."
            nginx -t && systemctl restart nginx
            systemctl status nginx --no-pager
            pause
            ;;
        2)
            log_info "Restarting PHP-FPM..."
            systemctl restart php*-fpm
            systemctl status php*-fpm --no-pager
            pause
            ;;
        3)
            log_info "Restarting MariaDB..."
            systemctl restart mariadb
            systemctl status mariadb --no-pager
            pause
            ;;
        4)
            log_info "Restarting Redis..."
            systemctl restart redis-server
            systemctl status redis-server --no-pager
            pause
            ;;
        5)
            echo -e "${GREEN}--- System Status ---${NC}"
            service --status-all | grep -E 'nginx|php|mysql|redis'
            pause
            ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}
