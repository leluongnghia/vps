#!/bin/bash

# core/mysql_helpers.sh - MySQL Database Helpers

# Initialize MySQL connection credentials
# output: exports MYSQL_CMD_PREFIX (e.g., "mysql -u root -pPASS")
ensure_mysql_access() {
    # If we already have a working command, return
    if [[ -n "${MYSQL_CMD_PREFIX:-}" ]]; then
        return 0
    fi

    local cmd="mysql"

    # 1. Try socket/no-password (unix_socket) hoặc ~/.my.cnf — đều phải kết nối được thật
    if $cmd -e "SELECT 1" &>/dev/null; then
        export MYSQL_CMD_PREFIX="$cmd"
        return 0
    fi

    # 3. Check env var
    if [[ -n "${MYSQL_ROOT_PASS:-}" ]]; then
         export MYSQL_PWD="$MYSQL_ROOT_PASS"
         if $cmd -e "SELECT 1" &>/dev/null; then
             export MYSQL_CMD_PREFIX="$cmd"
             return 0
         fi
         unset MYSQL_PWD
    fi

    # 4. Prompt user (INTERACTIVE ONLY)
    # Only prompt if we are in an interactive shell
    if [[ -t 0 ]]; then
        log_warn "MySQL root password required for database operations."
        read -sp "Enter MySQL root password: " input_pass
        echo ""
        
        export MYSQL_PWD="$input_pass"
        if $cmd -e "SELECT 1" &>/dev/null; then
            export MYSQL_ROOT_PASS="$input_pass"
            export MYSQL_CMD_PREFIX="$cmd"
            return 0
        else
            unset MYSQL_PWD
            log_error "Invalid MySQL password!"
            return 1
        fi
    else
        log_error "MySQL authentication failed (Non-interactive mode)."
        return 1
    fi
}

# Execute MySQL command safely
mysql_exec() {
    local query=$1
    # Ensure we have access (attempts to set MYSQL_CMD_PREFIX)
    ensure_mysql_access || return 1
    
    # SQL đi qua stdin (không nằm trên dòng lệnh) để mật khẩu không lộ trong `ps`
    $MYSQL_CMD_PREFIX <<< "$query"
}

# Escape 1 giá trị để đặt trong dấu nháy đơn của câu SQL
sql_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

# Check if database exists
db_exists() {
    local db_name=$1
    # Check if DB exists by querying information_schema
    # This prevents 'USE db' error from masking connection errors
    ensure_mysql_access || return 1
    
    [[ "$db_name" =~ ^[A-Za-z0-9_]{1,64}$ ]] || return 1
    local exists=$($MYSQL_CMD_PREFIX -Nse "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '$db_name';" 2>/dev/null)
    if [[ "$exists" == "1" ]]; then
        return 0
    else
        return 1
    fi
}

# Create database safely
create_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    ensure_mysql_access || return 1

    if ! [[ "$db_name" =~ ^[A-Za-z0-9_]{1,64}$ ]] || ! [[ "$db_user" =~ ^[A-Za-z0-9_]{1,80}$ ]]; then
        log_error "Tên database/user không hợp lệ (chỉ gồm chữ, số, gạch dưới): $db_name / $db_user"
        return 1
    fi

    if db_exists "$db_name"; then
        log_warn "Database $db_name already exists"
        return 1
    fi

    local esc_pass
    esc_pass=$(sql_escape "$db_pass")

    # Commands
    mysql_exec "CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
    mysql_exec "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${esc_pass}';" || return 1
    mysql_exec "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${esc_pass}';" || return 1
    mysql_exec "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';" || return 1
    mysql_exec "FLUSH PRIVILEGES;" || return 1
    
    log_info "Database created: $db_name"
    return 0
}

# Drop database safely
drop_database() {
    local db_name=$1
    local db_user=$2
    
    ensure_mysql_access || return 1

    if ! [[ "$db_name" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
        log_error "Tên database không hợp lệ: '$db_name' - không xoá."
        return 1
    fi

    mysql_exec "DROP DATABASE IF EXISTS \`${db_name}\`;" 2>/dev/null
    if [[ "$db_user" =~ ^[A-Za-z0-9_]{1,80}$ ]]; then
        mysql_exec "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null
    fi
    mysql_exec "FLUSH PRIVILEGES;" 2>/dev/null
}

# Dump 1 database ra file .sql.gz và KIỂM TRA kết quả.
# Thành công khi: mysqldump exit 0, file nén hợp lệ, và có dòng "Dump completed".
# Dùng: dump_database <db_name> <file.sql.gz>
dump_database() {
    local db_name=$1 out=$2
    local tmp="${out}.partial"
    if ! [[ "$db_name" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
        log_error "Tên database không hợp lệ: '$db_name'"
        return 1
    fi
    mysqldump --single-transaction --quick --routines --triggers "$db_name" 2>"${out}.err" | gzip > "$tmp"
    local rc=("${PIPESTATUS[@]}")
    if [[ "${rc[0]}" -ne 0 || "${rc[1]}" -ne 0 ]] || ! gzip -t "$tmp" 2>/dev/null \
        || ! zcat "$tmp" 2>/dev/null | tail -n 3 | grep -q "Dump completed"; then
        log_error "Dump database '$db_name' THẤT BẠI: $(head -n 2 "${out}.err" 2>/dev/null)"
        rm -f "$tmp" "${out}.err"
        return 1
    fi
    rm -f "${out}.err"
    mv -f "$tmp" "$out"
}

# Kiểm tra 1 file dump (.sql hoặc .sql.gz) có dùng được không trước khi restore
verify_sql_dump() {
    local f=$1
    [[ -s "$f" ]] || return 1
    if [[ "$f" == *.gz ]]; then
        gzip -t "$f" 2>/dev/null || return 1
        zcat "$f" 2>/dev/null | head -c 65536 | grep -qiE "CREATE TABLE|INSERT INTO|MySQL dump|MariaDB dump"
    else
        head -c 65536 "$f" | grep -qiE "CREATE TABLE|INSERT INTO|MySQL dump|MariaDB dump"
    fi
}
