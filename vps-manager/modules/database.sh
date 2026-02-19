#!/bin/bash

# modules/database.sh - Database Management

database_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Database${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Danh sách Database"
    echo -e "2. Thêm Database & User"
    echo -e "3. Xóa Database"
    echo -e "4. Đổi mật khẩu DB User"
    echo -e "5. Import Database (.sql)"
    echo -e "6. Export Database (Dump)"
    echo -e "7. 🔍 Xem DB theo Website (WordPress)"
    echo -e "8. Quản lý phpMyAdmin"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-8]: " choice

    case $choice in
        1) list_databases ;;
        2) add_database ;;
        3) delete_database ;;
        4) change_db_pass ;;
        5) import_database ;;
        6) export_database ;;
        7) view_db_by_website ;;
        8) 
            source "$ROOT_DIR/modules/phpmyadmin.sh"
            phpmyadmin_menu 
            ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

list_databases() {
    echo -e "${GREEN}Danh sách Database:${NC}"
    mysql -e "SHOW DATABASES;"
    echo ""
    echo -e "${GREEN}Dung lượng Database:${NC}"
    mysql -e "SELECT table_schema 'DB Name', ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) 'Size in MB' FROM information_schema.tables GROUP BY table_schema;"
    pause
}

add_database() {
    read -p "Nhập tên Database mới: " db_name
    read -p "Nhập tên User mới: " db_user
    read -p "Nhập Mật khẩu: " db_pass

    mysql -e "CREATE DATABASE ${db_name};"
    mysql -e "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    log_info "Đã tạo Database $db_name và User $db_user."
    pause
}

delete_database() {
    read -p "Nhập tên Database cần xóa: " db_name
    read -p "Xác nhận xóa $db_name? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        mysql -e "DROP DATABASE ${db_name};"
        log_info "Đã xóa $db_name."
    fi
    pause
}

change_db_pass() {
    read -p "Nhập tên DB User: " db_user
    read -p "Nhập mật khẩu mới: " new_pass
    
    mysql -e "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${new_pass}';"
    mysql -e "FLUSH PRIVILEGES;"
    log_info "Đã đổi mật khẩu cho user $db_user."
    pause
}

import_database() {
    read -p "Nhập tên Database đích: " db_name
    read -p "Đường dẫn file .sql: " sql_file
    
    if [ ! -f "$sql_file" ]; then
        echo -e "${RED}File không tồn tại!${NC}"
        pause; return
    fi
    
    log_info "Đang import..."
    pv "$sql_file" | mysql "$db_name" 2>/dev/null || mysql "$db_name" < "$sql_file"
    log_info "Import hoàn tất."
    pause
}

export_database() {
    read -p "Nhập tên Database cần export: " db_name
    local dump_file="/root/${db_name}_$(date +%F_%T).sql"
    
    log_info "Đang export ra $dump_file..."
    mysqldump "$db_name" > "$dump_file"
    log_info "Export hoàn tất."
    pause
}

view_db_by_website() {
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}     Database Credentials theo Website${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    
    echo -e "${YELLOW}💡 Tip: Data được lấy từ file lưu trữ hệ thống hoặc wp-config.php${NC}"
    
    local data_file="$HOME/.vps-manager/sites_data.conf"
    local found=0   # FIX: initialize found counter
    
    # Loop through all websites in /var/www
    for site_dir in /var/www/*; do
        if [ -d "$site_dir" ]; then
            local domain=$(basename "$site_dir")
            local wp_config="$site_dir/public_html/wp-config.php"
            
            # Skip system folders
            if [[ "$domain" == "html" ]]; then continue; fi
            
            # 1. Try reading from Local Config Store (Most Reliable)
            local db_info=""
            if [ -f "$data_file" ]; then
                db_info=$(grep "^$domain|" "$data_file")
            fi
            
            local db_name=""
            local db_user=""
            local db_pass=""
            local source="System Store"
            
            if [ -n "$db_info" ]; then
                db_name=$(echo "$db_info" | cut -d'|' -f2)
                db_user=$(echo "$db_info" | cut -d'|' -f3)
                db_pass=$(echo "$db_info" | cut -d'|' -f4)
            # 2. Fallback to reading wp-config.php (Robust Grep)
            elif [ -f "$wp_config" ]; then
                source="wp-config.php"
                # Use robust grep, do NOT use php execution which can print HTML errors
                db_name=$(grep "DB_NAME" "$wp_config" | cut -d "'" -f 4)
                if [ -z "$db_name" ]; then db_name=$(grep "DB_NAME" "$wp_config" | cut -d '"' -f 4); fi
                
                db_user=$(grep "DB_USER" "$wp_config" | cut -d "'" -f 4)
                if [ -z "$db_user" ]; then db_user=$(grep "DB_USER" "$wp_config" | cut -d '"' -f 4); fi
                
                db_pass=$(grep "DB_PASSWORD" "$wp_config" | cut -d "'" -f 4)
                if [ -z "$db_pass" ]; then db_pass=$(grep "DB_PASSWORD" "$wp_config" | cut -d '"' -f 4); fi
            else
                continue
            fi
            
            # Display info
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}🌐 Website:${NC} ${GREEN}$domain${NC} ($source)"
            echo -e "${YELLOW}📦 Database:${NC} $db_name"
            echo -e "${YELLOW}👤 User:${NC} $db_user"
            echo -e "${YELLOW}🔑 Password:${NC} $db_pass"
                
                # Get database size
                local db_size=$(mysql -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema = '$db_name';" 2>/dev/null | tail -1)
                if [ -n "$db_size" ] && [ "$db_size" != "NULL" ]; then
                    echo -e "${YELLOW}💾 Size:${NC} ${db_size} MB"
                fi
                
                echo ""
                found=$((found + 1))  # FIX: increment counter
            fi
        fi
    done
    
    if [ $found -eq 0 ]; then
        echo -e "${YELLOW}Không tìm thấy WordPress site nào.${NC}"
        echo ""
    fi
    
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${YELLOW}💡 Tip: Copy credentials này để config wp-config.php${NC}"
    echo ""
    pause
}
