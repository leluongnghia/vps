#!/bin/bash

# modules/swap.sh - Manage Swap Memory

swap_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý S wap (RAM ảo)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Thông tin hiện tại:"
    free -h | grep -i swap
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Tạo Swap (1GB/2GB...)"
    echo -e "2. Xóa Swap"
    echo -e "0. Quay lại"
    read -p "Chọn: " choice
    
    case $choice in
        1) create_swap ;;
        2) remove_swap ;;
        0) return ;;
    esac
}

create_swap() {
    if [ -n "$1" ]; then
        size=$1
    else
        read -p "Nhập dung lượng Swap (MB) (ví dụ 1024, 2048): " size
    fi
    
    if [ -f /swapfile ]; then
        echo -e "${RED}Swapfile đã tồn tại! Vui lòng xóa trước.${NC}"
        if [ -z "$1" ]; then pause; fi
        return
    fi
    
    log_info "Đang tạo Swapfile ${size}MB..."
    fallocate -l ${size}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Add to fstab
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    
    log_info "Tạo Swap thành công."
    if [ -z "$1" ]; then pause; fi
}

remove_swap() {
    log_info "Đang xóa Swap..."
    swapoff -a
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    log_info "Đã xóa Swap."
    pause
}
