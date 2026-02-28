#!/bin/bash

# core/mysql_helpers.sh - MySQL Database Helpers

# Initialize MySQL connection credentials
# output: exports MYSQL_CMD_PREFIX (e.g., "mysql -u root -pPASS")
ensure_mysql_access() {
    # If we already have a working command, return
    if [ -n "$MYSQL_CMD_PREFIX" ]; then
        return 0
    fi

    local cmd="mysql"
    
    # 1. Try socket/no-password (unix_socket)
    if $cmd -e "SELECT 1" &>/dev/null; then
        export MYSQL_CMD_PREFIX="$cmd"
        return 0
    fi
    
    # 2. Try .my.cnf
    if [ -f ~/.my.cnf ]; then
        export MYSQL_CMD_PREFIX="$cmd"
        return 0
    fi

    # 3. Check env var
    if [ -n "$MYSQL_ROOT_PASS" ]; then
         export MYSQL_PWD="$MYSQL_ROOT_PASS"
         if $cmd -e "SELECT 1" &>/dev/null; then
             export MYSQL_CMD_PREFIX="$cmd"
             return 0
         fi
         unset MYSQL_PWD
    fi

    # 4. Prompt user (INTERACTIVE ONLY)
    # Only prompt if we are in an interactive shell
    if [ -t 0 ]; then
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
    
    $MYSQL_CMD_PREFIX -e "$query" 2>/dev/null
}

# Check if database exists
db_exists() {
    local db_name=$1
    # Check if DB exists by querying information_schema
    # This prevents 'USE db' error from masking connection errors
    ensure_mysql_access || return 1
    
    local exists=$($MYSQL_CMD_PREFIX -Nse "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '$db_name';" 2>/dev/null)
    if [ "$exists" == "1" ]; then
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

    if db_exists "$db_name"; then
        log_warn "Database $db_name already exists"
        return 1
    fi
    
    # Commands
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
    
    ensure_mysql_access || return 1

    mysql_exec "DROP DATABASE IF EXISTS ${db_name};" 2>/dev/null
    mysql_exec "DROP USER IF EXISTS '${db_user}'@'localhost';" 2>/dev/null
    mysql_exec "FLUSH PRIVILEGES;" 2>/dev/null
}
