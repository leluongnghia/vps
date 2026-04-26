# 🖥️ VPS Manager — Quản lý VPS Tự động

[![Version](https://img.shields.io/badge/Version-1.3.4-brightgreen.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20AlmaLinux-orange.svg)](#)

[🇻🇳 Tiếng Việt](#giới-thiệu-tiếng-việt) | [🇬🇧 English](#introduction-english)

---

## ⚡ Cài đặt nhanh / Quick Install

> Chọn **một trong hai** stack phù hợp với nhu cầu của bạn:

### 🌐 Stack 1 — Nginx (LEMP: Nginx + MariaDB + PHP)
*Ổn định, chịu tải cao, phù hợp server general-purpose*

```bash
# curl
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)

# hoặc wget
bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
```

### ⚡ Stack 2 — OpenLiteSpeed (OLS + LSPHP + MariaDB + LSCache)
*Tốc độ ánh sáng cho WordPress, LSCache tích hợp sẵn*

```bash
# curl
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)

# hoặc wget
bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)
```

> 💡 Sau khi cài xong, gõ `vps` để mở menu quản lý bất kỳ lúc nào.
>
> 🔄 Muốn **chuyển đổi** giữa Nginx ↔ OLS sau khi đã cài? Vào menu `vps` → **Mục 24** (Di chuyển Máy chủ Web).

---

## 📊 So sánh 2 Stack

| Tiêu chí | 🌐 Nginx LEMP | ⚡ OpenLiteSpeed |
|----------|--------------|----------------|
| **Web Server** | Nginx | OpenLiteSpeed |
| **PHP** | PHP-FPM | LSPHP |
| **Cache** | FastCGI Cache / Redis | LSCache (tích hợp sẵn) |
| **Object Cache** | Valkey / Redis | Valkey / Redis |
| **WordPress tốc độ** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Độ ổn định** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Tài nguyên RAM** | Thấp | Trung bình |
| **Phù hợp** | Mọi loại ứng dụng | WordPress tối ưu |
| **Lệnh cài** | `install-nginx.sh` | `install-ols.sh` |

---

<a name="giới-thiệu-tiếng-việt"></a>

# 🇻🇳 Giới thiệu (Tiếng Việt)

Script Bash toàn diện giúp quản lý VPS **Ubuntu/Debian/AlmaLinux** qua menu tương tác, không cần nhớ lệnh phức tạp. Bao gồm **24 module** quản lý toàn bộ vòng đời server từ cài đặt đến bảo mật và backup.

---

## 📋 Menu Chính (24 Tùy chọn)

| # | Tính năng | Mô tả |
|---|-----------|--------|
| 1 | 🌐 **Cài đặt LEMP Stack (Nginx)** | Nginx + MariaDB + PHP + phpMyAdmin + Valkey |
| 2 | 🌐 **Quản lý Domain & Website** | Thêm/Xóa/Clone/Rename site, Parked domain, Redirect |
| 3 | 🔧 **Quản lý WordPress** | WP-CLI: Core/Plugin/User, Security, SEO, Database |
| 4 | 🛡️ **Bảo mật & Tối ưu hóa** | UFW, Fail2ban, SSH port, WAF, DDoS protection |
| 5 | 💾 **Sao lưu & Khôi phục** | Local, Google Drive, restore thông minh |
| 6 | 🐘 **Quản lý Phiên bản PHP** | Đổi version, cấu hình, extensions |
| 7 | ⏰ **Quản lý Cronjob** | Thêm/Xóa lịch chạy |
| 8 | 🔄 **Quản lý Services** | Khởi động lại/Stop Nginx, MySQL, PHP-FPM... |
| 9 | 🗃️ **Quản lý Database** | Tạo/Xóa DB, import/export, credentials |
| 10 | ⚡ **Quản lý Cache** | Redis/Valkey, FastCGI Cache, LSCache |
| 11 | 🧠 **Quản lý Swap** | RAM ảo File Swap, tối ưu swappiness |
| 12 | 💿 **Quản lý Ổ đĩa & Logs** | Dọn logs, kiểm tra disk usage |
| 13 | 🛠️ **AppAdmin & Công cụ bổ trợ** | Phpinfo, ứng dụng bổ trợ |
| 14 | 📐 **Quản lý Nginx (Cấu hình)** | nginx.conf, Virtual Hosts, fix lỗi tự động |
| 15 | 🔄 **Cập nhật Script** | Tự động nâng cấp từ GitHub |
| 16 | 🏥 **Chẩn đoán Hệ thống** | Health Check RAM/Disk/Services/Logs |
| 17 | 🚀 **Tối ưu WordPress Performance** | Tinh chỉnh cấp cao toàn hệ thống & website |
| 18 | 🗄️ **Quản lý phpMyAdmin** | Cài đặt tự động, HTTP Auth, URL ẩn |
| 19 | 🔒 **Quản lý SSL** | Let's Encrypt, Cloudflare Origin, ZeroSSL |
| 20 | ⏰ **Backup Tự động (Cron)** | Lập lịch backup source + DB hàng ngày/tuần |
| 21 | ⚡ **Cài đặt & Quản lý OpenLiteSpeed** | OLS + LSPHP + LSCache + WebAdmin |
| 22 | ⚡ **ZRAM Swap** | Swap nén trên RAM — nhanh x1000 |
| 23 | 🛡️ **Watchdog Giám sát (Monit)** | Tự động restart services khi crash |
| 24 | 🔄 **Di chuyển Máy chủ Web** | Chuyển đổi mượt mà Nginx ↔ OpenLiteSpeed |

---

## ✨ Tính năng Nổi bật

### 🚀 Cài đặt & Quản lý Website

- **2 Stack độc lập**: Nginx LEMP (`install-nginx.sh`) hoặc OpenLiteSpeed (`install-ols.sh`) — không trùng lặp chức năng
- **Quản lý Domain toàn diện**: Thêm, Xóa, Rename, Clone, Parked Domain, Redirect, **Bật/Tắt FastCGI Cache (Dev Mode)**
- **WordPress Manager**:
  - Cài đặt WordPress + Database an toàn tự động
  - WP-CLI tích hợp: Core/Plugin/Theme update, User management
  - Bảo mật: Tắt XML-RPC, File Edit, Giấu wp-config, Fix permissions
  - SEO Nginx rules (RankMath/Yoast)
  - Tạo Admin mới với password random

### ⚡ OpenLiteSpeed Stack (Menu 21)

- Cài đặt OLS + LSPHP (8.1 / 8.2 / 8.3 / 8.4 tuỳ chọn)
- **LSCache in-RAM** (64MB cache nhét thẳng vào RAM)
- **QUIC HTTP/3** bật sẵn
- WebAdmin Panel tự động sinh mật khẩu an toàn
- Tạo WordPress site trực tiếp với Virtual Host OLS
- Purge LSCache per-site hoặc toàn server
- Đổi LSPHP version per-site
- Unix Socket cho LSPHP (hiệu năng cao nhất)
- Tự động inject Valkey/Redis Object Cache vào `wp-config.php`

### 🔒 SSL Management (Menu 19)

- **Let's Encrypt** (Certbot) — miễn phí, tự động
- **Cloudflare Origin SSL** — hỗ trợ paste key từ dashboard
- **ZeroSSL** — qua acme.sh
- **Xem trạng thái SSL** tất cả domain + số ngày còn hạn
- **Auto-Renew Cron** tự gia hạn lúc 3:00 AM hàng ngày

### 💾 Backup & Restore thông minh (Menu 5 & 20)

- Backup Code + DB về **Local** hoặc **Google Drive** (rclone)
- **Auto Backup Cron**: Lịch hàng ngày (3:00 AM) hoặc hàng tuần
- **Space Saving Mode**: Tự động xóa file trên VPS sau khi upload thành công lên Google Drive
- **Smart Restore** với 3 lớp fallback tự động xử lý config, URL, permissions
- **Auto Search & Replace URL** khi migrate domain

### 🛡️ Bảo mật

- UFW Firewall + Fail2ban chống brute force SSH
- Thay đổi SSH port — **tự động xóa port cũ khỏi UFW**
- Rate Limiting Nginx (chống DDoS cơ bản)
- Basic WAF: Block SQLi, XSS, bad bots, file access
- Tắt các PHP function nguy hiểm

---

## 🚀 Hướng dẫn Tối ưu tốc độ Web (3 Bước)

### Bước 1: Tối ưu lõi Server bằng VPS Script

Mở SSH lên, gõ `vps` để vào Tool, sau đó:

1. **Menu 17 → Tính năng 1 (Auto-Optimize)**
   - Tính toán cấu hình RAM, tự động nâng cấp PHP-FPM, OPcache 256MB, tinh chỉnh MySQL/MariaDB
   - Web có thể **tải nhanh hơn ~50%**, giảm TTFB đáng kể

2. **Menu 10 → Tính năng 7 (Tối ưu Object Cache)**
   - Kích hoạt sức mạnh cho Database trên RAM

3. **(Nếu dùng WP Rocket)**: **Menu 10 → Tính năng 5 (Setup Nginx for WP Rocket)**
   - Ép Nginx nhận diện cache Rocket, bỏ qua tầng PHP

### Bước 2: Cài đặt Plugin trên WordPress

1. **Caching Plugin** (WP Rocket hoặc W3 Total Cache) — bật Page Caching, Minify CSS/JS
2. **Object Cache Plugin** — cài "Redis Object Cache" (Till Krüss), Enable Object Cache
3. **Image Optimization** — Imagify hoặc ShortPixel, auto convert sang `.webp`

### Bước 3: Dọn dẹp & Test

- **Menu 10 → Tùy chọn 1** để xóa toàn bộ cache
- Kiểm tra qua `PageSpeed Insights` hoặc `GTmetrix`

> ⚠️ **Lưu ý**: Luôn backup trước qua Menu của Script. Nếu dùng **Cloudflare**, nhớ *Purge Cache* sau khi tối ưu.

---

## 📋 Yêu cầu Hệ thống

| Yêu cầu | Tối thiểu |
|---------|-----------|
| OS | Ubuntu 20.04 / 22.04 / 24.04 — Debian 11/12 — AlmaLinux 8/9 |
| Quyền | Root |
| RAM | 1GB (khuyên dùng 2GB+ cho WordPress) |
| Disk | 5GB trống |

---

## 🗂️ Cấu trúc Project

```
vps-manager/
├── install.sh              # Entry point & self-updater (menu chính)
├── install-nginx.sh        # 🌐 Lệnh cài nhanh LEMP Nginx Stack
├── install-ols.sh          # ⚡ Lệnh cài nhanh OpenLiteSpeed Stack
├── VERSION                 # Phiên bản hiện tại
├── core/
│   ├── menu.sh             # Main menu (24 options)
│   ├── utils.sh            # Colors, logger, helpers
│   ├── mysql_helpers.sh    # MySQL connection handling
│   ├── nginx_helpers.sh    # Nginx config helpers
│   ├── dashboard.sh        # Real-time server dashboard
│   └── system_helpers.sh  # PHP socket, disk, OLS/LSPHP repo setup
└── modules/
    ├── nginx.sh             # 🌐 Nginx install stack & management menu
    ├── lemp.sh              # LEMP component installers (Nginx/MariaDB/PHP)
    ├── ols.sh               # ⚡ OpenLiteSpeed stack & LSCache manager
    ├── site.sh              # Domain & website management
    ├── wordpress_tool.sh    # WordPress advanced tools
    ├── wordpress_performance.sh  # Performance optimization (WpTangToc)
    ├── backup.sh            # Backup + Auto Backup Cron
    ├── ssl.sh               # SSL management
    ├── security.sh          # Firewall, SSH, WAF
    ├── database.sh          # Database management
    ├── phpmyadmin.sh        # phpMyAdmin install & manage
    ├── cache.sh             # Redis/Valkey/FastCGI Cache
    ├── php.sh               # PHP version management
    ├── switch.sh            # Web server switcher (Nginx <=> OLS)
    ├── monit.sh             # Monit watchdog
    ├── zram.sh              # ZRAM swap management
    ├── cron.sh              # Cronjob management
    ├── update.sh            # Self-updater
    └── ...
```

---

<a name="introduction-english"></a>

# 🇬🇧 Introduction (English)

A comprehensive **24-module** Bash script for managing Ubuntu/Debian/AlmaLinux VPS servers through an interactive menu. No need to memorize complex commands.

## Two Independent Install Stacks

### 🌐 Nginx LEMP Stack
```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
```

### ⚡ OpenLiteSpeed Stack
```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)
```

## Key Features

- **Dual web server support**: Nginx LEMP stack OR OpenLiteSpeed stack — completely independent, no overlap
- **Domain Management** — Add, Remove, Rename, Clone, Aliases, Redirects, Toggle FastCGI Cache (Dev Mode)
- **WordPress Manager Suite** via WP-CLI — Core/Plugin/User/Security/SEO
- **SSL Management** — Let's Encrypt, Cloudflare Origin, ZeroSSL + Auto-Renew Cron
- **Smart Backup & Restore** — Local/Google Drive, Auto Backup Cron (daily/weekly), 3-tier credential fallback
- **phpMyAdmin** — Automated install, HTTP Auth, hidden URL support
- **Security** — UFW, Fail2ban, SSH port change (auto-removes old UFW rule), WAF, Rate Limiting
- **Performance** — Valkey/Redis, LSCache, FastCGI Cache, ZRAM Swap, OPcache tuning
- **OpenLiteSpeed** — OLS install, LSPHP multi-version, LSCache in-RAM, QUIC HTTP/3, WebAdmin
- **Web Server Switcher** — Migrate all sites Nginx ↔ OLS with zero data loss (Menu 24)
- **Health Check** — Comprehensive RAM/Disk/Services/Config/Log diagnostics
- **Self-Update** — `git pull` (fast) with clone fallback

## Usage

```bash
vps        # Open management menu
```

## Requirements

| Requirement | Minimum |
|-------------|---------|
| OS | Ubuntu 20.04/22.04/24.04 or Debian 11/12 or AlmaLinux 8/9 |
| User | Root |
| RAM | 1GB (2GB+ recommended) |
| Disk | 5GB free |

---

> **Lưu ý / Note**: Script luôn chạy dưới quyền `root`. Sử dụng có trách nhiệm trên môi trường production.
