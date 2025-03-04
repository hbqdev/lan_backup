#!/bin/bash
# Backup Script v4.4 (With auto rsync installation, improved logging, and bandwidth control)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="${SCRIPT_DIR}/configs/backup_config.yaml"
ENV_FILE="${SCRIPT_DIR}/configs/.env"
BACKUP_ROOT="${SCRIPT_DIR}/data"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Default bandwidth limit in KB/s (5 MB/s = 5120 KB/s)
# Set to 0 for unlimited
DEFAULT_BANDWIDTH_LIMIT=5120

# Default sleep time between hosts in seconds (0 = no sleep)
DEFAULT_SLEEP_BETWEEN_HOSTS=30

# SSH and rsync configuration
SSH_OPTS="-o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no"
RSYNC_SSH_CMD="sshpass -p \"\$password_var\" ssh $SSH_OPTS"
SCP_CMD="sshpass -p \"\$password_var\" scp $SSH_OPTS"
RSYNC_BASE_CMD="rsync --rsh=\"$RSYNC_SSH_CMD\""

# Parse command line arguments
BANDWIDTH_LIMIT=$DEFAULT_BANDWIDTH_LIMIT
SLEEP_BETWEEN_HOSTS=$DEFAULT_SLEEP_BETWEEN_HOSTS
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --bwlimit|--bandwidth-limit)
            BANDWIDTH_LIMIT="$2"
            shift
            ;;
        --bwlimit=*|--bandwidth-limit=*)
            BANDWIDTH_LIMIT="${1#*=}"
            ;;
        --unlimited)
            BANDWIDTH_LIMIT=0
            ;;
        --sleep)
            SLEEP_BETWEEN_HOSTS="$2"
            shift
            ;;
        --sleep=*)
            SLEEP_BETWEEN_HOSTS="${1#*=}"
            ;;
        --no-sleep)
            SLEEP_BETWEEN_HOSTS=0
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --bwlimit, --bandwidth-limit VALUE  Set bandwidth limit in KB/s (default: $DEFAULT_BANDWIDTH_LIMIT)"
            echo "  --unlimited                         Run without bandwidth limits"
            echo "  --sleep, --sleep=VALUE             Set sleep time between hosts in seconds (default: $DEFAULT_SLEEP_BETWEEN_HOSTS)"
            echo "  --no-sleep                         Don't sleep between hosts"
            echo "  --help                              Show this help message"
            echo
            echo "Backup Strategies (configurable per host in backup_config.yaml):"
            echo "  mirror       - Creates an exact copy, deleting files at destination that don't exist at source"
            echo "  incremental  - Keeps previous versions in snapshots directory (default)"
            echo "  safe         - Only adds or updates files, never deletes"
            echo "  gentle       - Network-friendly strategy that minimizes bandwidth usage"
            echo
            echo "Example configuration in backup_config.yaml:"
            echo "  hosts:"
            echo "    - name: server1"
            echo "      backup_strategy: incremental"
            echo "      max_snapshots: 7"
            echo "      bandwidth_limit: 3072  # 3 MB/s"
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Create directory structure if it doesn't exist
mkdir -p "${SCRIPT_DIR}/"{data,logs,configs}

# Generate a unique log filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
LOG_FILE="${LOGS_DIR}/backup_${TIMESTAMP}_${BACKUP_ID}.log"

# Create sample config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Creating sample configuration file..."
    cat << EOF > "$CONFIG_FILE"
# Backup configuration
hosts:
  - name: example-host
    ip: 192.168.1.100
    user: backupuser
    password_key: EXAMPLE_HOST_PASSWORD  # Reference to environment variable
    paths:
      - /path/to/backup
    # Optional: Set bandwidth limit in KB/s for this host (overrides global setting)
    # bandwidth_limit: 2048
    
    # Optional: Backup strategy (mirror, incremental, safe, gentle)
    # - mirror: Creates an exact copy, deleting files at destination that don't exist at source
    # - incremental: Keeps previous versions in snapshots directory (default)
    # - safe: Only adds or updates files, never deletes
    # - gentle: Network-friendly strategy that minimizes bandwidth usage
    # backup_strategy: incremental
    
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
    exit 0
fi

# Create .env file if it doesn't exist
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
    exit 0
fi

# Set proper permissions
chmod 700 "${SCRIPT_DIR}/configs"
chmod 600 "$ENV_FILE"

# Source the environment file to load passwords
source "$ENV_FILE"

# Create logs directory if it doesn't exist
mkdir -p "${LOGS_DIR}"

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
        ssh_command "sudo yum install -y rsync" || {
            echo "  ❌ Failed to install rsync with yum. Trying without sudo..."
            ssh_command "yum install -y rsync"
        }
    elif ssh_command "command -v dnf" &>/dev/null; then
        echo "  📦 Fedora/RHEL detected. Installing rsync using dnf..."
        ssh_command "sudo dnf install -y rsync" || {
            echo "  ❌ Failed to install rsync with dnf. Trying without sudo..."
            ssh_command "dnf install -y rsync"
        }
    elif ssh_command "command -v zypper" &>/dev/null; then
        echo "  📦 openSUSE detected. Installing rsync using zypper..."
        ssh_command "sudo zypper install -y rsync" || {
            echo "  ❌ Failed to install rsync with zypper. Trying without sudo..."
            ssh_command "zypper install -y rsync"
        }
    elif ssh_command "command -v pacman" &>/dev/null; then
        echo "  📦 Arch Linux detected. Installing rsync using pacman..."
        ssh_command "sudo pacman -S --noconfirm rsync" || {
            echo "  ❌ Failed to install rsync with pacman. Trying without sudo..."
            ssh_command "pacman -S --noconfirm rsync"
        }
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

# Function to install yq and its dependencies
install_yq() {
    echo "🔧 Attempting to install yq..."
    
    # Check for package managers and install yq
    if command -v apt-get &>/dev/null; then
        echo "📦 Debian/Ubuntu detected. Installing yq and dependencies..."
        # First try to install jq (dependency for Python yq)
        sudo apt-get update && sudo apt-get install -y jq || {
            echo "❌ Failed to install jq with sudo. Trying without sudo..."
            apt-get update && apt-get install -y jq
        }
        
        # Then try to install yq
        sudo apt-get install -y yq || {
            echo "❌ Failed to install yq with apt-get. Trying alternative method..."
            # Try to install Go version
            if command -v wget &>/dev/null; then
                echo "📦 Installing yq using wget and direct binary..."
                YQ_VERSION="v4.35.1"
                YQ_BINARY="yq_linux_amd64"
                wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
                sudo mv /tmp/yq /usr/local/bin/yq && \
                sudo chmod +x /usr/local/bin/yq || {
                    echo "❌ Failed to install Go yq with sudo. Trying without sudo..."
                    wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
                    mv /tmp/yq ~/yq && \
                    chmod +x ~/yq && \
                    export PATH=$PATH:~
                }
            fi
        }
    elif command -v yum &>/dev/null; then
        echo "📦 RHEL/CentOS/Fedora detected. Installing dependencies..."
        # Install jq first
        sudo yum install -y jq wget || {
            echo "❌ Failed to install jq with sudo. Trying without sudo..."
            yum install -y jq wget
        }
        
        # Then install yq (Go version)
        echo "📦 Installing yq using wget and direct binary..."
        YQ_VERSION="v4.35.1"
        YQ_BINARY="yq_linux_amd64"
        wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
        sudo mv /tmp/yq /usr/local/bin/yq && \
        sudo chmod +x /usr/local/bin/yq || {
            echo "❌ Failed to install Go yq with sudo. Trying without sudo..."
            wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
            mv /tmp/yq ~/yq && \
            chmod +x ~/yq && \
            export PATH=$PATH:~
        }
    elif command -v dnf &>/dev/null; then
        echo "📦 Fedora/RHEL detected. Installing dependencies..."
        # Install jq first
        sudo dnf install -y jq wget || {
            echo "❌ Failed to install jq with sudo. Trying without sudo..."
            dnf install -y jq wget
        }
        
        # Then install yq (Go version)
        echo "📦 Installing yq using wget and direct binary..."
        YQ_VERSION="v4.35.1"
        YQ_BINARY="yq_linux_amd64"
        wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
        sudo mv /tmp/yq /usr/local/bin/yq && \
        sudo chmod +x /usr/local/bin/yq || {
            echo "❌ Failed to install Go yq with sudo. Trying without sudo..."
            wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
            mv /tmp/yq ~/yq && \
            chmod +x ~/yq && \
            export PATH=$PATH:~
        }
    elif command -v pip &>/dev/null; then
        echo "📦 Python pip detected. Installing dependencies..."
        # Install jq first
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y jq || apt-get update && apt-get install -y jq
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq || yum install -y jq
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y jq || dnf install -y jq
        fi
        
        # Then install yq
        pip install yq || sudo pip install yq
    elif command -v pip3 &>/dev/null; then
        echo "📦 Python pip3 detected. Installing dependencies..."
        # Install jq first
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y jq || apt-get update && apt-get install -y jq
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq || yum install -y jq
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y jq || dnf install -y jq
        fi
        
        # Then install yq
        pip3 install yq || sudo pip3 install yq
    else
        echo "❌ Could not detect a suitable package manager. Trying direct binary installation..."
        # Try direct binary installation for yq
        if command -v wget &>/dev/null; then
            echo "📦 Installing yq using wget and direct binary..."
            YQ_VERSION="v4.35.1"
            YQ_BINARY="yq_linux_amd64"
            wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq && \
            chmod +x /tmp/yq && \
            mv /tmp/yq ~/yq && \
            export PATH=$PATH:~
            echo "⚠️ Added yq to ~/yq. You may need to add this to your PATH permanently."
        else
            echo "❌ Failed to install yq. Please install it manually:"
            echo "   For Go version: https://github.com/mikefarah/yq#install"
            echo "   For Python version: pip install yq (requires jq)"
            return 1
        fi
    fi
    
    # Check if yq was installed successfully
    if command -v yq &>/dev/null; then
        echo "✅ yq installed successfully."
        return 0
    elif [ -f ~/yq ] && [ -x ~/yq ]; then
        echo "✅ yq installed to ~/yq. Using this version."
        alias yq=~/yq
        return 0
    else
        echo "❌ Failed to install yq."
        return 1
    fi
}

# Process host function with proper variable scoping
process_host() {
    local i=$1
    local yq_cmd="$2"
    
    # Extract host details
    local hostname=$($yq_cmd ".hosts[$i].name" "$CONFIG_FILE")
    local ip=$($yq_cmd ".hosts[$i].ip" "$CONFIG_FILE")
    local user=$($yq_cmd ".hosts[$i].user" "$CONFIG_FILE")
    
    # Get password key or direct password
    local password_key=$($yq_cmd ".hosts[$i].password_key" "$CONFIG_FILE")
    
    if [[ "$password_key" == "null" || -z "$password_key" ]]; then
        local password_raw=$($yq_cmd ".hosts[$i].password" "$CONFIG_FILE")
        if [[ "$password_raw" == *"_PASSWORD"* ]]; then
            password_key=$(echo "$password_raw" | tr -d '"')
            local password_var="${!password_key}"
        else
            local password_var=$(echo "$password_raw" | tr -d '"')
        fi
    else
        local password_var="${!password_key}"
    fi
    
    # Check if password is set
    if [ -z "$password_var" ]; then
        echo "❌ ERROR: Password for $hostname not found."
        echo "   Please check your configuration and environment file."
        return
    fi
    
    echo "Processing: $hostname ($ip)"
    echo "🔄 Starting backup for host: $hostname"
    
    # Process each path
    local path_count=$($yq_cmd ".hosts[$i].paths | length" "$CONFIG_FILE")
    for ((p=0; p<path_count; p++)); do
        local path=$($yq_cmd ".hosts[$i].paths[$p]" "$CONFIG_FILE")
        
        # Destination path
        local dest_path="${BACKUP_ROOT}/${hostname}${path}"
        if [[ -z "$dest_path" ]]; then
            echo "❌ Invalid destination path for $hostname:$path"
            continue
        fi
        
        echo "  Backing up: $path"
        echo "  📂 Path: $path"
        
        local use_ip=false
        local host_to_use="$hostname"

        # Connection check function
        check_connection() {
            local target=$1
            if sshpass -p "$password_var" ssh $SSH_OPTS "$user@$target" "ls -la $path" &>/dev/null; then
                return 0
            else
                return 1
            fi
        }

        # Try hostname first, then IP
        if check_connection "$hostname"; then
            echo "  ✅ Hostname connection successful."
            host_to_use="$hostname"
        elif check_connection "$ip"; then
            echo "  ✅ IP connection successful."
            host_to_use="$ip"
        else
            echo "⚠️ WARNING: Cannot access $path on $hostname ($ip). Will try to backup anyway..."
            host_to_use="$ip"
        fi
        
        # Create destination path
        mkdir -p "$dest_path"
        echo "  Destination path: $dest_path"
        
        # Check if rsync is installed
        check_rsync_installed() {
            sshpass -p "$password_var" ssh $SSH_OPTS "$user@$host_to_use" "which rsync" &>/dev/null
        }

        if ! check_rsync_installed; then
            echo "  ⚠️ WARNING: rsync not found on remote host."

            # Try to install rsync
            if install_rsync "$host_to_use" "$user" "$password_var"; then
                echo "  ✅ rsync installed successfully. Proceeding with rsync backup."
            else
                echo "  ❌ Could not install rsync. Skipping this path."
                continue # Skip to the next path if rsync install fails
            fi
        else
            echo "  ✅ rsync is already installed on remote host."
        fi
        
        # Get host-specific bandwidth limit
        local host_bandwidth_limit=$($yq_cmd ".hosts[$i].bandwidth_limit" "$CONFIG_FILE")
        if [[ "$host_bandwidth_limit" == "null" || -z "$host_bandwidth_limit" ]]; then
            host_bandwidth_limit=$BANDWIDTH_LIMIT
        fi
        
        # Select backup strategy
        echo "  Selecting appropriate backup strategy..."
        
        # Define backup strategies
        declare -A backup_strategies
        backup_strategies=(
            ["mirror"]="--archive --hard-links --acls --xattrs --delete --delete-excluded --progress --stats --timeout=120 --no-compress"
            ["incremental"]="--archive --hard-links --acls --xattrs --backup --backup-dir=\"$(realpath "$dest_path")/../.snapshots/$(date +%Y-%m-%d_%H-%M-%S)\" --progress --stats --timeout=120 --no-compress --block-size=128K"
            ["safe"]="--archive --hard-links --acls --xattrs --update --progress --stats --timeout=120 --no-compress --block-size=128K"
            # ["gentle"]="--archive --update --no-compress --timeout=120 --contimeout=60 --inplace --size-only --progress --stats --block-size=128K"  # Commented out - remove if never used
            # ["large-files"]="--archive --whole-file --block-size=128K --info=progress2 --timeout=120 --no-compress" # Commented out - remove if never used
            ["large-incremental"]="--archive --whole-file --block-size=128K --hard-links --acls --xattrs --backup --backup-dir=\"$(realpath "$dest_path")/../.snapshots/$(date +%Y-%m-%d_%H-%M-%S)\" --info=progress2 --timeout=180 --no-compress"
            # ["root-access"]="--archive --whole-file --block-size=128K --hard-links --acls --xattrs --super --numeric-ids --info=progress2 --timeout=180 --no-compress" #Commented out
        )
        
        # Default strategy
        local backup_strategy="large-incremental"
        
        # Get host-specific backup strategy
        local host_backup_strategy=$($yq_cmd ".hosts[$i].backup_strategy" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$host_backup_strategy" != "null" && -n "$host_backup_strategy" ]]; then
            if [[ -n "${backup_strategies[$host_backup_strategy]}" ]]; then
                backup_strategy="$host_backup_strategy"
            else
                echo "  ⚠️ Unknown backup strategy '$host_backup_strategy' in config, using default '$backup_strategy'"
            fi
        fi
        
        # Get rsync options for selected strategy
        local rsync_opts="${backup_strategies[$backup_strategy]}"
        
        # Add common options
        rsync_opts="$rsync_opts --human-readable --partial --info=progress2 --no-inc-recursive"
        
        # Add bandwidth limit if set
        if [ "$host_bandwidth_limit" -gt 0 ]; then
            echo "  Applying bandwidth limit: $host_bandwidth_limit KB/s"
            rsync_opts="$rsync_opts --bwlimit=$host_bandwidth_limit"
        fi
        
        # Create snapshot directory if using incremental backup
        if [[ "$backup_strategy" == "incremental" || "$backup_strategy" == "large-incremental" ]]; then
            local snapshot_dir="$(realpath "$dest_path")/../.snapshots"
            mkdir -p "$snapshot_dir"
            echo "  📸 Using incremental backup with snapshots in: $snapshot_dir"
            
            # Manage snapshots retention
            local max_snapshots=7
            local host_max_snapshots=$($yq_cmd ".hosts[$i].max_snapshots" "$CONFIG_FILE" 2>/dev/null)
            if [[ "$host_max_snapshots" != "null" && -n "$host_max_snapshots" ]]; then
                max_snapshots=$host_max_snapshots
            fi
            
            # Clean up old snapshots
            local snapshot_count=$(ls -1 "$snapshot_dir" 2>/dev/null | wc -l)
            if [ "$snapshot_count" -gt "$max_snapshots" ]; then
                echo "  Cleaning up old snapshots (keeping $max_snapshots most recent)..."
                ls -1t "$snapshot_dir" | tail -n +$((max_snapshots+1)) | xargs -I {} rm -rf "$snapshot_dir/{}"
            fi
        fi
        
        echo "  Using backup strategy: $backup_strategy"
        
        # Make sure destination directory exists
        mkdir -p "$dest_path"
        
        # Change to script directory
        cd "$SCRIPT_DIR"
        
        # Add exclusion patterns if specified
        local exclusion_opts=""
        local exclusion_count=$($yq_cmd ".hosts[$i].exclude | length" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$exclusion_count" != "null" && "$exclusion_count" -gt 0 ]]; then
            for ((e=0; e<exclusion_count; e++)); do
                local exclude_pattern=$($yq_cmd ".hosts[$i].exclude[$e]" "$CONFIG_FILE")
                exclusion_opts="$exclusion_opts --exclude=\"$exclude_pattern\""
            done
            echo "  Using exclusion patterns: $exclusion_opts"
        fi
        
        # Check if sudo is needed for root-owned files
        check_sudo_access() {
            sshpass -p "$password_var" ssh $SSH_OPTS "$user@$host_to_use" \
                "find \"$path\" -user root | grep -q ." &>/dev/null
        }

        # Check for root-owned files
        local use_sudo=false
        if check_sudo_access; then
            echo "  🔒 Root-owned files detected, attempting to use sudo..."
            if sshpass -p "$password_var" ssh $SSH_OPTS "$user@$host_to_use" "sudo -n true" &>/dev/null; then
                echo "  ✅ Sudo access available without password, using sudo for backup"
                use_sudo=true
            elif sshpass -p "$password_var" ssh $SSH_OPTS "$user@$host_to_use" "echo \"$password_var\" | sudo -S true" &>/dev/null; then
                echo "  ✅ Sudo access available with password, using sudo for backup"
                use_sudo=true
            else
                echo "  ⚠️ Root-owned files detected but sudo access not available"
                echo "  ⚠️ Some files may not be backed up due to permission issues"
            fi
        fi
        
        # Build rsync command
        if [ "$use_sudo" = true ]; then
            rsync_command="rsync $rsync_opts $exclusion_opts --rsync-path='sudo rsync' --rsh=\"$RSYNC_SSH_CMD\" \"$user@$host_to_use:$path/\" \"$(realpath "$dest_path")/\""
        else
            rsync_command="rsync $rsync_opts $exclusion_opts --rsh=\"sshpass -p \\\"$password_var\\\" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no\" \"$user@$host_to_use:$path/\" \"$(realpath "$dest_path")/\""
        fi
        
        # Execute rsync
        if eval "$rsync_command"; then
            echo "  ✅ Backup successful with $backup_strategy strategy."
            
            # Create success marker
            echo "$(date)" > "$(realpath "$dest_path")/.backup_success"
            
            # Show backup stats
            echo "  📊 Backup Statistics:"
            echo "    - 📁 Total Files: $(find "$(realpath "$dest_path")" -type f | wc -l)"
            echo "    - 💾 Total Size: $(du -sh "$(realpath "$dest_path")" | cut -f1)"
            
            # Show snapshot info if applicable
            if [[ "$backup_strategy" == "incremental" && -d "$snapshot_dir" ]]; then
                local latest_snapshot=$(ls -1t "$snapshot_dir" 2>/dev/null | head -n 1)
                if [[ -n "$latest_snapshot" ]]; then
                    echo "    - Latest Snapshot: $latest_snapshot"
                    echo "    - Snapshot Size: $(du -sh "$snapshot_dir/$latest_snapshot" 2>/dev/null | cut -f1)"
                    echo "    - Changed Files: $(find "$snapshot_dir/$latest_snapshot" -type f | wc -l)"
                fi
            fi
        else
            echo "  ❌ Backup failed with $backup_strategy strategy."
            echo "  ⚠️ Trying with safe strategy as fallback..."
            
            # Fallback to safe strategy
            if [ "$use_sudo" = true ]; then
                echo "  Using safe strategy with sudo as fallback..."
                local rsync_command="rsync --archive --update --super --numeric-ids --verbose --stats --rsync-path=\"$tmp_script\" --rsh=\"sshpass -p \\\"$password_var\\\" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -v\" \"$user@$host_to_use:$path/\" \"$(realpath "$dest_path")/\""
            else
                echo "  Using standard safe strategy as fallback..."
                local rsync_command="rsync --archive --update --verbose --stats --rsh=\"sshpass -p \\\"$password_var\\\" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -v\" \"$user@$host_to_use:$path/\" \"$(realpath "$dest_path")/\""
            fi
            
            if eval "$rsync_command"; then
                echo "  ✅ Backup successful with safe fallback strategy."
                echo "$(date)" > "$(realpath "$dest_path")/.backup_success"
            else
                echo "  ❌ Backup failed with safe fallback strategy."
                echo "$(date)" > "$(realpath "$dest_path")/.backup_failed"
            fi
        fi
        
        echo "  ✅ Backup attempt completed"
        ls -la "$dest_path"
        echo "  Note: Some files may have been skipped due to permissions or other issues"
    done
}

# Fix 3: Main processing logic with proper function calls
{
    echo "=== Backup Started @ $(date) ==="
    echo "🚀 Starting backup process..."
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ ERROR: Configuration file not found at $CONFIG_FILE"
        exit 1
    fi
    
    # Check which version of yq is installed
    if ! command -v yq &> /dev/null; then
        echo "❌ yq is not installed. Attempting to install it..."
        if install_yq; then
            echo "✅ yq installed successfully. Continuing with backup..."
        else
            echo "❌ ERROR: Failed to install yq. Please install it manually:"
            echo "   For Go version: https://github.com/mikefarah/yq#install"
            echo "   For Python version: pip install yq"
            exit 1
        fi
    else
        # Check if it's the Python version and if jq is installed
        local YQ_VERSION=$(yq --version 2>&1 | head -n 1)
        if [[ "$YQ_VERSION" != *"mikefarah"* ]] && ! command -v jq &> /dev/null; then
            echo "❌ Python yq detected but jq is not installed. Attempting to install jq..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y jq || apt-get update && apt-get install -y jq
            elif command -v yum &>/dev/null; then
                sudo yum install -y jq || yum install -y jq
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y jq || dnf install -y jq
            else
                echo "❌ Could not install jq. Please install it manually."
                echo "   The Python version of yq requires jq to be installed."
                exit 1
            fi
        fi
    fi
    
    # Check if sshpass is installed
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
            exit 1
        fi
    fi
    
    echo "Using YQ version: $YQ_VERSION"
    
    # Determine yq command format based on version
    if [[ "$YQ_VERSION" == *"mikefarah"* ]]; then
        hosts_count=$(yq '.hosts | length' "$CONFIG_FILE")
        for ((i=0; i<hosts_count; i++)); do
            process_host $i "yq"
        done
    else
        hosts_count=$(yq -r '.hosts | length' "$CONFIG_FILE")
        for ((i=0; i<hosts_count; i++)); do
            process_host $i "yq -r"
        done
    fi
    
    echo "=== Backup Completed @ $(date) ==="
    echo "🎉 Backup process completed!"
} 2>&1 | tee -a "$LOG_FILE"

# Create a symlink to the latest log for easy access
ln -sf "$LOG_FILE" "${LOGS_DIR}/latest_backup.log"

echo "Log file created at: $LOG_FILE"
echo "Bandwidth limit used: $([ "$BANDWIDTH_LIMIT" -eq 0 ] && echo "Unlimited" || echo "$BANDWIDTH_LIMIT KB/s")"
echo "Sleep between hosts: $([ "$SLEEP_BETWEEN_HOSTS" -eq 0 ] && echo "None" || echo "$SLEEP_BETWEEN_HOSTS seconds")"

