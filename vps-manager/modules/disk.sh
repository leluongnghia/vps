#!/bin/bash

# modules/disk.sh - Disk & Log Management

disk_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Disk & Logs${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Xem dung lượng ổ đĩa (Disk Usage)"
    echo -e "2. Cảnh báo dung lượng (>90%)"
    echo -e "3. Dọn dẹp hệ thống (Log cũ, apt cache)"
    echo -e "4. Xem Logs (Nginx, PHP, MySQL)"
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) 
            df -h
            echo "--- Top 10 thư mục lớn nhất trong /var/www ---"
            du -sh /var/www/* | sort -rh | head -10
            pause 
            ;;
        2) check_disk_usage ;;
        3) clean_system ;;
        4) view_logs ;;
        0) return ;;
    esac
}

check_disk_usage() {
    usage=$(df / | grep / | awk '{ print $5 }' | sed 's/%//g')
    if [ "$usage" -gt 90 ]; then
        echo -e "${RED}CẢNH BÁO: Ổ đĩa đã đầy $usage%!${NC}"
    else
        echo -e "${GREEN}Dung lượng ổ đĩa ổn định ($usage%).${NC}"
    fi
    pause
}

clean_system() {
    log_info "Đang dọn dẹp..."
    apt-get clean
    apt-get autoremove -y
    journalctl --vacuum-time=3d
    rm -rf /tmp/*
    log_info "Dọn dẹp hoàn tất."
    pause
}

view_logs() {
    echo -e "1. Nginx Error Log"
    echo -e "2. Nginx Access Log"
    echo -e "3. PHP-FPM Log"
    echo -e "4. MariaDB Log"
    read -p "Chọn log: " l
    
    case $l in
        1) tail -f -n 50 /var/log/nginx/error.log ;;
        2) tail -f -n 50 /var/log/nginx/access.log ;;
        3) tail -f -n 50 /var/log/php*-fpm.log ;;
        4) tail -f -n 50 /var/log/mysql/error.log ;;
    esac
    pause
}
