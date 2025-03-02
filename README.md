# LAN Backup System

A simple, secure system for backing up data from multiple hosts on a local network.

## Features

- Backs up multiple hosts and paths
- Supports both hostname and IP-based connections
- Automatically detects and adapts to different YQ versions
- Automatically installs rsync on remote hosts if missing
- Falls back to SCP if rsync installation fails
- Secure password management via environment file
- Force copy option to override errors and continue backups
- Detailed logging and error handling

## Setup

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

## Configuration

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
```

### Password Configuration (configs/.env)

## Requirements

- `sshpass` for password-based SSH authentication
- `yq` for YAML parsing (supports both Go and Python versions)
- `rsync` for efficient file transfers (automatically installed if missing)

## Security Improvements

This system now uses a more secure approach for password management:
- Passwords are stored in a separate `.env` file with restricted permissions
- The `.env` file can be excluded from version control
- Configuration and secrets are properly separated

## Troubleshooting

If you encounter rsync compression issues, try one of these solutions:
1. Disable compression by removing the `-z` flag from the rsync command
2. Use SSH compression instead by adding `-C` to the SSH options

## License

MIT
EOF

