# 🖥️ VPS Management Script — Quản lý VPS Tự động

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![OS: Ubuntu/Debian](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-orange.svg)](#)

[🇻🇳 Tiếng Việt](#giới-thiệu-tiếng-việt) | [🇬🇧 English](#introduction-english)

---

## ⚡ Cài đặt nhanh / Quick Install

```bash
# curl
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)

# hoặc wget
bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
```

Sau khi cài, gõ `vps` để mở menu bất kỳ lúc nào.

---

<a name="giới-thiệu-tiếng-việt"></a>

# 🇻🇳 Giới thiệu (Tiếng Việt)

Script Bash toàn diện giúp quản lý VPS **Ubuntu/Debian** qua menu tương tác, không cần nhớ lệnh phức tạp. Bao gồm **22 module** quản lý toàn bộ vòng đời server từ cài đặt đến bảo mật và backup.

---

## 📋 Menu Chính (20 Tùy chọn)

| # | Tính năng | Mô tả |
|---|-----------|--------|
| 1 | 🏗️ **Cài đặt LEMP Stack** | Nginx + MariaDB + PHP (8.1/8.2/8.3) tự động |
| 2 | 🌐 **Quản lý Domain & Website** | Thêm/Xóa/Clone/Rename site, Parked domain, Redirect |
| 3 | 🔧 **Quản lý WordPress** | WP-CLI: Core/Plugin/User, Security, SEO, Database |
| 4 | 🛡️ **Bảo mật & Tối ưu hóa** | UFW, Fail2ban, SSH port, WAF, DDoS protection |
| 5 | 💾 **Sao lưu & Khôi phục (Backup/Restore)** | Local, Google Drive, restore thông minh |
| 6 | 🐘 **Quản lý Phiên bản PHP** | Đổi version, cấu hình, extensions |
| 7 | ⏰ **Quản lý Cronjob (Lịch biểu)** | Thêm/Xóa lịch chạy |
| 8 | 🔄 **Quản lý Services** | Khởi động lại/Stop Nginx, MySQL, PHP-FPM... |
| 9 | 🗃️ **Quản lý Database** | Tạo/Xóa DB, import/export, credentials |
| 10 | ⚡ **Quản lý Cache** | Redis, Memcached, FastCGI Cache |
| 11 | 🧠 **Quản lý Swap** | RAM ảo, tối ưu swappiness |
| 12 | 💿 **Quản lý Ổ đĩa & Dọn dẹp Logs** | Dọn dẹp logs, kiểm tra disk usage |
| 13 | 🛠️ **AppAdmin & Công cụ bổ trợ** | Phpinfo, ứng dụng bổ trợ |
| 14 | 📐 **Quản lý Nginx (Cấu hình)** | Cấu hình Virtual Hosts, snippets |
| 15 | 🔄 **Cập nhật Script (Từ GitHub)** | Tự động nâng cấp script lên bản mới nhất |
| 16 | 🏥 **Chẩn đoán Hệ thống (Health Check)** | Health Check tổng thể RAM/Disk/Services/Logs |
| 17 | 🚀 **Tối ưu WordPress Performance** | Tinh chỉnh cấp cao cho toàn hệ thống & website |
| 18 | 🗄️ **Quản lý phpMyAdmin** | Cài đặt tự động, bảo mật bằng HTTP Auth, URL ẩn |
| 19 | 🔒 **Quản lý SSL (Let's Encrypt / Renew)**| Cài đặt SSL, tự động gia hạn, kiểm tra trạng thái |
| 20 | ⏰ **Backup Tự động (Auto Backup Cron)** | Lập lịch backup source, DB hàng ngày/tuần |

---

## ✨ Tính năng Nổi bật

### 🚀 Cài đặt & Quản lý Website

- **LEMP Stack tự động**: Nginx + MariaDB + PHP multi-version (8.1, 8.2, 8.3) một lệnh
- **Quản lý Domain toàn diện**: Thêm, Xóa, Rename, Clone, Parked Domain, Redirect, **Bật/Tắt FastCGI Cache (Dev Mode)**
- **WordPress Manager**:
  - Cài đặt WordPress + Database an toàn tự động
  - WP-CLI tích hợp: Core/Plugin/Theme update, User management
  - Bảo mật: Tắt XML-RPC, File Edit, Giấu wp-config, Fix permissions
  - SEO Nginx rules (RankMath/Yoast)
  - Tạo Admin mới với password random

### 🔒 SSL Management (Menu 19)

- **Let's Encrypt** (Certbot) — miễn phí, tự động
- **Cloudflare Origin SSL** — hỗ trợ paste key từ dashboard
- **ZeroSSL** — qua acme.sh
- **Xem trạng thái SSL** tất cả domain + số ngày còn hạn
- **Auto-Renew Cron** tự gia hạn lúc 3:00 AM hàng ngày

### 💾 Backup & Restore thông minh (Menu 5 & 20)

- Backup Code + DB về **Local** hoặc **Google Drive** (rclone)
- **Auto Backup Cron**: Lịch hàng ngày (3:00 AM) hoặc hàng tuần
- **Space Saving Mode**: Tự động xóa file trên VPS sau khi upload thành công lên Google Drive (tiết kiệm dung lượng)
- **Backup ALL to Drive**: Sao lưu toàn bộ website lên Cloud chỉ với 1 thao tác
- **Smart Remote Select**: Tự động liệt kê danh sách Remote rclone để chọn (không cần nhớ tên)
- **Smart Restore (Local & Cloud)** với 3 lớp fallback tự động xử lý config, URL, permissions:
  1. Đọc từ kho lưu trữ hệ thống (`~/.vps-manager/sites_data.conf`)
  2. Đọc từ `wp-config.php` (nếu còn tồn tại)
  3. **Tự động reset + tạo mới** DB password nếu không tìm thấy
- **Auto Search & Replace URL** khi migrate domain
- **Auto fix table prefix**, DB repair sau restore
- Config retention: giữ bao nhiêu bản (mặc định 7 ngày)

### 🗄️ phpMyAdmin (Menu 18)

- Cài đặt tự động phpMyAdmin 5.2.1
- **HTTP Basic Auth** bảo vệ lớp 1
- Đổi URL ẩn để bảo mật
- Nginx config đúng chuẩn (không dùng `alias` — tránh 404)
- Hiển thị thông tin login đầy đủ sau cài đặt

### 🛡️ Bảo mật

- UFW Firewall + Fail2ban chống brute force SSH
- Thay đổi SSH port — **tự động xóa port cũ khỏi UFW** (tránh bị lock out)
- Rate Limiting Nginx (chống DDoS cơ bản)
- Basic WAF: Block SQLi, XSS, bad bots, file access
- Tắt các PHP function nguy hiểm

---

## 🚀 Hướng dẫn Tối ưu tốc độ Web với Script (3 Bước Chuẩn)

Quy trình này kết hợp hoàn hảo giữa cài cắm Plugin của anh và sự can thiệp từ VPS:

### Bước 1: Tối ưu lõi Server bằng VPS Script (Rất quan trọng)
Mở SSH lên, gõ `vps` để vào Tool, sau đó làm theo các menu sau:

1. **Vào Menu 17 (WordPress Performance) -> Chọn tính năng 1 (Auto-Optimize)**
   - Script sẽ tính toán cấu hình RAM của VPS để tự động nâng cấp sức mạnh cho PHP-FPM, Mở rộng OPcache lên mức 256MB, và tinh chỉnh cấu hình MySQL/MariaDB.
   - Khi chạy xong bước này, web của bạn đã có thể **tải nhanh hơn khoảng 50%**, giảm độ trễ Time-to-First-Byte (TTFB).

2. **Vào Menu 10 (Quản lý Cache) -> Chọn tính năng 7 (Tối ưu Server cho Object Cache)**
   - Kích hoạt sức mạnh cho Database trên RAM.

3. **(Nếu dùng WP Rocket)**: **Vào Menu 10 -> Chọn tính năng 5 (Setup Nginx for WP Rocket)**
   - Ép Nginx nhận diện thư mục cache của Rocket để bỏ qua tầng trung gian PHP. Điểm mấu chốt để web chịu tải được lượng traffic lớn.

### Bước 2: Cài đặt Plugin trên WordPress
Đăng nhập vào trang quản trị wp-admin của web và cài 3 loại plugin sau:

1. **Caching Plugin (Nên dùng WP Rocket hoặc W3 Total Cache):**
   - Chỉ cần bật tính năng cơ bản: *Enable Page Caching, Minify CSS/JS*. Do đã setup Nginx ở Bước 1 nên tốc độ load bây giờ sẽ được boot lên tối đa.
2. **Object Cache Plugin (Bắt buộc phải có để giảm tải Database):**
   - Cài Plugin **"Redis Object Cache"** (Của Till Krüss phát hành - bản miễn phí).
   - Truy cập Cài đặt -> Redis -> Nhấn "Enable Object Cache" -> Chờ nó chuyển sang chữ *Connected* màu xanh là xong (Khoảng 90% câu lệnh Database sẽ bị triệt tiêu).
3. **Image Optimization:**
   - Ảnh là thứ làm web nặng nhất. Cài Plugin **Imagify** hoặc **ShortPixel**, thiết lập tự động Converter ảnh sang đuôi `.webp` và dồn nén chất lượng khoảng 80-85%.

### Bước 3: Dọn dẹp rác & Test tốc độ
Cuối cùng, mở lại Menu của VPS CLI Script:
- Vào **Menu 10 (Quản lý Cache) -> Chọn Tùy chọn 1 (Xóa Cache FastCGI, Redis, Memcached)** để khởi động lại bộ nhớ một cách sạch sẽ nhất.
- Kiểm tra tốc độ thực tế thông qua các công cụ như `PageSpeed Insights` (Của Google) hoặc `GTmetrix` để xem độ cải thiện của Time-To-First-Byte. 

> **Lưu ý:** Mọi quy trình trên đều cực kỳ an toàn, hãy luôn backup lại web qua Menu của Script trước khi làm để đề phòng. Nếu web có sử dụng **Cloudflare**, đừng quên nút *Purge Cache* trên bảng điều khiển Cloudflare.

---

## 📋 Yêu cầu Hệ thống

| Yêu cầu | Tối thiểu |
|---------|-----------|
| OS | Ubuntu 20.04 / 22.04 / 24.04 LTS — Debian 11/12 |
| Quyền | Root |
| RAM | 1GB (khuyên dùng 2GB+ cho WordPress) |
| Disk | 5GB trống |

---

## 🗂️ Cấu trúc Project

```
vps-manager/
├── install.sh              # Entry point & self-updater
├── core/
│   ├── menu.sh             # Main menu (22 options)
│   ├── utils.sh            # Colors, logger, helpers
│   ├── mysql_helpers.sh    # MySQL connection handling
│   ├── nginx_helpers.sh    # Nginx config helpers
│   └── system_helpers.sh  # PHP socket, disk, validate
└── modules/
    ├── lemp.sh             # LEMP stack install
    ├── site.sh             # Domain & website management
    ├── wordpress_tool.sh   # WordPress advanced tools
    ├── backup.sh           # Backup + Auto Backup Cron
    ├── ssl.sh              # SSL management
    ├── security.sh         # Firewall, SSH, WAF
    ├── database.sh         # Database management
    ├── phpmyadmin.sh       # phpMyAdmin install & manage
    ├── optimize.sh         # Performance optimization
    ├── cron.sh             # Cronjob management
    ├── cache.sh            # Redis/Memcached/FastCGI
    ├── php.sh              # PHP version management
    ├── update.sh           # Self-updater
    └── ...                 # Và các module khác
```

---

<a name="introduction-english"></a>

# 🇬🇧 Introduction (English)

A comprehensive **22-module** Bash script for managing Ubuntu/Debian VPS servers through an interactive menu. No need to memorize complex commands.

## Key Features

- **LEMP Stack** (Nginx + MariaDB + PHP 8.1/8.2/8.3) automated install
- **Domain Management** — Add, Remove, Rename, Clone, Aliases, Redirects, **Toggle FastCGI Cache (Dev Mode)**
- **WordPress Manager Suite** via WP-CLI — Core/Plugin/User/Security/SEO
- **SSL Management** — Let's Encrypt, Cloudflare Origin, ZeroSSL + Auto-Renew Cron
- **Smart Backup & Restore** — Local/Google Drive, Auto Backup Cron (daily/weekly), 3-tier credential fallback
- **phpMyAdmin** — Automated install, HTTP Auth, hidden URL support
- **Security** — UFW, Fail2ban, SSH port change (auto-removes old UFW rule), WAF, Rate Limiting
- **Performance** — Redis, Memcached, FastCGI Cache, Brotli, TCP BBR, Swap tuning
- **Health Check** — Comprehensive RAM/Disk/Services/Config/Log diagnostics
- **Self-Update** — `git pull` (fast) with clone fallback, `getcwd`-safe implementation

## Installation

```bash
# curl
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)

# or wget
bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
```

## Usage

```bash
vps        # Open management menu
```

## Requirements

| Requirement | Minimum |
|-------------|---------|
| OS | Ubuntu 20.04/22.04/24.04 or Debian 11/12 |
| User | Root |
| RAM | 1GB (2GB+ recommended) |
| Disk | 5GB free |

---

> **Lưu ý / Note**: Script luôn chạy dưới quyền `root`. Sử dụng có trách nhiệm trên môi trường production.
