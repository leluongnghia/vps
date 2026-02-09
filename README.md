# VPS Management Script - Quản lý VPS Tự động

[Tiếng Việt](#giới-thiệu) | [English](#introduction)

---

# <a name="giới-thiệu"></a>🇻🇳 Giới thiệu (Tiếng Việt)

Một script Bash toàn diện, mạnh mẽ giúp bạn quản lý VPS (Ubuntu/Debian) dễ dàng. Tự động hóa cài đặt Web Server (LEMP), WordPress, Bảo mật và Tối ưu hiệu năng chỉ với vài lệnh đơn giản.

## Tính năng Nổi bật

### 🚀 Cài đặt & Quản lý
- **LEMP Stack Tự động**: Cài đặt Nginx, MariaDB, PHP (Hỗ trợ đa phiên bản: 8.1, 8.2, 8.3...) chỉ với 1 click.
- **WordPress**: Cài đặt Web WordPress tự động, thiết lập Database, Nginx Config chuẩn.
- **Quản lý SSL Đa năng**:
  - **Let's Encrypt**: Tự động, miễn phí (Certbot).
  - **Cloudflare Origin SSL**: Hỗ trợ cài đặt chứng chỉ gốc Cloudflare (cho site dùng Proxy đám mây vàng).
  - **ZeroSSL**: Hỗ trợ qua `acme.sh`.
- **Shortcut tiện lợi**: Tự động tạo shortcut `/www` trỏ về thư mục web để truy cập nhanh.

### 🛡️ Bảo mật & An toàn
- **Tường lửa (Firewall)**: Cài đặt UFW, Fail2ban chống brute-force SSH.
- **Bảo mật SSH**: Đổi Port, giới hạn đăng nhập.
- **Chống DDoS cơ bản**: Cấu hình Nginx Rate Limiting.
- **Fix Lỗi Tự động**: Tự động phát hiện và xử lý lỗi cấu hình Nginx/PHP.

### ⚡ Tối ưu Hiệu năng (Performance)
- **Cache**:
  - Hỗ trợ Redis, Memcached, FastCGI Cache.
  - Tối ưu Nginx cho **WP Rocket**, **W3 Total Cache**, **WP Super Cache**.
- **System Tuning**: Tạo Swap RAM ảo, Tối ưu MySQL InnoDB, PHP Opcache.

### 💾 Sao lưu & Khôi phục (Backup/Restore)
- **Backup Đa kênh**: Sao lưu Code & Database về Local hoặc **Google Drive** (Rclone).
- **Restore Thông minh**:
  - Khôi phục từ file Backup có sẵn trên Local/Cloud.
  - **Restore từ file Upload thủ công**: Chỉ cần upload file .zip/.sql vào thư mục web, script tự nhận diện và khôi phục.
  - **Tự động thay thế URL (Search & Replace)**: Khi di chuyển web (Migration), script tự đổi domain cũ -> mới trong Database.
  - **Tự động sửa lỗi Database** sau khi restore.

### 🔧 Công cụ Hệ thống
- **Chẩn đoán Hệ thống (Health Check)**: Kiểm tra toàn diện RAM, Disk, Services, Config lỗi, và Log.
- **Cập nhật tự động**: Update script từ GitHub mà không mất dữ liệu cũ.

## Cài đặt

Chạy lệnh sau dưới quyền **root**:

```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
```

## Sử dụng

Sau khi cài đặt, bạn có thể mở menu quản lý bất cứ lúc nào bằng lệnh:

```bash
vps
```

## Yêu cầu Hệ thống
- **OS**: Ubuntu 20.04, 22.04, 24.04 LTS hoặc Debian 11/12.
- **Quyền**: Root.
- **RAM**: Tối thiểu 1GB (Khuyên dùng 2GB+ cho WordPress).

---

# <a name="introduction"></a>🇬🇧 Introduction (English)

A comprehensive and powerful Bash script to automate VPS management (Ubuntu/Debian). Simplify LEMP Stack installation, WordPress management, Security hardening, and Performance tuning.

## Key Features

### 🚀 Installation & Management
- **Automated LEMP Stack**: Install Nginx, MariaDB, PHP (Multi-version: 8.1, 8.2, 8.3...) in one click.
- **WordPress Manager**: Auto-install WordPress, setup Database, and generate optimized Nginx Config.
- **Versatile SSL Support**:
  - **Let's Encrypt**: Automatic & Free (via Certbot).
  - **Cloudflare Origin SSL**: Support for Cloudflare Proxied sites (Origin CA).
  - **ZeroSSL**: Support via `acme.sh`.
- **Convenient Shortcut**: Auto-create `/www` symlink for quick access to web roots.

### 🛡️ Security
- **Firewall**: One-click UFW & Fail2ban setup.
- **SSH Hardening**: Change SSH Port, limit login attempts.
- **DDoS Mitigation**: Basic Nginx Rate Limiting configuration.
- **Auto-Fix**: Self-healing scripts for common Nginx/PHP misconfigurations.

### ⚡ Performance Optimization
- **Caching**:
  - Redis, Memcached, FastCGI Cache support.
  - Nginx Optimization for **WP Rocket**, **W3 Total Cache**, **WP Super Cache**.
- **System Tuning**: Automated Swap creation, MySQL InnoDB tuning, PHP Opcache optimization.

### 💾 Backup & Restore
- **Multi-channel Backup**: Backup Code & DB to Local storage or **Google Drive** (via Rclone).
- **Smart Restore**:
  - Restore from Local/Cloud backups.
  - **Manual Upload Restore**: Simply upload .zip/.sql to web folder, script auto-detects and restores.
  - **Auto Search & Replace URL**: Automatically replaces old domain links with new domain during migration/restore.
  - **Auto DB Repair**: Checks and repairs database tables after restore.

### 🔧 System Tools
- **System Diagnosis (Health Check)**: Comprehensive check of RAM, Disk, Services, Config errors, and Error Logs.
- **Auto Update**: Built-in self-update mechanism from GitHub.

## Installation

Run the following command as **root**:

```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
```

## Usage

After installation, launch the manager anytime using:

```bash
vps
```

## Requirements
- **OS**: Ubuntu 20.04, 22.04, 24.04 LTS or Debian 11/12.
- **User**: Root access.
- **RAM**: Minimum 1GB (2GB+ recommended for WordPress).
