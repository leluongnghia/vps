#!/bin/bash

# core/kernel_tuning.sh - Tối ưu Kernel TCP/Network
# Áp dụng cho cả Nginx stack và OLS stack

# ==============================================================================
# Tắt Transparent Huge Pages (THP)
# THP gây lag cho MariaDB, Redis/Valkey, OLS vì chúng truy xuất dữ liệu nhỏ
# ==============================================================================

disable_thp() {
    if grep -q "vps-manager-thp" /etc/systemd/system/disable-thp.service 2>/dev/null; then
        log_info "THP đã được tắt từ trước. Bỏ qua."
        return 0
    fi

    log_info "Tắt Transparent Huge Pages (THP) để tối ưu MariaDB/Cache..."

    # Tắt ngay lập tức
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

    # Tạo systemd service để tắt THP vĩnh viễn sau mỗi lần reboot
    cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP) for VPS Manager
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mariadb.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true'
# vps-manager-thp

[Install]
WantedBy=basic.target
EOF

    systemctl daemon-reload
    systemctl enable --now disable-thp.service > /dev/null 2>&1
    log_info "✓ THP đã tắt và ghi vào boot service."
}

# ==============================================================================
# CPU Governor — Ép CPU chạy tần số cao nhất
# ==============================================================================

set_cpu_performance_governor() {
    # Dùng tuned nếu có (AlmaLinux, Rocky)
    if command -v tuned-adm &>/dev/null; then
        tuned-adm profile latency-performance > /dev/null 2>&1
        log_info "✓ CPU Governor: latency-performance (tuned-adm)"
        return
    fi

    # Ubuntu/Debian: cpufrequtils
    if command -v cpufreq-set &>/dev/null; then
        for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
            echo "performance" > "$cpu" 2>/dev/null || true
        done
        log_info "✓ CPU Governor: performance"
    fi
}

# ==============================================================================
# Kernel TCP/Network Tuning chuyên sâu
# Dựa trên công thức Premium
# ==============================================================================

tune_kernel_tcp() {
    local sysctl_file="/etc/sysctl.d/101-vps-manager.conf"

    # Đánh dấu phiên bản bộ tham số: khi bộ tham số thay đổi, server cũ được ghi lại file thay vì bỏ qua
    local tuning_rev="vps-manager-sysctl-rev2"
    if [[ -f "$sysctl_file" ]] && grep -q "$tuning_rev" "$sysctl_file" 2>/dev/null; then
        log_info "Kernel TCP đã được tối ưu từ trước. Bỏ qua."
        return 0
    fi

    log_info "Áp dụng tối ưu Kernel TCP/Network..."

    # vm.min_free_kbytes theo RAM (~1.5%, 16MB..64MB): 64MB cố định là quá nhiều với VPS 512MB-1GB
    local ram_kb min_free_kb
    ram_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
    [[ -z "$ram_kb" ]] && ram_kb=1048576
    min_free_kb=$(( ram_kb * 15 / 1000 ))
    [[ "$min_free_kb" -lt 16384 ]] && min_free_kb=16384
    [[ "$min_free_kb" -gt 65536 ]] && min_free_kb=65536

    # Tính hashsize = nf_conntrack_max / 4 (524288 / 4 = 131072)
    if [[ ! -f /proc/user_beancounters ]]; then  # Bỏ qua nếu là OpenVZ (ảo hóa 1 phần)
        if [[ -d /etc/sysctl.d ]]; then

            echo 131072 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
            # modprobe.d giữ hashsize qua các lần reboot (không cần /etc/rc.local)
            if [[ ! -f /etc/modprobe.d/nf_conntrack.conf ]]; then
                echo 'options nf_conntrack hashsize=131072' > /etc/modprobe.d/nf_conntrack.conf
            fi

            cat > "$sysctl_file" << EOF
# vps-manager — Kernel TCP/Network Optimization
# ${tuning_rev}

# Process & File
# (không đặt kernel.pid_max / net.core.optmem_max / tcp_limit_output_bytes:
#  giá trị mặc định của kernel hiện đại cao hơn các con số từng ghi ở đây)
kernel.printk = 4 1 1 7
fs.nr_open = 12000000
fs.file-max = 9000000

# Socket buffers
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
net.ipv4.tcp_rmem = 8192 87380 16777216
net.ipv4.tcp_wmem = 8192 65536 16777216
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535

# TCP performance
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_time = 240
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_sack = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_rfc1337 = 1
net.ipv4.ip_local_port_range = 1024 65535

# BBR Congestion Control (tốc độ truyền cao, giảm latency)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# Memory management
# (khi bật ZRAM, /etc/sysctl.d/99-vps-manager-zram.conf nạp sau file này và đặt swappiness = 100)
vm.swappiness = 10
vm.min_free_kbytes = ${min_free_kb}

# conntrack
net.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_tcp_timeout_established = 28800
net.netfilter.nf_conntrack_generic_timeout = 60

# Security (hardening)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# TCP misc
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024
net.unix.max_dgram_qlen = 4096

# Panic recovery
kernel.panic = 10
EOF

            # Thêm AMD EPYC specific nếu detect CPU này
            if grep -q "AMD EPYC" /proc/cpuinfo 2>/dev/null; then
                echo "kernel.watchdog_thresh = 20" >> "$sysctl_file"
                log_info "✓ Phát hiện CPU AMD EPYC — đã điều chỉnh watchdog_thresh."
            fi

            # Áp dụng ngay
            /sbin/sysctl --system > /dev/null 2>&1
            log_info "✓ Kernel TCP/Network đã được tối ưu."
        fi
    else
        log_warn "OpenVZ/LXC environment — bỏ qua tuning kernel (không có quyền)."
    fi
}

# ==============================================================================
# File Descriptor limits
# ==============================================================================

tune_file_limits() {
    if grep -q "524288" /etc/security/limits.conf 2>/dev/null; then
        return 0
    fi

    log_info "Nâng giới hạn file descriptor..."
    cat >> /etc/security/limits.conf << 'EOF'
# vps-manager limits
* soft nofile 524288
* hard nofile 524288
EOF
    # Áp dụng ngay trong session hiện tại
    ulimit -n 524288 2>/dev/null || true

    # limits.conf chỉ áp dụng cho phiên đăng nhập (PAM). Service do systemd chạy cần LimitNOFILE riêng.
    local svc
    for svc in nginx mariadb; do
        if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "^${svc}\.service"; then
            mkdir -p "/etc/systemd/system/${svc}.service.d"
            printf '[Service]\nLimitNOFILE=524288\n' > "/etc/systemd/system/${svc}.service.d/vps-manager-limits.conf"
        fi
    done
    systemctl daemon-reload 2>/dev/null || true

    # /etc/security/limits.d/20-nproc.conf cho RHEL-based
    if [[ -f /etc/security/limits.d/20-nproc.conf ]]; then
        cat > /etc/security/limits.d/20-nproc.conf << 'EOF'
# vps-manager nproc limits
*          soft    nproc     8192
*          hard    nproc     8192
nobody     soft    nproc     32278
nobody     hard    nproc     32278
root       soft    nproc     unlimited
EOF
    fi

    log_info "✓ File descriptor limits đã được nâng lên 524288."
}

# ==============================================================================
# Tính toán thông số MariaDB theo RAM
# ==============================================================================

calc_mariadb_tuning_params() {
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local cpu_cores
    cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)

    # Cùng công thức với _tune_mariadb_config trong modules/lemp.sh (một nguồn số liệu duy nhất):
    # InnoDB 25% RAM; phần còn lại dành cho PHP-FPM (~40%), object cache và hệ điều hành.
    local innodb_buffer=$(( total_ram_mb / 4 ))
    local key_buffer=16          # chỉ phục vụ MyISAM; WordPress dùng InnoDB
    local db_table_size=$(( total_ram_mb / 128 ))
    local max_connections=$(( total_ram_mb / 50 ))

    [[ "$innodb_buffer" -lt 64 ]] && innodb_buffer=64
    [[ "$db_table_size" -lt 16 ]] && db_table_size=16
    [[ "$db_table_size" -gt 64 ]] && db_table_size=64
    [[ "$max_connections" -lt 30 ]] && max_connections=30
    [[ "$max_connections" -gt 150 ]] && max_connections=150

    # Query cache tắt hẳn: đã deprecated, gây tranh chấp khoá; object cache (Valkey/Redis) làm tốt hơn.
    local query_cache_type=0
    local query_cache_size=0

    export DB_INNODB_BUFFER="${innodb_buffer}M"
    export DB_KEY_BUFFER="${key_buffer}M"
    export DB_TABLE_SIZE="${db_table_size}M"
    export DB_MAX_CONNECTIONS="$max_connections"
    export DB_QUERY_CACHE_TYPE="$query_cache_type"
    export DB_QUERY_CACHE_SIZE="$query_cache_size"
}

# ==============================================================================
# Entry point: chạy toàn bộ tối ưu hệ thống
# ==============================================================================

run_system_optimization() {
    echo -e "${CYAN}[System] Tối ưu hóa hệ thống toàn diện...${NC}"
    disable_thp
    tune_file_limits
    tune_kernel_tcp
    set_cpu_performance_governor
    echo -e "${GREEN}[System] ✓ Tối ưu hóa hoàn tất!${NC}"
}
