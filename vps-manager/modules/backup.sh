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
    echo -e "4. Restore Website (Manual Uploaded - trong public_html)"
    echo -e "5. Restore Website (Google Drive)"
    echo -e "6. Cấu hình Google Drive (rclone)"
    echo -e "7. Quản lý bản Backup (List/Delete)"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-7]: " choice

    case $choice in
        1) backup_site_local ;;
        2) backup_to_gdrive ;;
        3) restore_site_local ;;
        4) restore_site_manual_upload ;;
        5) restore_site_gdrive ;;
        6) setup_gdrive ;;
        7) manage_backups ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

restore_site_manual_upload() {
    # 1. Select Target Domain
    echo -e "${YELLOW}--- Restore từ File Upload thủ công ---${NC}"
    echo -e "Vui lòng upload file backup (.zip / .sql) vào thư mục: /var/www/TEN_MIEN/public_html"
    
    # List active sites
    target_sites=()
    i=1
    for d in /var/www/*; do
        if [ -d "$d" ]; then
            domain=$(basename "$d")
            if [[ "$domain" != "html" ]]; then
                target_sites+=("$domain")
                echo -e "$i. $domain"
                ((i++))
            fi
        fi
    done
    
    read -p "Chọn website ĐÍCH [1-${#target_sites[@]}]: " t_choice
    if ! [[ "$t_choice" =~ ^[0-9]+$ ]] || [ "$t_choice" -lt 1 ] || [ "$t_choice" -gt "${#target_sites[@]}" ]; then echo -e "${RED}Error${NC}"; pause; return; fi
    target_domain="${target_sites[$((t_choice-1))]}"
    search_dir="/var/www/$target_domain/public_html"
    
    # Detect Source Domain (Try to guess from filename or prompt)
    # Usually filenames are code_domain_time.zip
    # We will prompt later if search-replace needed.
    
    # 2. Select Code File
    echo -e "\n${CYAN}Tìm kiếm file .zip / .tar.gz trong $search_dir...${NC}"
    code_files=()
    j=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            code_files+=("$fname")
            echo -e "$j. $fname"
            ((j++))
        fi
    done < <(find "$search_dir" -maxdepth 1 \( -name "*.zip" -o -name "*.tar.gz" \) -type f)
    
    read -p "Chọn file Code [1-${#code_files[@]}] (Enter để bỏ qua): " c_sel
    code_file=""
    if [[ -n "$c_sel" && "$c_sel" =~ ^[0-9]+$ ]]; then code_file="${code_files[$((c_sel-1))]}"; fi

    # 3. Select DB File
    echo -e "\n${CYAN}Tìm kiếm file .sql / .sql.gz trong $search_dir...${NC}"
    db_files=()
    k=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            db_files+=("$fname")
            echo -e "$k. $fname"
            ((k++))
        fi
    done < <(find "$search_dir" -maxdepth 1 \( -name "*.sql" -o -name "*.sql.gz" \) -type f)
    
    read -p "Chọn file DB [1-${#db_files[@]}] (Enter để bỏ qua): " db_sel
    db_file=""
    if [[ -n "$db_sel" && "$db_sel" =~ ^[0-9]+$ ]]; then db_file="${db_files[$((db_sel-1))]}"; fi
    
    if [ -z "$code_file" ] && [ -z "$db_file" ]; then echo -e "${RED}Không chọn file nào.${NC}"; pause; return; fi

    # 4. Confirm Restore
    echo -e "${RED}CẢNH BÁO: Dữ liệu trên $target_domain sẽ bị ghi đè!${NC}"
    read -p "Xác nhận restore? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi
    
    # Get Target DB Creds (Match logic with site.sh)
    target_db_name=$(echo "$target_domain" | tr -d '.-' | cut -c1-16)
    target_db_user="${target_db_name}_u"
    target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" 2>/dev/null | cut -d "'" -f 4)

    # RESTORE CODE
    if [ -n "$code_file" ]; then
        log_info "Giải nén Code..."
        
        tmp_extract="/root/restore_tmp_$target_domain"
        rm -rf "$tmp_extract"; mkdir -p "$tmp_extract"
        
        if [[ "$code_file" == *.zip ]]; then
            unzip -o -q "$search_dir/$code_file" -d "$tmp_extract"
        elif [[ "$code_file" == *.tar.gz ]]; then
            tar -xzf "$search_dir/$code_file" -C "$tmp_extract"
        else
            log_error "Định dạng file code không hỗ trợ (.zip, .tar.gz)"
            rm -rf "$tmp_extract"
            return
        fi
        
        # Move content to proper place
        log_info "Đang di chuyển dữ liệu..."
        # Find where wp-config.php is in extracted
        wp_root=$(find "$tmp_extract" -name "wp-config.php" -exec dirname {} \; | head -n 1)
        
        if [ -n "$wp_root" ]; then
            cp -a "$wp_root/." "/var/www/$target_domain/public_html/"
        else
            # Try just moving everything if empty
            cp -a "$tmp_extract/." "/var/www/$target_domain/public_html/"
        fi
        
        rm -rf "$tmp_extract"
        
        # RESTORE CORRECT DB CREDENTIALS TO wp-config.php
        log_info "Khôi phục thông tin kết nối Database chuẩn..."
        wp_conf="/var/www/$target_domain/public_html/wp-config.php"
        
        if [ -f "$wp_conf" ] && [ -n "$current_db_pass" ]; then
            # Update DB_NAME
            sed -i "s|define([ ]*['\"]DB_NAME['\"],.*)|define( 'DB_NAME', '$target_db_name' );|" "$wp_conf"
            # Update DB_USER
            sed -i "s|define([ ]*['\"]DB_USER['\"],.*)|define( 'DB_USER', '$target_db_user' );|" "$wp_conf"
            # Update DB_PASSWORD
            sed -i "s|define([ ]*['\"]DB_PASSWORD['\"],.*)|define( 'DB_PASSWORD', '$current_db_pass' );|" "$wp_conf"
        else
            log_warn "Không tìm thấy wp-config.php hoặc không lấy được mật khẩu DB cũ."
        fi
    fi
    
    # RESTORE DB
    if [ -n "$db_file" ]; then
        log_info "Import Database..."
        if [[ "$db_file" == *.gz ]]; then
            zcat "$search_dir/$db_file" | mysql "$target_db_name"
        else
            mysql "$target_db_name" < "$search_dir/$db_file"
        fi
        mysqlcheck --auto-repair "$target_db_name"
        
        # Auto fix Table Prefix
        log_info "Đang kiểm tra Table Prefix..."
        detected_table=$(mysql -N -B -e "SHOW TABLES LIKE '%_users'" "$target_db_name" | head -n 1)
        if [ -n "$detected_table" ]; then
            new_prefix=${detected_table%users}
            if [ -n "$new_prefix" ]; then
                log_info "Prefix phát hiện: '$new_prefix'. Cập nhật wp-config.php..."
                sed -i "s/\\\$table_prefix\s*=\s*'.*';/\\\$table_prefix = '$new_prefix';/" "/var/www/$target_domain/public_html/wp-config.php"
            fi
        fi
    fi
    
    # AUTO DETECT & SEARCH REPLACE
    log_info "Đang kiểm tra URL cũ trong Database..."
    
    # Ensure WP-CLI
    if ! command -v wp &> /dev/null; then
         curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; chmod +x wp-cli.phar; mv wp-cli.phar /usr/local/bin/wp
    fi
    
    cd "/var/www/$target_domain/public_html"
    
    # Get current siteurl from DB
    old_url=$(wp option get siteurl --allow-root 2>/dev/null)
    # Extract domain from url (remove http:// or https://)
    source_domain=$(echo "$old_url" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    
    if [ -n "$source_domain" ] && [ "$source_domain" != "$target_domain" ]; then
        log_info "Phát hiện tên miền cũ: $source_domain -> Tên miền mới: $target_domain"
        log_info "Tiến hành thay thế toàn bộ liên kết..."
        
        wp search-replace "http://$source_domain" "http://$target_domain" --allow-root
        wp search-replace "https://$source_domain" "https://$target_domain" --allow-root
        wp search-replace "$source_domain" "$target_domain" --allow-root
        
        log_info "Đã thay thế URL xong."
    else
        log_info "URL trong database ($source_domain) khớp với hiện tại hoặc không tìm thấy. Bỏ qua thay thế."
    fi
    
    # AUTO FIX WORDPRESS CORE IF NEEDED
    # Check if critical files are missing (which causes 'No input file specified/redirect setup')
    if [ ! -f "/var/www/$target_domain/public_html/wp-admin/admin.php" ] || [ ! -f "/var/www/$target_domain/public_html/wp-includes/version.php" ]; then
        log_warn "Phát hiện thiếu file Core WordPress. Đang tự động tải lại Core..."
        
        cd "/var/www/$target_domain/public_html"
        wget -q https://wordpress.org/latest.tar.gz
        if [ -f latest.tar.gz ]; then
            tar -xzf latest.tar.gz
            cp -r wordpress/* .
            rm -rf wordpress latest.tar.gz
            log_info "Đã khôi phục Core WordPress thành công."
        fi
    fi

    # REMOVE CONFLICTING CONFIGS (Critical for open_basedir errors)
    log_info "Đang dọn dẹp cấu hình cũ gây xung đột..."
    find "/var/www/$target_domain/public_html" -name ".user.ini" -delete
    find "/var/www/$target_domain/public_html" -name ".htaccess" -delete
    
    # Clean temporary files if any remain
    if [ -n "$tmp_extract" ] && [ -d "$tmp_extract" ]; then
        rm -rf "$tmp_extract"
    fi

    # FINAL PERMISSIONS FIX (AGAIN to cover new files)
    log_info "Đang thiết lập quyền (Permissions) chuẩn cho WordPress..."
    chown -R www-data:www-data "/var/www/$target_domain/public_html"
    find "/var/www/$target_domain/public_html" -type d -exec chmod 755 {} \;
    find "/var/www/$target_domain/public_html" -type f -exec chmod 644 {} \;
    
    log_info "Restore hoàn tất!"
    pause
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
    # Select site from list
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
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
    # Select site from list
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
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
    # 1. Select Target Domain (Active Sites)
    echo -e "${YELLOW}--- Restore / Migrate Website (Local) ---${NC}"
    echo -e "Chọn Website ĐÍCH (Nơi dữ liệu sẽ được khôi phục vào):"
    
    # List active sites in /var/www check
    target_sites=()
    i=1
    for d in /var/www/*; do
        if [ -d "$d" ]; then
            domain=$(basename "$d")
            if [[ "$domain" != "html" ]]; then
                target_sites+=("$domain")
                echo -e "$i. $domain"
                ((i++))
            fi
        fi
    done
    
    if [ ${#target_sites[@]} -eq 0 ]; then
        echo -e "${RED}Chưa có website nào được tạo trên VPS.${NC}"
        pause; return
    fi
    
    read -p "Chọn website ĐÍCH [1-${#target_sites[@]}]: " t_choice
    if ! [[ "$t_choice" =~ ^[0-9]+$ ]] || [ "$t_choice" -lt 1 ] || [ "$t_choice" -gt "${#target_sites[@]}" ]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi
    target_domain="${target_sites[$((t_choice-1))]}"
    
    # 2. Select Source Backup (From /root/backups)
    echo -e "\n${CYAN}Chọn Nguồn Backup (Domain gốc của bản sao lưu):${NC}"
    local backup_root="/root/backups"
    if [ ! -d "$backup_root" ]; then echo -e "${RED}Không có backup nào.${NC}"; pause; return; fi
    
    source_folders=()
    j=1
    for d in "$backup_root"/*; do
        if [ -d "$d" ]; then
            s_domain=$(basename "$d")
            source_folders+=("$s_domain")
            echo -e "$j. $s_domain"
            ((j++))
        fi
    done
    
    read -p "Chọn nguồn backup [1-${#source_folders[@]}]: " s_choice
    if ! [[ "$s_choice" =~ ^[0-9]+$ ]] || [ "$s_choice" -lt 1 ] || [ "$s_choice" -gt "${#source_folders[@]}" ]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi
    source_domain="${source_folders[$((s_choice-1))]}"
    backup_dir="$backup_root/$source_domain"
    
    # 3. Select Backup Files
    echo -e "\n${CYAN}--- Chọn bản Backup Code ---${NC}"
    code_files=()
    k=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            code_files+=("$fname")
            echo -e "$k. $fname ($(du -h "$file" | cut -f1))"
            ((k++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 -name "code_*.zip" -type f | sort -r)
    
    read -p "Chọn file Code [1-${#code_files[@]}] (Enter để bỏ qua): " c_sel
    code_file=""
    if [[ -n "$c_sel" && "$c_sel" =~ ^[0-9]+$ ]]; then code_file="${code_files[$((c_sel-1))]}"; fi

    echo -e "\n${CYAN}--- Chọn bản Backup DB ---${NC}"
    db_files=()
    l=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            db_files+=("$fname")
            echo -e "$l. $fname ($(du -h "$file" | cut -f1))"
            ((l++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 -name "db_*.sql*" -type f | sort -r)
    
    read -p "Chọn file DB [1-${#db_files[@]}] (Enter để bỏ qua): " db_sel
    db_file=""
    if [[ -n "$db_sel" && "$db_sel" =~ ^[0-9]+$ ]]; then db_file="${db_files[$((db_sel-1))]}"; fi
    
    if [ -z "$code_file" ] && [ -z "$db_file" ]; then echo -e "${RED}Không chọn file nào.${NC}"; pause; return; fi

    # Confirm
    echo -e "${RED}CẢNH BÁO: Dữ liệu trên $target_domain sẽ bị ghi đè!${NC}"
    read -p "Xác nhận restore? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi
    
    # Get Target DB Creds (from current wp-config or regenerate)
    # We assume standard naming convention or read from file
    target_db_name=$(echo "$target_domain" | tr -d '.')
    target_db_user="${target_db_name}_user"
    # Try to grep password from existing file
    if [ -f "/var/www/$target_domain/public_html/wp-config.php" ]; then
        target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" | cut -d "'" -f 4)
    else
        # If config missing, we might have a problem unless we know the pass.
        # Assuming we don't change pass, just keeping what's in the backup? NO, backup has OLD creds.
        # We need to UPDATE wp-config with TARGET creds.
        # If we can't find target creds, we might need to reset them?
        # Let's hope mysql root access works.
        target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
    fi

    # RESTORE CODE
    if [ -n "$code_file" ]; then
        log_info "Đang giải nén Code..."
        unzip -o "$backup_dir/$code_file" -d "/var/www/$target_domain/"
        chown -R www-data:www-data "/var/www/$target_domain/public_html"
        
        # Update wp-config with TARGET DB info (if we found it)
        if [ -n "$target_db_pass" ]; then
            log_info "Cập nhật wp-config.php theo Database đích..."
            sed -i "s/DB_NAME', '.*'/DB_NAME', '$target_db_name'/" "/var/www/$target_domain/public_html/wp-config.php"
            sed -i "s/DB_USER', '.*'/DB_USER', '$target_db_user'/" "/var/www/$target_domain/public_html/wp-config.php"
            sed -i "s/DB_PASSWORD', '.*'/DB_PASSWORD', '$target_db_pass'/" "/var/www/$target_domain/public_html/wp-config.php"
        fi
    fi
    
    # RESTORE DB
    if [ -n "$db_file" ]; then
        log_info "Đang import Database..."
        if [[ "$db_file" == *.gz ]]; then
            zcat "$backup_dir/$db_file" | mysql "$target_db_name"
        else
            mysql "$target_db_name" < "$backup_dir/$db_file"
        fi
        
        log_info "Tự động sửa lỗi Database..."
        mysqlcheck --auto-repair "$target_db_name"
        
        # Auto fix Table Prefix
        log_info "Đang kiểm tra Table Prefix..."
        detected_table=$(mysql -N -B -e "SHOW TABLES LIKE '%_users'" "$target_db_name" | head -n 1)
        if [ -n "$detected_table" ]; then
            new_prefix=${detected_table%users}
            if [ -n "$new_prefix" ]; then
                log_info "Prefix phát hiện: '$new_prefix'. Cập nhật wp-config.php..."
                sed -i "s/\\\$table_prefix\s*=\s*'.*';/\\\$table_prefix = '$new_prefix';/" "/var/www/$target_domain/public_html/wp-config.php"
            fi
        fi
    fi
    
    # SEARCH & REPLACE (Migration)
    if [[ "$target_domain" != "$source_domain" ]]; then
        log_info "Phát hiện thay đổi tên miền ($source_domain -> $target_domain)."
        log_info "Đang thay thế URL trong Database..."
        
        # Install wp-cli if needed
        if ! command -v wp &> /dev/null; then
             curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
             chmod +x wp-cli.phar
             mv wp-cli.phar /usr/local/bin/wp
        fi
        
        cd "/var/www/$target_domain/public_html"
        # Run search-replace allow-root
        # Try http and https permutations
        wp search-replace "http://$source_domain" "http://$target_domain" --allow-root
        wp search-replace "https://$source_domain" "https://$target_domain" --allow-root
        wp search-replace "$source_domain" "$target_domain" --allow-root
        
        log_info "Đã thay thế URL xong."
    fi
    
    log_info "Restore hoàn tất!"
    pause
}

restore_site_gdrive() {
    # Select site from list
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
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
