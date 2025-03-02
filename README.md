# 🔄 LAN Backup System

A simple, secure system for backing up data from multiple hosts on a local network.

## ✨ Features

- 🖥️ Backs up multiple hosts and paths
- 🌐 Supports both hostname and IP-based connections
- 🔄 Multiple backup strategies (mirror, incremental, safe, gentle)
- 📸 Incremental backups with configurable snapshot retention
- 🔍 Automatically detects and adapts to different YQ versions
- 📦 Automatically installs rsync on remote hosts if missing
- 🔄 Falls back to SCP if rsync installation fails
- 🔒 Secure password management via environment file
- 🚀 Bandwidth control with configurable limits
- 🌐 Network-friendly options to prevent connection saturation
- ⏱️ Configurable delays between host backups
- 🚫 File exclusion patterns support
- 📊 Detailed logging with statistics reporting
- 🛡️ Automatic fallback to safer strategies if preferred strategy fails

## 🚀 Setup

The backup system is now completely self-contained in a single script. To get started:

1. Copy the `lan_backup.sh` script to your machine
2. Make it executable:
   `chmod +x lan_backup.sh`
3. Run it once to generate the configuration files:
   `./lan_backup.sh`
4. Edit the configuration files:
   ```
   vi configs/backup_config.yaml  # Configure hosts and paths
   vi configs/.env                # Set your passwords
   ```
5. Run the backup: `./lan_backup.sh`

## 🔄 Backup Strategies

The script supports four different backup strategies that can be configured per host:

1. **Mirror** (`mirror`):
   - 🪞 Creates an exact copy of the source at the destination
   - 🗑️ Deletes files at the destination that don't exist at the source
   - ✅ Perfect for when you need an exact replica of the source

2. **Incremental** (`incremental`) - Default:
   - 📸 Preserves previous versions of files in a snapshots directory
   - 🔄 Automatically manages snapshots with configurable retention
   - ✅ Ideal for most backup scenarios where you want to recover previous versions

3. **Safe** (`safe`):
   - 🛡️ Only adds or updates files, never deletes anything
   - ✅ Good for cautious backups where data preservation is critical

4. **Gentle** (`gentle`):
   - 🌐 Network-friendly strategy that minimizes bandwidth usage
   - 🔄 Uses size-only comparison and in-place updates to reduce network traffic
   - ✅ Best for unstable networks or when backing up over slow connections

## ⚙️ Configuration

### Host Configuration (configs/backup_config.yaml)

```yaml
# Backup configuration
hosts:
  - name: example-host
    ip: 192.168.1.100
    user: backupuser
    password_key: EXAMPLE_HOST_PASSWORD  # Reference to environment variable
    paths:
      - /path/to/backup
      - /another/path
    # Optional: Set bandwidth limit in KB/s for this host (overrides global setting)
    # bandwidth_limit: 2048
    
    # Optional: Backup strategy (mirror, incremental, safe, gentle)
    # backup_strategy: incremental
    
    # Optional: Maximum number of snapshots to keep (for incremental strategy)
    # max_snapshots: 7
    
    # Optional: Exclude patterns (files/directories to exclude from backup)
    # exclude:
    #   - "*.tmp"
    #   - "temp/"
    #   - "cache/"
```

### Password Configuration (configs/.env)

```
# Environment file for secure password storage
EXAMPLE_HOST_PASSWORD=your_password_here
```

## 🛠️ Command Line Options

```
Usage: ./lan_backup.sh [options]
Options:
  --bwlimit, --bandwidth-limit VALUE  Set bandwidth limit in KB/s (default: 5120)
  --unlimited                         Run without bandwidth limits
  --sleep, --sleep=VALUE              Set sleep time between hosts in seconds (default: 30)
  --no-sleep                          Don't sleep between hosts
  --help                              Show this help message
```

## 🔧 Troubleshooting Network Issues

If the backup script is causing network issues:

1. **🚀 Reduce bandwidth limits**:
   - Use a lower global limit: `./lan_backup.sh --bwlimit=2048` (2 MB/s)
   - Set host-specific limits in the config file

2. **🌐 Use the gentle backup strategy**:
   - Set `backup_strategy: gentle` in your host configuration
   - This minimizes network impact while still ensuring files are backed up

3. **⏱️ Add delays between hosts**:
   - Use `--sleep=60` to wait 60 seconds between backing up different hosts
   - This prevents network saturation from multiple concurrent transfers

4. **🕒 Schedule backups during off-hours**:
   - Use cron to run backups when network usage is low

## 📋 Requirements

- `sshpass` for password-based SSH authentication
- `yq` for YAML parsing (supports both Go and Python versions)
- `rsync` for efficient file transfers (automatically installed if missing)
- Passwords are stored in a separate `.env` file with restricted permissions
- The `.env` file can be excluded from version control
- Configuration and secrets are properly separated

## ❓ Troubleshooting

If you encounter rsync compression issues, try one of these solutions:
1. Disable compression by removing the `-z` flag from the rsync command
2. Use SSH compression instead by adding `-C` to the SSH options

## 📄 License

MIT


