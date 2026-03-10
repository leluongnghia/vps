#!/bin/bash

# modules/disk.sh - Disk & Log Management

disk_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Disk & Logs${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Xem dung lượng tổng quan (df -h)"
    echo -e "2. Top 10 thư mục lớn nhất trong /var/www (du)"
    echo -e "3. Quét hệ thống trực quan với ncdu"
    echo -e "4. Cảnh báo dung lượng (>90%)"
    echo -e "5. Dọn dẹp hệ thống (Log cũ, apt cache, /tmp)"
    echo -e "6. Xem Logs (Nginx, PHP, MySQL)"
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) 
            clear
            echo -e "${GREEN}--- Dung lượng tổng quan (df -h) ---${NC}"
            df -h
            pause 
            ;;
        2) 
            clear
            echo -e "${GREEN}--- Top 10 thư mục lớn nhất trong /var/www ---${NC}"
            du -sh /var/www/* 2>/dev/null | sort -rh | head -10
            pause 
            ;;
        3) check_and_run_ncdu ;;
        4) check_disk_usage ;;
        5) clean_system ;;
        6) view_logs ;;
        0) return ;;
    esac
}

check_and_run_ncdu() {
    clear
    if ! command -v ncdu &> /dev/null; then
        echo -e "${YELLOW}Công cụ ncdu chưa được cài đặt. Đang tiến hành cài đặt...${NC}"
        apt-get update
        apt-get install -y ncdu
    fi
    echo -e "${GREEN}Đang mở giao diện ncdu để quét toàn bộ VPS... (Bấm phím 'q' để thoát)${NC}"
    sleep 2
    ncdu /
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
