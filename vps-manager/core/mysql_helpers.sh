#!/bin/bash

# core/mysql_helpers.sh - MySQL Database Helpers

# Get MySQL connection command with proper credentials
get_mysql_cmd() {
    # Try unix_socket first (most common on Ubuntu)
    if mysql -e "SELECT 1" &>/dev/null; then
        echo "mysql"
        return 0
    fi
    
    # Try with .my.cnf
    if [ -f ~/.my.cnf ]; then
        echo "mysql"
        return 0
    fi
    
    # Need password - check if we have it cached
    if [ -n "$MYSQL_ROOT_PASS" ]; then
        echo "mysql -p$MYSQL_ROOT_PASS"
        return 0
    fi
    
    # Prompt for password
    log_warn "MySQL root password required"
    read -sp "Enter MySQL root password: " MYSQL_ROOT_PASS
    echo ""
    export MYSQL_ROOT_PASS
    
    # Test connection
    if mysql -p"$MYSQL_ROOT_PASS" -e "SELECT 1" &>/dev/null; then
        echo "mysql -p$MYSQL_ROOT_PASS"
        return 0
    else
        log_error "Invalid MySQL password"
        unset MYSQL_ROOT_PASS
        return 1
    fi
}

# Execute MySQL command safely
mysql_exec() {
    local query=$1
    local mysql_cmd=$(get_mysql_cmd)
    
    if [ -z "$mysql_cmd" ]; then
        return 1
    fi
    
    $mysql_cmd -e "$query" 2>/dev/null
}

# Check if database exists
db_exists() {
    local db_name=$1
    mysql_exec "USE $db_name" &>/dev/null
}

# Create database safely
create_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    if db_exists "$db_name"; then
        log_warn "Database $db_name already exists"
        return 1
    fi
    
    mysql_exec "CREATE DATABASE ${db_name};" || return 1
    mysql_exec "CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" || return 1
    mysql_exec "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';" || return 1
    mysql_exec "FLUSH PRIVILEGES;" || return 1
    
    log_info "Database created: $db_name"
    return 0
}

# Drop database safely
drop_database() {
    local db_name=$1
    local db_user=$2
    
    mysql_exec "DROP DATABASE IF EXISTS ${db_name};" 2>/dev/null
    mysql_exec "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null
    mysql_exec "FLUSH PRIVILEGES;" 2>/dev/null
}
