#!/bin/bash

# modules/diagnose.sh - System Health Check & Diagnosis

diagnose_system() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       KIỂM TRA TỔNG QUÁT HỆ THỐNG${NC}"
    echo -e "${BLUE}=================================================${NC}"
    
    # 1. OS & Kernel
    echo -e "${YELLOW}1. THÔNG TIN HỆ THỐNG:${NC}"
    echo -e "   OS: $(lsb_release -d | cut -f2)"
    echo -e "   Kernel: $(uname -r)"
    echo -e "   Uptime: $(uptime -p)"
    
    # 2. Resources
    echo -e "\n${YELLOW}2. TÀI NGUYÊN (RAM & DISK):${NC}"
    free -h | awk '/^Mem:/ {print "   RAM: Thừa " $7 " / Tổng " $2}'
    free -h | awk '/^Swap:/ {print "   Swap: Dùng " $3 " / Tổng " $2}'
    df -h / | awk 'NR==2 {print "   Disk (/): Dùng " $3 " (" $5 ") / Tổng " $2}'
    
    # 3. Services Status
    echo -e "\n${YELLOW}3. TRẠNG THÁI DỊCH VỤ:${NC}"
    check_service_status "nginx" "Web Server (Nginx)"
    check_service_status "mariadb" "Database (MariaDB)"
    
    # Check PHP versions
    for ver in 8.0 8.1 8.2 8.3 8.4; do
        if systemctl list-units --full -all | grep -q "php$ver-fpm.service"; then
             check_service_status "php$ver-fpm" "PHP $ver FPM"
        fi
    done
    
    check_service_status "ssh" "SSH Service"
    check_service_status "fail2ban" "Fail2ban Security"
    
    # Firewall Status
    echo -n "   Firewall (UFW): "
    if ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}ĐANG BẬT${NC}"
    else
        echo -e "${RED}ĐANG TẮT${NC}"
    fi
    
    # 4. Deep Checks
    echo -e "\n${YELLOW}4. KIỂM TRA MẠNH (DEEP CHECK):${NC}"
    
    # Nginx Config
    echo -n "   Nginx Config: "
    if nginx -t &>/dev/null; then
        echo -e "${GREEN}OK (Hợp lệ)${NC}"
    else
        echo -e "${RED}LỖI! (Xem chi tiết bên dưới)${NC}"
        nginx -t
        has_error=1
    fi
    
    # Database Connection
    echo -n "   Kết nối Database: "
    if mysqladmin ping &>/dev/null; then
        echo -e "${GREEN}OK (Sẵn sàng)${NC}"
    else
        echo -e "${RED}LỖI (Không kết nối được)${NC}"
        has_error=1
    fi
    
    # Web Response
    echo -n "   Web Localhost (Port 80): "
    http_code=$(curl -s -o /dev/null -w "%{http_code}" 127.0.0.1)
    if [[ "$http_code" == "200" || "$http_code" == "301" || "$http_code" == "403" ]]; then
       echo -e "${GREEN}OK ($http_code)${NC}"
    else
       echo -e "${RED}Có vấn đề ($http_code)${NC}"
       # Not setting has_error strict here as default page might be deleted/redirected
    fi
    
    # 5. Log Summary
    echo -e "\n${YELLOW}5. LOG LỖI NGINX GẦN NHẤT (20 dòng):${NC}"
    if [ -f /var/log/nginx/error.log ]; then
        tail -n 20 /var/log/nginx/error.log
    else
        echo "   (Không tìm thấy file log)"
    fi
    
    echo -e "\n${BLUE}=================================================${NC}"
    if [[ "$has_error" == "1" ]]; then
        echo -e "${RED}HỆ THỐNG CÓ LỖI CẦN KHẮC PHỤC!${NC}"
    else
        echo -e "${GREEN}HỆ THỐNG HOẠT ĐỘNG TỐT!${NC}"
    fi
    echo -e "${BLUE}=================================================${NC}"
    
    pause
}

check_service_status() {
    local service=$1
    local name=$2
    if systemctl is-active --quiet "$service"; then
        echo -e "   $name: ${GREEN}RUNNING${NC}"
    else
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
             echo -e "   $name: ${RED}STOPPED (Nhưng đang Enable)${NC}"
        else
             echo -e "   $name: ${GRAY}NOT RUNNING${NC}"
        fi
    fi
}
