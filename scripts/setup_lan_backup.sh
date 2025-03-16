#!/bin/bash
# Setup and Installation Functions for LAN Backup

# Source the variables
source "$(dirname "${BASH_SOURCE[0]}")/../config/backup_vars.sh"

# Function to detect Linux distribution and install rsync
install_rsync() {
    local host=$1 user=$2 password=$3
    echo "  🔧 Attempting to install rsync on $host..."
    
    # Single ssh command with SSH_OPTS
    ssh_command() {
        sshpass -p "$password" ssh $SSH_OPTS "$user@$host" "$@"
    }

    # Package manager detection and installation
    if ssh_command "command -v apt-get" &>/dev/null; then
        echo "  📦 Debian/Ubuntu detected. Installing rsync using apt-get..."
        ssh_command "sudo apt-get update && sudo apt-get install -y rsync" || {
            echo "  ❌ Failed to install rsync with sudo. Trying without sudo..."
            ssh_command "apt-get update && apt-get install -y rsync"
        }
    elif ssh_command "command -v yum" &>/dev/null; then
        echo "  📦 RHEL/CentOS/Fedora detected. Installing rsync using yum..."
        ssh_command "sudo yum install -y rsync" || ssh_command "yum install -y rsync"
    elif ssh_command "command -v dnf" &>/dev/null; then
        echo "  📦 Fedora/RHEL detected. Installing rsync using dnf..."
        ssh_command "sudo dnf install -y rsync" || ssh_command "dnf install -y rsync"
    else
        echo "  ❌ Could not detect package manager. Unable to install rsync automatically."
        return 1
    fi
    
    # Check if rsync was installed successfully
    if ssh_command "which rsync" &>/dev/null; then
        echo "  ✅ rsync installed successfully on $host."
        return 0
    else
        echo "  ❌ Failed to install rsync on $host."
        return 1
    fi
}

# Function to check and install sshpass
install_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        echo "❌ sshpass is not installed. Attempting to install it..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y sshpass || apt-get update && apt-get install -y sshpass
        elif command -v yum &>/dev/null; then
            sudo yum install -y sshpass || yum install -y sshpass
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y sshpass || dnf install -y sshpass
        else
            echo "❌ ERROR: Failed to install sshpass. Please install it manually."
            return 1
        fi
    fi
    return 0
}

# Function to create sample configuration
create_sample_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "📝 Creating sample configuration file..."
        cat << EOF > "$CONFIG_FILE"
# Backup configuration
hosts:
  - name: example-host
    ip: 192.168.1.100
    user: backupuser
    password_key: EXAMPLE_HOST_PASSWORD  # Reference to environment variable
    backup_strategy: large-incremental   # Default strategy for all paths
    paths:
      - path: /path/to/backup
      - path: /path/to/database/postgres
        backup_strategy: postgres        # Override default strategy for this path
        postgres:
          database: mydb
          port: 5432
          host: localhost
    # Optional: Set bandwidth limit in KB/s for this host (overrides global setting)
    # bandwidth_limit: 2048
    
    # Optional: Maximum number of snapshots to keep (for incremental strategy)
    # max_snapshots: 7
    
    # Optional: Exclude patterns (files/directories to exclude from backup)
    # exclude:
    #   - "*.tmp"
    #   - "temp/"
    #   - "cache/"

  # Add more hosts as needed
EOF
        chmod 600 "$CONFIG_FILE"
        
        echo "✅ Sample configuration created at $CONFIG_FILE"
        echo "⚠️ Please edit the configuration files before running the backup:"
        echo "   1. Edit config: nano $CONFIG_FILE"
        echo "   2. Set passwords: nano $ENV_FILE (will be created automatically)"
    fi
}

# Function to create environment file
create_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "📝 Creating environment file for passwords..."
        cat << EOF > "$ENV_FILE"
# Environment file for secure password storage
# This file should be kept secure and not shared

# Format: HOST_PASSWORD=your_password_here
EXAMPLE_HOST_PASSWORD=your_password_here

# Add more passwords as needed
EOF
        chmod 600 "$ENV_FILE"
        echo "✅ Environment file created at $ENV_FILE"
        echo "⚠️ Please add your passwords to the environment file before running the backup."
        echo "   Use: nano $ENV_FILE"
    fi
}

# Function to create directory structure
create_directory_structure() {
    mkdir -p "${SCRIPT_DIR}/"{data,logs,configs,corelib}
    chmod 700 "${SCRIPT_DIR}/configs"
    chmod 600 "$ENV_FILE" 2>/dev/null
    
    # If backup_functions.sh doesn't exist in corelib, create it
    if [ ! -f "${SCRIPT_DIR}/corelib/backup_functions.sh" ]; then
        # Ensure corelib directory exists
        mkdir -p "${SCRIPT_DIR}/corelib"
        
        # Copy backup_functions.sh from the source directory if it exists
        if [ -f "$(dirname "${BASH_SOURCE[0]}")/../corelib/backup_functions.sh" ]; then
            cp "$(dirname "${BASH_SOURCE[0]}")/../corelib/backup_functions.sh" "${SCRIPT_DIR}/corelib/"
        else
            echo "❌ ERROR: backup_functions.sh not found. Please ensure it's properly installed."
            exit 1
        fi
    fi
}

# Main setup function
setup_lan_backup() {
    create_directory_structure
    create_sample_config
    create_env_file
    
    # Install required tools
    install_sshpass
    
    # Install yq using the dedicated script
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/install_yq.sh" ]; then
        echo "📦 Installing yq using dedicated script..."
        bash "$(dirname "${BASH_SOURCE[0]}")/install_yq.sh"
    else
        echo "❌ ERROR: install_yq.sh not found. Please ensure it's in the scripts directory."
        exit 1
    fi
    
    # Set proper permissions
    chmod 700 "${SCRIPT_DIR}/configs"
    chmod 600 "$ENV_FILE" 2>/dev/null
    
    echo "✅ Setup completed successfully!"
    echo "📝 Next steps:"
    echo "   1. Edit your backup configuration: nano $CONFIG_FILE"
    echo "   2. Set your passwords: nano $ENV_FILE"
    echo "   3. Run your first backup: ./lan_backup.sh"
}

# If this script is run directly, perform setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_lan_backup
fi 