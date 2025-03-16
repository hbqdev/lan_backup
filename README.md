# 🔄 LAN Backup System

A robust system for backing up self-hosted services across multiple LAN hosts.

## ✨ Features

- 🔄 Multiple backup strategies (mirror, incremental, safe)
- 🐘 Specialized PostgreSQL backup support
- 🔒 Secure password management
- 🚀 Configurable bandwidth control
- 📊 Detailed logging and verification
- 🛡️ Automatic fallback mechanisms

## 🚀 Quick Start

1. Clone and setup:
   ```bash
   git clone <repository>
   cd lan_backup
   chmod +x lan_backup.sh
   ```

2. Create configuration:
   ```bash
   ./lan_backup.sh  # Generates initial config
   ```

3. Configure your hosts:
   ```bash
   vi configs/backup_config.yaml  # Host configuration
   vi configs/.env                # Password configuration
   ```

4. Run backup:
   ```bash
   ./lan_backup.sh [options]
   ```

## 📋 Command Options

```bash
./lan_backup.sh [options]

Options:
  --stop                    Stop running backup
  --bwlimit VALUE          Bandwidth limit (KB/s)
  --unlimited              No bandwidth limit
  --sleep VALUE           Delay between hosts (seconds)
  --help                   Show help
```

## ⚙️ Configuration Example

```yaml
hosts:
  - name: myhost
    ip: 192.168.1.100
    user: backupuser
    password_key: HOST_PASSWORD
    backup_strategy: large-incremental
    bandwidth_limit: 3072  # Optional: 3MB/s
    paths:
      - path: /home/user/data
      
      # PostgreSQL backup
      - path: /path/to/postgres
        backup_strategy: postgres
        postgres:
          database: mydb
    
    exclude:
      - "*.tmp"
      - "temp/"
```

## 🔍 Backup Verification

Verify backup integrity:

```bash
./scripts/verify_backup.sh [options]

Options:
  --host HOST     Verify specific host
  --path PATH     Verify specific path
  --checksum      Use MD5 checksums
  --fix           Fix discrepancies
```

## 🔄 Backup Strategies

- **large-incremental** (default): Optimized for mixed content
- **mirror**: Exact source replica
- **safe**: Never deletes destination files
- **postgres**: PostgreSQL database backup

## 📁 Directory Structure

```
lan_backup/
├── configs/ # Configuration files
│ ├── backup_config.yaml # Host configuration
│ └── .env # Environment variables & passwords
├── corelib/ # Core library files
│ └── backup_functions.sh
├── scripts/ # Utility scripts
│ ├── verify_backup.sh # Backup verification
│ ├── install_yq.sh # YQ installation
│ └── setup_lan_backup.sh
├── data/ # Backup storage location
├── logs/ # Backup logs
├── config/ # Legacy config (deprecated)
├── lan_backup.sh # Main backup script
└── .gitignore # Git ignore rules

```

## 🛟 Troubleshooting

- **Backup Process Running**: Use `--stop` to terminate
- **YQ Version Mismatch**: Run `scripts/install_yq.sh`
- **SSH Connection Issues**: Check host connectivity and passwords
- **Permission Errors**: Verify sudo access on remote hosts

## 📝 Notes

- Requires YQ v4.45.1 on backup host
- Remote hosts only need rsync (auto-installed if missing)
- Uses SSH for secure transfers
- Supports both hostname and IP-based connections