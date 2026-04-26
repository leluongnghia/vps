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

    if [[ -f "$sysctl_file" ]] && grep -q "vps-manager" "$sysctl_file" 2>/dev/null; then
        log_info "Kernel TCP đã được tối ưu từ trước. Bỏ qua."
        return 0
    fi

    log_info "Áp dụng tối ưu Kernel TCP/Network..."

    # Tính hashsize = nf_conntrack_max / 4 (524288 / 4 = 131072)
    if [[ ! -f /proc/user_beancounters ]]; then  # Bỏ qua nếu là OpenVZ (ảo hóa 1 phần)
        if [[ -d /etc/sysctl.d ]]; then

            echo 131072 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
            if [[ ! -f /etc/modprobe.d/nf_conntrack.conf ]]; then
                echo 'options nf_conntrack hashsize=131072' > /etc/modprobe.d/nf_conntrack.conf
            fi

            # Ghi hashsize vào rc.local để bền vĩnh
            if ! grep -q "nf_conntrack/parameters/hashsize" /etc/rc.local 2>/dev/null; then
                echo "echo 131072 > /sys/module/nf_conntrack/parameters/hashsize" >> /etc/rc.local
            fi

            cat > "$sysctl_file" << 'EOF'
# vps-manager — Kernel TCP/Network Optimization
# Tham khảo: Premium guidelines

# Process & File
kernel.pid_max = 65536
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
net.core.optmem_max = 8192

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
net.ipv4.tcp_limit_output_bytes = 65536
net.ipv4.tcp_rfc1337 = 1
net.ipv4.ip_local_port_range = 1024 65535

# BBR Congestion Control (tốc độ truyền cao, giảm latency)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# Memory management
vm.swappiness = 10
vm.min_free_kbytes = 65536
vm.vfs_cache_pressure = 150

# conntrack
net.netfilter.nf_conntrack_helper = 0
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

    # Ghi vào rc.local để bền vĩnh
    if ! grep -q "ulimit -n 524288" /etc/rc.local 2>/dev/null; then
        echo "ulimit -n 524288" >> /etc/rc.local 2>/dev/null || true
    fi

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
# Tính toán thông số OLS theo RAM (Auto-scaling)
# ==============================================================================

calc_ols_tuning_params() {
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local cpu_cores
    cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)

    # Buffer size cho inMemBufSize (OLS in-RAM buffer)
    local buffer_size mmap_cache_size ka_timeout ka_reqs max_client

    if   [[ "$total_ram_mb" -le 1200 ]]; then
        buffer_size="64M";  mmap_cache_size="20M";  ka_timeout=15;  ka_reqs=1000
    elif [[ "$total_ram_mb" -le 2500 ]]; then
        buffer_size="128M"; mmap_cache_size="40M";  ka_timeout=30;  ka_reqs=3000
    elif [[ "$total_ram_mb" -le 4500 ]]; then
        buffer_size="192M"; mmap_cache_size="80M";  ka_timeout=45;  ka_reqs=5000
    elif [[ "$total_ram_mb" -le 8500 ]]; then
        buffer_size="256M"; mmap_cache_size="80M";  ka_timeout=45;  ka_reqs=8000
    else
        buffer_size="384M"; mmap_cache_size="80M";  ka_timeout=60;  ka_reqs=10000
    fi

    max_client=$(( 1024 * cpu_cores * 2 ))
    local max_client_max=$(( 1024 * cpu_cores * 3 ))
    local lsphp_children=$(( cpu_cores * 2 ))

    # Export để dùng trong _configure_ols_base_advanced
    export OLS_BUFFER_SIZE="$buffer_size"
    export OLS_MMAP_CACHE="$mmap_cache_size"
    export OLS_KA_TIMEOUT="$ka_timeout"
    export OLS_KA_REQS="$ka_reqs"
    export OLS_MAX_CONN="$max_client_max"
    export OLS_LSPHP_CHILDREN="$lsphp_children"
    export OLS_CPU_CORES="$cpu_cores"
    export OLS_RAM_MB="$total_ram_mb"
}

# ==============================================================================
# Tính toán thông số MariaDB theo RAM
# ==============================================================================

calc_mariadb_tuning_params() {
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local cpu_cores
    cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
    local total_ram_gb=$(( total_ram_mb / 1024 ))

    # Innodb buffer: 25% RAM
    local innodb_buffer=$(( total_ram_mb / 4 ))
    local key_buffer=$(( total_ram_mb / 6 ))
    local db_table_size=$(( total_ram_gb * 64 ))
    local max_connections=$(( 64 * total_ram_gb ))
    local max_allowed_packet=64

    # Tối thiểu cho VPS nhỏ < 1GB
    if [[ "$total_ram_mb" -lt 1024 ]]; then
        innodb_buffer=48; key_buffer=32; db_table_size=32; max_connections=300
    fi

    # query_cache: tắt nếu > 2 CPU (MariaDB 10.8+ deprecated)
    local query_cache_type=0
    local query_cache_size=0
    if [[ "$cpu_cores" -le 2 ]]; then
        query_cache_type=1; query_cache_size="50M"
    fi

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
