#!/bin/bash

# modules/disk.sh - Disk & Log Management & Logrotate

disk_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          💿 Quản lý Ổ đĩa & Logs${NC}"
        echo -e "${BLUE}=================================================${NC}"
        
        # Display current disk usage
        local root_usage
        root_usage=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
        echo -e "Dung lượng phân vùng [/]: ${CYAN}${root_usage}${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Xem dung lượng tổng quan (df -h)"
        echo -e "2. Top 10 thư mục lớn nhất trong /var/www (du)"
        echo -e "3. 🔍 Quét tìm các file lớn nhất toàn VPS (>100MB)"
        echo -e "4. 🖥️  Quét hệ thống trực quan với NCDU (Duyệt thư mục bằng phím mũi tên)"
        echo -e "5. 🧹 Dọn dẹp rác hệ thống (Package cache, systemd journal, /tmp)"
        echo -e "6. 🚨 Cứu hộ khẩn cấp: Xả trắng các file Log quá lớn (>100MB)"
        echo -e "7. 🛡️  Cấu hình Logrotate tự động (Chống 100% rủi ro tràn đĩa do log)"
        echo -e "8. 📜 Xem trực tiếp Logs (Nginx, PHP, MariaDB)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-8]: " choice
        
        case $choice in
            1) 
                clear
                echo -e "${GREEN}--- Dung lượng tổng quan các phân vùng (df -h) ---${NC}"
                df -h
                pause 
                ;;
            2) 
                clear
                echo -e "${GREEN}--- Top 10 thư mục lớn nhất trong /var/www ---${NC}"
                du -sh /var/www/* 2>/dev/null | sort -rh | head -10
                pause 
                ;;
            3) find_large_files ;;
            4) check_and_run_ncdu ;;
            5) clean_system ;;
            6) truncate_huge_logs ;;
            7) setup_logrotate ;;
            8) view_logs ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

find_large_files() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🔍 Quét các File Dung lượng Lớn (>100MB)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}Đang quét toàn bộ hệ thống (bỏ qua /proc, /sys, /dev)... Vui lòng đợi trong giây lát...${NC}"
    echo ""

    local large_files
    large_files=$(find / -xdev -type f -size +100M -exec ls -lh {} + 2>/dev/null | awk '{print $5, "\t", $9}' | sort -hr | head -n 25)

    if [[ -z "$large_files" ]]; then
        echo -e "${GREEN}✅ Không tìm thấy file nào vượt quá 100MB. Ổ đĩa rất gọn gàng!${NC}"
    else
        echo -e "${CYAN}Danh sách 25 file lớn nhất tìm thấy:${NC}"
        echo -e "SIZE\t FILE PATH"
        echo -e "----\t ---------"
        echo "$large_files"
    fi
    echo ""
    pause
}

check_and_run_ncdu() {
    clear
    if ! command -v ncdu &> /dev/null; then
        echo -e "${YELLOW}Công cụ ncdu chưa được cài đặt. Đang tiến hành cài đặt...${NC}"
        pkg_update >/dev/null 2>&1
        pkg_install ncdu
    fi
    echo -e "${GREEN}Đang mở giao diện ncdu để quét thư mục /var/www... (Bấm phím 'q' để thoát)${NC}"
    sleep 1
    ncdu /var/www
}

clean_system() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🧹 Dọn dẹp Rác Hệ thống${NC}"
    echo -e "${BLUE}=================================================${NC}"
    log_info "1. Dọn dẹp bộ đệm gói cài đặt (Package Cache)..."
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf clean all -y >/dev/null 2>&1
    else
        apt-get clean -y >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
    fi

    log_info "2. Thu gọn Systemd Journal Log (chỉ giữ 3 ngày gần nhất)..."
    journalctl --vacuum-time=3d >/dev/null 2>&1

    log_info "3. Dọn dẹp thư mục tạm /tmp..."
    rm -rf /tmp/* 2>/dev/null || true

    log_info "4. Dọn dẹp cache Nginx cũ..."
    if [[ -d /var/cache/nginx ]]; then
        find /var/cache/nginx/ -type f -mtime +7 -delete 2>/dev/null || true
    fi

    echo ""
    echo -e "${GREEN}✅ Dọn dẹp rác hệ thống hoàn tất!${NC}"
    pause
}

truncate_huge_logs() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${RED}   🚨 Cứu hộ Khẩn cấp: Xả Trắng File Log Lớn (>100MB)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Tìm các file log (*.log) trong /var/log có kích thước >100MB và xóa nội dung về 0..."
    echo ""

    local logs_found
    logs_found=$(find /var/log -type f -name "*.log" -size +100M 2>/dev/null)

    if [[ -z "$logs_found" ]]; then
        echo -e "${GREEN}✅ Không có file log nào vượt quá 100MB.${NC}"
        pause; return
    fi

    echo -e "${YELLOW}Phát hiện các file log khổng lồ:${NC}"
    echo "$logs_found"
    echo ""
    read -p "Xác nhận xả trắng (truncate) các file log này? [y/N]: " confirm_tr
    if [[ "$confirm_tr" == "y" || "$confirm_tr" == "Y" ]]; then
        echo "$logs_found" | while read -r lf; do
            if [[ -n "$lf" && -f "$lf" ]]; then
                truncate -s 0 "$lf"
                log_info "Đã xả trắng: $lf"
            fi
        done
        echo -e "${GREEN}✅ Đã giải phóng không gian ổ đĩa thành công!${NC}"
    else
        echo -e "${YELLOW}Đã hủy thao tác.${NC}"
    fi
    pause
}

setup_logrotate() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    🛡️  Cấu hình Logrotate Tự động${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Thiết lập tự động xoay vòng log định kỳ cho Nginx, PHP-FPM, MariaDB:"
    echo -e "  • Tần suất: Hàng tuần (hoặc ngay khi file vượt quá 50MB)"
    echo -e "  • Giữ lại: 4 bản cũ gần nhất (nén gz để tiết kiệm dung lượng)"
    echo -e "  • Tự động dọn sạch log quá hạn, không bao giờ lo tràn ổ đĩa"
    echo -e "${BLUE}=================================================${NC}"

    if ! command -v logrotate &>/dev/null; then
        pkg_install logrotate
    fi

    cat > /etc/logrotate.d/vps-manager << 'EOF'
/var/log/nginx/*.log /var/log/php*-fpm.log /var/log/mariadb/*.log /var/log/mysql/*.log {
    weekly
    maxsize 50M
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
EOF

    # Test logrotate config syntax
    if logrotate -d /etc/logrotate.d/vps-manager >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Cấu hình Logrotate đã được cài đặt và kích hoạt thành công!${NC}"
    else
        echo -e "${YELLOW}Đã tạo cấu hình Logrotate tại /etc/logrotate.d/vps-manager.${NC}"
    fi
    pause
}

view_logs() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          📜 Xem Trực tiếp Logs Hệ thống${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Nginx Error Log (/var/log/nginx/error.log)"
    echo -e "2. Nginx Access Log (/var/log/nginx/access.log)"
    echo -e "3. PHP-FPM Log"
    echo -e "4. MariaDB Log (/var/log/mysql/error.log)"
    echo -e "0. Quay lại"
    read -p "Chọn log muốn xem [0-4]: " l
    
    case $l in
        1) [[ -f /var/log/nginx/error.log ]] && tail -n 50 /var/log/nginx/error.log || echo "Chưa có log." ;;
        2) [[ -f /var/log/nginx/access.log ]] && tail -n 50 /var/log/nginx/access.log || echo "Chưa có log." ;;
        3) 
            local php_log
            php_log=$(ls /var/log/php*-fpm.log 2>/dev/null | head -n 1)
            [[ -n "$php_log" && -f "$php_log" ]] && tail -n 50 "$php_log" || echo "Không tìm thấy log PHP-FPM."
            ;;
        4) 
            local db_log="/var/log/mysql/error.log"
            [[ ! -f "$db_log" ]] && db_log="/var/log/mariadb/mariadb.log"
            [[ -f "$db_log" ]] && tail -n 50 "$db_log" || echo "Không tìm thấy log MariaDB."
            ;;
        0) return ;;
    esac
    pause
}

