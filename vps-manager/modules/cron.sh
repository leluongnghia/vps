#!/bin/bash

# modules/cron.sh - Cron Job Management

cron_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Cronjob${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Xem danh sách Cronjob hiện tại"
    echo -e "2. Thêm Cronjob mới"
    echo -e "3. Xóa toàn bộ Cronjob (Cẩn thận!)"
    echo -e "4. Chỉnh sửa Cronjob thủ công (Nano)"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-4]: " choice

    case $choice in
        1) list_crons ;;
        2) add_cron ;;
        3) delete_all_crons ;;
        4) edit_cron_manual ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

list_crons() {
    echo -e "${GREEN}--- Danh sách Cronjob ---${NC}"
    crontab -l
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Chưa có cronjob nào được thiết lập.${NC}"
    fi
    pause
}

add_cron() {
    echo -e "${GREEN}Thêm Cronjob Mới${NC}"
    echo -e "Ví dụ: */5 * * * * /usr/bin/php /var/www/domain.com/cron.php"
    read -p "Nhập lệnh cron: " cron_cmd
    
    if [ -z "$cron_cmd" ]; then return; fi
    
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    log_info "Đã thêm cronjob thành công."
    pause
}

delete_all_crons() {
    read -p "Bạn có chắc chắn muốn XÓA TOÀN BỘ cronjob? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        crontab -r
        log_info "Đã xóa toàn bộ cronjob."
    fi
    pause
}

edit_cron_manual() {
    log_info "Đang mở trình soạn thảo Nano..."
    crontab -e
    pause
}
