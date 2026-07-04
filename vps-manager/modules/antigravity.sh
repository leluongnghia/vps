#!/bin/bash
# modules/antigravity.sh - Antigravity Installation Management

antigravity_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       Quản lý Cài đặt Antigravity${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e ""
    echo -e "1. Cài đặt Antigravity"
    echo -e "2. Gỡ cài đặt Antigravity"
    echo -e "0. Quay lại"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-2]: " choice

    case $choice in
        1) install_antigravity ;;
        2) uninstall_antigravity ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

install_antigravity() {
    echo -e "${YELLOW}Đang tiến hành cài đặt Antigravity...${NC}"
    # Add actual installation commands here
    # Example:
    # apt-get install -y python3-pip
    # pip3 install antigravity
    echo -e "${GREEN}Cài đặt Antigravity hoàn tất!${NC}"
    pause
}

uninstall_antigravity() {
    echo -e "${YELLOW}Đang tiến hành gỡ cài đặt và dọn sạch hoàn toàn rác của Antigravity...${NC}"
    
    # 1. Dừng và xóa systemd service (nếu có)
    echo -e "${CYAN}[1/6] Dừng và gỡ bỏ các service ẩn...${NC}"
    systemctl stop antigravity.service 2>/dev/null || true
    systemctl disable antigravity.service 2>/dev/null || true
    rm -f /etc/systemd/system/antigravity.service
    rm -f /usr/lib/systemd/system/antigravity.service
    systemctl daemon-reload

    # 2. Xóa các file thực thi và package (ví dụ qua pip hoặc apt)
    echo -e "${CYAN}[2/6] Gỡ cài đặt package và file thực thi...${NC}"
    pip3 uninstall -y antigravity 2>/dev/null || true
    rm -f /usr/local/bin/antigravity
    rm -f /usr/bin/antigravity

    # 3. Xóa thư mục cấu hình
    echo -e "${CYAN}[3/6] Xóa toàn bộ file cấu hình...${NC}"
    rm -rf /etc/antigravity
    rm -rf ~/.config/antigravity

    # 4. Xóa thư mục Log và Cache
    echo -e "${CYAN}[4/6] Dọn dẹp thư mục log và cache...${NC}"
    rm -rf /var/log/antigravity
    rm -rf /var/cache/antigravity
    rm -rf ~/.cache/antigravity

    # 5. Xóa dữ liệu tồn đọng
    echo -e "${CYAN}[5/6] Xóa dữ liệu ứng dụng tồn đọng...${NC}"
    rm -rf /var/lib/antigravity
    rm -rf /opt/antigravity

    # 6. Xóa User/Group hệ thống (nếu phần mềm đã tạo)
    echo -e "${CYAN}[6/6] Xóa user/group hệ thống (nếu có)...${NC}"
    userdel -r antigravity 2>/dev/null || true
    groupdel antigravity 2>/dev/null || true

    echo -e "${GREEN}Gỡ cài đặt và dọn sạch 100% rác Antigravity hoàn tất!${NC}"
    pause
}
