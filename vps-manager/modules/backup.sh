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
    # 1. Select Domain
    echo -e "${YELLOW}Danh sách các bản backup Local:${NC}"
    local backup_root="/root/backups"
    
    if [ ! -d "$backup_root" ] || [ -z "$(ls -A $backup_root)" ]; then
        echo -e "${RED}Chưa có bản backup nào trên Local.${NC}"
        pause
        return
    fi

    # List domains in backup dir
    domains=()
    i=1
    for d in "$backup_root"/*; do
        if [ -d "$d" ]; then
            domain_name=$(basename "$d")
            domains+=("$domain_name")
            echo -e "$i. $domain_name"
            ((i++))
        fi
    done
    
    read -p "Chọn domain cần restore [1-${#domains[@]}]: " d_choice
    
    if ! [[ "$d_choice" =~ ^[0-9]+$ ]] || [ "$d_choice" -lt 1 ] || [ "$d_choice" -gt "${#domains[@]}" ]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
        pause
        return
    fi
    
    domain="${domains[$((d_choice-1))]}"
    backup_dir="$backup_root/$domain"
    
    # 2. Select Backup Code File
    echo -e "${CYAN}--- Chọn bản Backup Code (Source) ---${NC}"
    code_files=()
    j=1
    # Find zip files
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            code_files+=("$fname")
            echo -e "$j. $fname ($(du -h "$file" | cut -f1))"
            ((j++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 -name "code_*.zip" -type f | sort -r)
    
    if [ ${#code_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}Không tìm thấy file backup Code nào.${NC}"
        # Ask if want to continue restore DB only?
    else
        read -p "Chọn file Code [1-${#code_files[@]}] (Enter để bỏ qua): " c_choice
        if [[ -n "$c_choice" && "$c_choice" =~ ^[0-9]+$ ]]; then
             code_file="${code_files[$((c_choice-1))]}"
        fi
    fi

    # 3. Select Backup DB File
    echo -e "${CYAN}--- Chọn bản Backup Database ---${NC}"
    db_files=()
    k=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            db_files+=("$fname")
            echo -e "$k. $fname ($(du -h "$file" | cut -f1))"
            ((k++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 -name "db_*.sql*" -type f | sort -r)
    
    if [ ${#db_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}Không tìm thấy file backup DB nào.${NC}"
    else
        read -p "Chọn file DB [1-${#db_files[@]}] (Enter để bỏ qua): " db_choice
        if [[ -n "$db_choice" && "$db_choice" =~ ^[0-9]+$ ]]; then
             db_file="${db_files[$((db_choice-1))]}"
        fi
    fi
    
    if [ -z "$code_file" ] && [ -z "$db_file" ]; then
        echo -e "${RED}Chưa chọn file nào để restore.${NC}"
        pause; return
    fi
    
    echo -e "${YELLOW}Chuẩn bị Restore cho $domain...${NC}"
    echo -e "Code: ${code_file:-Không restore}"
    echo -e "DB:   ${db_file:-Không restore}"
    read -p "Xác nhận restore? Dữ liệu hiện tại sẽ bị ghi đè! (y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then return; fi
    
    # Execute Restore Code
    if [ -n "$code_file" ]; then
        log_info "Đang giải nén mã nguồn..."
        # Backup current html just in case? Maybe simplistic restore simply overwrites.
        # Clean current dir to avoid mixing?
        # rm -rf "/var/www/$domain/public_html/*"  <-- Risk
        # Unzip overwrites
        unzip -o "$backup_dir/$code_file" -d "/var/www/$domain/"
        # Fix permissions
        chown -R www-data:www-data "/var/www/$domain/public_html"
    fi
    
    # Execute Restore DB
    if [ -n "$db_file" ]; then
        log_info "Đang import database..."
        # Detect compression
        db_name=$(echo "$domain" | tr -d '.')
        
        if [[ "$db_file" == *.gz ]]; then
            zcat "$backup_dir/$db_file" | mysql "$db_name"
        else
            mysql "$db_name" < "$backup_dir/$db_file"
        fi
    fi
    
    log_info "Restore hoàn tất!"
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
