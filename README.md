# 🖥️ VPS Manager — Quản lý VPS Tự động (Premium Grade Nginx Stack)

[![Version](https://img.shields.io/badge/Version-1.6.0-brightgreen.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20AlmaLinux-orange.svg)](#)

[🇻🇳 Tiếng Việt](#giới-thiệu-tiếng-việt) | [🇬🇧 English](#introduction-english)

---

<a name="giới-thiệu-tiếng-việt"></a>

## ⚡ Cài đặt nhanh (Nginx LEMP Stack)

> Hệ thống được chuẩn hóa 100% sang Nginx LEMP Stack, tự động tối ưu Kernel, System, ZRAM, và cấu hình Cache 2 lớp ngay khi cài đặt.

```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
```

> 💡 Sau khi cài đặt hoàn tất, gõ lệnh `vps` từ terminal bất kỳ lúc nào để mở Menu quản lý.

---

## 🚀 Quy trình Tối ưu hóa Hệ thống (Premium Grade)

Để đạt hiệu suất cao nhất (Điểm số PageSpeed tối ưu, TTFB thấp nhất), VPS Manager thực hiện đồng bộ 4 bước tối ưu chuyên sâu:

### Bước 1: Tối ưu hóa Kernel & Network (Hệ thống)
- **Tắt Transparent Huge Pages (THP):** Ngăn ngừa lag và đột biến độ trễ (latency spikes) cho MariaDB và Valkey/Redis.
- **Bật TCP BBR:** Tối ưu hóa tốc độ truyền tải mạng và giảm thiểu packet loss.
- **CPU Performance Mode:** Ép các lõi CPU chạy ở tần suất hiệu năng tối đa.
- **File Descriptor Limits:** Nâng giới hạn file descriptor lên 524,288 để xử lý mượt mà hàng chục ngàn kết nối đồng thời.

### Bước 2: Tối ưu hóa Web Server & PHP
- **Cache 2 Lớp tối tân:**
  - **L1 (FastCGI Cache):** Nginx lưu trữ và phân phối HTML tĩnh trực tiếp cho khách vãng lai, bypass hoàn toàn PHP để giảm tải CPU.
  - **L2 (Object Cache qua Unix Socket):** Sử dụng Valkey/Redis kết nối qua Unix Socket (nhanh hơn TCP từ 30% - 50%) để lưu trữ database queries.
- **HTTP/2 & Brotli Compression:** Nén dữ liệu tối ưu, tăng tốc tải trang trên thiết bị di động.

### Bước 3: Tối ưu hóa Cơ sở dữ liệu (MariaDB)
- **Auto-scaling RAM:** Tự động tính toán và điều chỉnh tham số `innodb_buffer_pool_size` bằng 25% - 40% RAM thực tế.
- **Bảo mật cơ sở dữ liệu:** Đổi tên user mặc định `root` thành `wpdbadmin` nhằm ngăn chặn brute-force tấn công và ẩn cổng kết nối.

### Bước 4: Tích hợp bảo mật 7G/8G WAF & Fail2ban
- Tích hợp sẵn bộ quy tắc tường lửa ứng dụng web **7G/8G WAF** ngay trong Nginx để chặn spam, SQL injection, XSS.
- Giám sát hệ thống tự động qua **Monit Watchdog** tự khởi động lại Nginx, PHP, MariaDB nếu gặp sự cố crash.

---

## 📋 Menu Quản lý (Các tính năng chính)

| Tính năng | Mô tả |
|-----------|-------|
| 🌐 **Quản lý Nginx** | Chỉnh sửa nhanh config chung, vhost từng domain, kiểm tra cấu hình (`nginx -t`) |
| 📁 **Quản lý Website** | Thêm, xóa site WordPress tự động, cấu hình SSL Let's Encrypt miễn phí |
| 💾 **Quản lý Cache** | Cài đặt và quản lý Valkey / Redis Unix Socket cho Object Cache |
| 🗄️ **Tối ưu MySQL/MariaDB** | Tự động cân chỉnh các bộ đệm database dựa theo dung lượng RAM thực tế |
| 🛡️ **Bảo mật & WAF** | Bật tắt 7G/8G WAF, chặn IP theo quốc gia (GeoIP), cấu hình Fail2ban |
| ⚡ **Fix TBT & Render-Blocking** | MU-Plugin chuyên sâu hỗ trợ dọn dẹp CSS/JS render-blocking cho Elementor, FontAwesome |

---

## 📋 Yêu cầu Hệ thống

- **Hệ điều hành:** Ubuntu 20.04 / 22.04 / 24.04 (Khuyên dùng), Debian 11 / 12, AlmaLinux 8 / 9, Rocky Linux.
- **Cấu hình tối thiểu:** RAM từ 1GB trở lên (Khuyên dùng 2GB+ để vận hành hiệu quả Valkey/Redis Object Cache).
- **Quyền hạn:** Truy cập quyền root cao nhất (`sudo su`).

---

## 🗂️ Cấu trúc dự án v1.6.0

```
vps-manager/
├── install-nginx.sh        # Lệnh cài đặt nhanh Nginx Stack từ xa
├── install.sh              # File thực thi cài đặt & Menu khởi tạo
├── core/
│   ├── kernel_tuning.sh    # Tối ưu hóa thông số nhân Kernel TCP
│   ├── system_helpers.sh   # Tiện ích hệ thống
│   └── menu.sh             # Menu quản lý vps tập trung
├── modules/
│   ├── nginx.sh            # Quản lý cấu hình Nginx
│   ├── lemp.sh             # Cài đặt PHP, MariaDB, phpMyAdmin
│   ├── wordpress_performance.sh # Tối ưu hóa hiệu năng WordPress chuyên sâu
│   ├── security.sh         # Cấu hình WAF 7G/8G, tường lửa
│   └── ...
```

---

<a name="introduction-english"></a>

# 🇬🇧 English Introduction

VPS Manager is a professional, high-performance Bash script to automate and optimize Nginx LEMP stack servers on Ubuntu/Debian/AlmaLinux.

### Quick Install
```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
```

### Key Features (v1.6.0)
- **100% Nginx Standardized:** Cleaned up and completely removed OpenLiteSpeed to focus purely on high-performance Nginx.
- **Kernel & Network Tuning:** Auto-configures TCP BBR, disables THP, sets CPU governor to performance, and boosts file descriptor limits.
- **2-Layer Cache Architecture:** Integrates L1 Nginx FastCGI micro-cache with L2 Valkey/Redis Object Cache over Unix Socket.
- **Dynamic Resource Scaling:** Auto-calculates MariaDB buffer pool sizes and PHP-FPM workers based on physical RAM.
- **Built-in Security WAF:** Out-of-the-box support for 7G/8G Nginx WAF, GeoIP blocking, and Fail2ban setup.

---
> **Copyright**: © 2024-2026 leluongnghia. Optimized to Premium Grade Standards.
