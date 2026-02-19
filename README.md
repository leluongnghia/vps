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

## 📋 Menu Chính (22 Tùy chọn)

| # | Tính năng | Mô tả |
|---|-----------|--------|
| 1 | 🏗️ **Cài đặt LEMP Stack** | Nginx + MariaDB + PHP (8.1/8.2/8.3) tự động |
| 2 | 🌐 **Quản lý Domain & Website** | Thêm/Xóa/Clone/Rename site, Parked domain, Redirect |
| 3 | 🔧 **Quản lý WordPress** | WP-CLI: Core/Plugin/User, Security, SEO, Database |
| 4 | 🛡️ **Bảo mật & Tường lửa** | UFW, Fail2ban, SSH port, WAF, DDoS protection |
| 5 | 💾 **Backup & Restore** | Local, Google Drive, restore thông minh |
| 6 | ⚙️ **Công cụ Hệ thống** | Optimize, Logs, System tools |
| 7 | 🐘 **Quản lý PHP** | Đổi version, cấu hình, extensions |
| 8 | ⏰ **Quản lý Cronjob** | Thêm/Xóa lịch chạy |
| 9 | 🔄 **Quản lý Services** | Nginx/MySQL/PHP-FPM restart/stop/status |
| 10 | 🗃️ **Quản lý Database** | Tạo/Xóa DB, import/export, credentials |
| 11 | ⚡ **Quản lý Cache** | Redis, Memcached, FastCGI Cache |
| 12 | 🧠 **Quản lý Swap** | RAM ảo, tối ưu swappiness |
| 13 | 💿 **Quản lý Ổ đĩa** | Dọn dẹp logs, disk usage |
| 14 | 🛠️ **AppAdmin & Công cụ** | Phpinfo, bổ trợ |
| 15 | 📐 **Quản lý Nginx** | Cấu hình, snippets |
| 16 | 🚀 **Tối ưu Hiệu năng** | Redis/BBR/Brotli/Swap/Limits |
| 17 | 🔄 **Cập nhật Script** | Self-update từ GitHub (git pull hoặc clone) |
| 18 | 🏥 **Health Check** | Chẩn đoán toàn diện RAM/Disk/Services/Logs |
| 19 | ⚡ **WordPress Performance** | Tối ưu chuyên sâu cho WordPress |
| 20 | 🗄️ **Quản lý phpMyAdmin** | Cài đặt, HTTP Auth, URL ẩn |
| 21 | 🔒 **Quản lý SSL** | Status, Install, Renew, Revoke, Auto-renew Cron |
| 22 | ⏰ **Auto Backup Cron** | Lịch backup tự động hàng ngày/tuần |

---

## ✨ Tính năng Nổi bật

### 🚀 Cài đặt & Quản lý Website
- **LEMP Stack tự động**: Nginx + MariaDB + PHP multi-version (8.1, 8.2, 8.3) một lệnh
- **Quản lý Domain toàn diện**: Thêm, Xóa, Rename, Clone, Parked Domain, Redirect
- **WordPress Manager**:
  - Cài đặt WordPress + Database an toàn tự động
  - WP-CLI tích hợp: Core/Plugin/Theme update, User management
  - Bảo mật: Tắt XML-RPC, File Edit, Giấu wp-config, Fix permissions
  - SEO Nginx rules (RankMath/Yoast)
  - Tạo Admin mới với password random

### 🔒 SSL Management (Menu 21)
- **Let's Encrypt** (Certbot) — miễn phí, tự động
- **Cloudflare Origin SSL** — hỗ trợ paste key từ dashboard
- **ZeroSSL** — qua acme.sh
- **Xem trạng thái SSL** tất cả domain + số ngày còn hạn
- **Auto-Renew Cron** tự gia hạn lúc 3:00 AM hàng ngày

### 💾 Backup & Restore thông minh (Menu 5 & 22)
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

### 🗄️ phpMyAdmin (Menu 20)
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

## 🚀 Thứ tự ưu tiên tăng tốc WordPress

Để đạt hiệu suất cao nhất, hãy thực hiện theo thứ tự ưu tiên sau:

### 🥇 Tier 1 — Quan trọng nhất (Server-level & Database)
| Option | Tác dụng |
|--------|----------|
| **1. Auto-Optimize Server** | Tối ưu PHP-FPM, OPcache, MySQL, Nginx FastCGI ở cấp server. Ảnh hưởng tích cực toàn bộ các site. |
| **9. Disable Bloat** | Tắt Heartbeat, XML-RPC, Embeds... giúp giảm request không cần thiết. |
| **8. Database Cleanup** | Dọn dẹp revision, spam, transient giúp query database nhanh hơn. |

### 🥈 Tier 2 — Caching (Sau khi server ổn định)
| Option | Tác dụng |
|--------|----------|
| **5. Nginx FastCGI Cache** | Cache PHP response, giúp bypass PHP hoàn toàn cho khách truy cập lại. |
| **Cache Plugin (Rocket/W3TC)** | Tạo Static HTML giúp giảm TTFB xuống dưới 50ms. |
| **6. Object Cache (Redis)** | Cache database queries vào RAM, giảm tải cho MySQL 60-80%. |

### 🥉 Tier 3 — Tối ưu bổ sung
| Option | Tác dụng |
|--------|----------|
| **7. HTTP/2 + Brotli/Gzip** | Cần SSL. Giảm dung lượng truyền tải 60-70%. |
| **10. Image Optimization** | Cần thiết nếu site có nhiều hình ảnh chưa được tối ưu. |

> **Quy trình khuyến nghị:** 
> B1 (Opt 1) → B2 (Opt 9) → B3 (Opt 8) → B4 (Cài Cache Plugin) → B5 (Opt 6) → B6 (Opt 7)

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
