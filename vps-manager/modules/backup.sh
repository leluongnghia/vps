#!/bin/bash

# modules/backup.sh - Backup & Restore System

backup_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Sao lưu & Khôi phục${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Backup Website (Local)"
    echo -e "2. Backup Website (Google Drive)"
    echo -e "3. Restore Website (Local)"
    echo -e "4. Restore Website (Google Drive)"
    echo -e "5. Cấu hình Google Drive (rclone)"
    echo -e "6. Quản lý bản Backup (List/Delete)"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-6]: " choice

    case $choice in
        1) backup_site_local ;;
        2) backup_to_gdrive ;;
        3) restore_site_local ;;
        4) restore_site_gdrive ;;
        5) setup_gdrive ;;
        6) manage_backups ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

setup_gdrive() {
    if ! command -v rclone &> /dev/null; then
        apt-get install -y rclone
    fi
    echo -e "${YELLOW}--- Cấu hình rclone ---${NC}"
    rclone config
    pause
}

backup_site_local() {
    read -p "Nhập domain cần backup: " domain
    timestamp=$(date +%F_%H-%M-%S)
    backup_dir="/root/backups/$domain"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Code..."
    zip -r "$backup_dir/code_$timestamp.zip" "/var/www/$domain/public_html" -x "*.log"
    
    db_name=$(echo "$domain" | tr -d '.')
    log_info "Backing up DB..."
    mysqldump "$db_name" > "$backup_dir/db_$timestamp.sql"
    gzip "$backup_dir/db_$timestamp.sql"
    
    log_info "Backup hoàn tất tại $backup_dir"
    cleanup_old_backups "$backup_dir" 7
    pause
}

backup_to_gdrive() {
    read -p "Nhập domain cần backup: " domain
    read -p "Nhập tên remote GDrive (Mac dinh: gdrive): " remote
    remote=${remote:-gdrive}
    
    # Local backup first
    timestamp=$(date +%F_%H-%M-%S)
    backup_dir="/root/backups/$domain"
    mkdir -p "$backup_dir"
    
    zip_file="$backup_dir/code_$timestamp.zip"
    db_file="$backup_dir/db_$timestamp.sql.gz"
    
    log_info "Creating Local Backup..."
    zip -r "$zip_file" "/var/www/$domain/public_html" -x "*.log"
    mysqldump $(echo "$domain" | tr -d '.') | gzip > "$db_file"
    
    log_info "Uploading to Google Drive ($remote:vps_backups/$domain)..."
    rclone copy "$zip_file" "$remote:vps_backups/$domain/"
    rclone copy "$db_file" "$remote:vps_backups/$domain/"
    
    log_info "Upload Done."
    pause
}

restore_site_local() {
    read -p "Nhập domain cần restore: " domain
    backup_dir="/root/backups/$domain"
    
    echo "Files available:"
    ls -lh "$backup_dir"
    
    read -p "File Code (zip): " code_file
    read -p "File DB (sql.gz): " db_file
    
    if [[ -f "$backup_dir/$code_file" && -f "$backup_dir/$db_file" ]]; then
        log_info "Restoring..."
        unzip -o "$backup_dir/$code_file" -d "/var/www/$domain/"
        zcat "$backup_dir/$db_file" | mysql $(echo "$domain" | tr -d '.')
        log_info "Done."
    else
        echo -e "${RED}File not found.${NC}"
    fi
    pause
}

restore_site_gdrive() {
    read -p "Nhập domain cần restore: " domain
    read -p "Remote name (gdrive): " remote
    remote=${remote:-gdrive}
    
    log_info "Files on Cloud:"
    rclone lsl "$remote:vps_backups/$domain/" | tail -n 10
    
    read -p "Cloud Code filename: " cloud_code
    read -p "Cloud DB filename: " cloud_db
    
    tmp_dir="/root/backups/$domain/restore_tmp"
    mkdir -p "$tmp_dir"
    
    log_info "Downloading..."
    rclone copy "$remote:vps_backups/$domain/$cloud_code" "$tmp_dir/"
    rclone copy "$remote:vps_backups/$domain/$cloud_db" "$tmp_dir/"
    
    log_info "Restoring..."
    unzip -o "$tmp_dir/$cloud_code" -d "/var/www/$domain/"
    zcat "$tmp_dir/$cloud_db" | mysql $(echo "$domain" | tr -d '.')
    
    rm -rf "$tmp_dir"
    log_info "Done."
    pause
}

manage_backups() {
    echo -e "1. List Local"
    echo -e "2. List Cloud"
    read -p "Select: " c
    if [[ "$c" == "1" ]]; then
        du -sh /root/backups/*
    elif [[ "$c" == "2" ]]; then
        read -p "Remote: " r
        rclone lsd "${r:-gdrive}:vps_backups/"
    fi
    pause
}

cleanup_old_backups() {
    local dir=$1
    local keep=$2
    cd "$dir"
    ls -tp | grep -v '/$' | tail -n +$(($keep + 1)) | xargs -I {} rm -- {}
}
