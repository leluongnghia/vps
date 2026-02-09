# VPS Management Script

A comprehensive Bash script to manage your VPS server (Ubuntu 20.04/22.04/24.04).

## Features

- **LEMP Stack Installation**: Nginx, MariaDB, PHP (Multiple Versions)
- **WordPress Management**: Install, Manage, Backup, Restore
- **Security**: Firewall (UFW), Fail2Ban, SSH Hardening
- **Performance**: Swap Management, Cache Tuning, Redis/Memcached object cache
- **Database**: Create databases, users, backup/restore
- **SSL**: Let's Encrypt (Certbot) automation
- **Cron Jobs**: Easy management interface
- **Log Management**: Analyze and rotate logs

## Installation

Run the following command as **root** to install and start the manager:

```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh)
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install.sh | bash
```

## Update

To update the script to the latest version, simply run the installation command again or use the built-in update option in the menu.

## Usage

After installation, you can launch the menu anytime by typing:

```bash
vps
```

## Requirements

- **OS**: Ubuntu 20.04, 22.04, 24.04 LTS (Recommended) or Debian 11/12
- **User**: Root access is required
- **RAM**: Minimum 1GB recommended for WordPress sites
