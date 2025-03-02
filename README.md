# 🔄 LAN Backup System

A simple, secure system for backing up data from multiple hosts on a local network.

## ✨ Features

- 🖥️ Backs up multiple hosts and paths
- 🌐 Supports both hostname and IP-based connections
- 🔄 Multiple backup strategies (mirror, incremental, safe, gentle, large-files, large-incremental, root-access)
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
- 🔐 Support for backing up root-owned files with sudo
- 🧪 Automatic testing of sudo access before backup
- 🔄 Graceful degradation if sudo access is unavailable

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

The script supports seven different backup strategies that can be configured per host:

1. **Mirror** (`mirror`):
   - 🪞 Creates an exact copy of the source at the destination
   - 🗑️ Deletes files at the destination that don't exist at the source
   - ✅ Perfect for when you need an exact replica of the source

2. **Incremental** (`incremental`):
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

5. **Large Files** (`large-files`):
   - 📦 Optimized for transferring large files
   - 🚀 Uses whole-file transfer to avoid delta calculations
   - ✅ Best for media files, virtual machine images, and other large binary files

6. **Large Incremental** (`large-incremental`) - Default:
   - 📦 Combines large file optimization with incremental backup features
   - 📸 Preserves previous versions while optimizing for large file transfers
   - ✅ Ideal for backing up mixed content with both large and small files

7. **Root Access** (`root-access`):
   - 🔐 Automatically used when root-owned files are detected
   - 🛡️ Preserves ownership and permissions of system files
   - ✅ Perfect for backing up system directories or mixed-ownership content

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
    
    # Optional: Backup strategy (mirror, incremental, safe, gentle, large-files, large-incremental, root-access)
    # backup_strategy: large-incremental
    
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

## 🔐 Root-Owned Files

The script automatically handles root-owned files:

1. **🔍 Automatic Detection**:
   - The script checks for root-owned files in each backup path
   - If found, it attempts to use sudo for the backup

2. **🧪 Testing Before Backup**:
   - Tests sudo access before attempting the backup
   - Creates a temporary helper script on the remote server

3. **🛡️ Fallback Mechanisms**:
   - If sudo access fails, falls back to non-sudo backup
   - Ensures you get at least a partial backup of non-root files

4. **📝 Detailed Logging**:
   - Provides verbose output about sudo access attempts
   - Reports which files might be skipped due to permission issues

## 📋 Requirements

- `sshpass` for password-based SSH authentication
- `yq` for YAML parsing (supports both Go and Python versions)
- `rsync` for efficient file transfers (automatically installed if missing)
- Passwords are stored in a separate `.env` file with restricted permissions
- The `.env` file can be excluded from version control
- Configuration and secrets are properly separated

## ❓ Troubleshooting

If you encounter issues with the backup:

1. **🔄 Rsync Compression Issues**:
   - The script now disables compression by default with `--no-compress`
   - This improves performance and compatibility

2. **🔐 Sudo Access Problems**:
   - Check if your user has sudo access on the remote system
   - Verify that the password works with sudo commands
   - The script will attempt multiple sudo approaches automatically

3. **📊 Check Logs for Details**:
   - Review the detailed logs in the `logs` directory
   - The script provides verbose output about what it's doing

4. **🔄 Block Size Optimization**:
   - The script uses a 128K block size for optimal performance
   - This can be adjusted in the script if needed for specific environments

## 📄 License

MIT


