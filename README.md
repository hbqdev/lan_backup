# LAN Backup System

A simple, secure system for backing up data from multiple hosts on a local network.

## Features

- Backs up multiple hosts and paths
- Supports both hostname and IP-based connections
- Automatically detects and adapts to different YQ versions
- Falls back to SCP if rsync is not available on the remote host
- Detailed logging and error handling

## Setup

1. Run the setup script:
   \`\`\`
   ./setup_backup.sh
   \`\`\`

2. Edit the configuration file:
   \`\`\`
   nano configs/backup_config.yaml
   \`\`\`

3. Run the backup:
   \`\`\`
   ./lan_backup.sh
   \`\`\`

## Requirements

- \`sshpass\` for password-based SSH authentication
- \`yq\` for YAML parsing (supports both Go and Python versions)
- \`rsync\` for efficient file transfers (falls back to SCP if not available)

## Security Considerations

This script stores passwords in plain text. For better security:
- Consider using SSH keys instead
- Restrict access to the config directory
- Use a more secure password storage method

## License

MIT
EOF
