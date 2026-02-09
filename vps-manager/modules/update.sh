#!/bin/bash

# modules/update.sh - Script Updater
# Updates the VPS Manager script from the GitHub repository

update_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Cập nhật VPS Manager${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Phiên bản hiện tại: $(cat $ROOT_DIR/version.txt 2>/dev/null || echo 'Unknown')"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Kiểm tra và Cập nhật ngay"
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) do_update ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

do_update() {
    echo -e "${YELLOW}Đang kiểm tra cập nhật từ GitHub...${NC}"
    
    # Define update URL
    UPDATE_URL="https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh"
    
    # Download new install script
    wget -qO /tmp/vps_update.sh "$UPDATE_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Lỗi: Không thể kết nối tới GitHub. Vui lòng kiểm tra mạng hoặc repo URL.${NC}"
        pause
        return
    fi
    
    # Verify the script
    if ! grep -q "VPS Manager" /tmp/vps_update.sh; then
        echo -e "${RED}Lỗi: File tải về không hợp lệ!${NC}"
        rm -f /tmp/vps_update.sh
        pause
        return
    fi
    
    echo -e "${GREEN}Đã tìm thấy phiên bản mới! Đang tiến hành cập nhật...${NC}"
    
    # Run the new install script to self-update
    # The install.sh logic handles cloning and replacing files
    bash /tmp/vps_update.sh
    
    # Cleanup
    rm -f /tmp/vps_update.sh
    
    # Since install.sh execs itself, the script *should* restart. 
    # But if we were called from a function, we might just exit here to be safe.
    exit 0
}
