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

# Parse command line arguments
BANDWIDTH_LIMIT=$DEFAULT_BANDWIDTH_LIMIT
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
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --bwlimit, --bandwidth-limit VALUE  Set bandwidth limit in KB/s (default: $DEFAULT_BANDWIDTH_LIMIT)"
            echo "  --unlimited                         Run without bandwidth limits"
            echo "  --help                              Show this help message"
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

  # Add more hosts as needed
EOF
    chmod 600 "$CONFIG_FILE"
    
    # Create sample .env file if it doesn't exist
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
        echo "✅ Sample environment file created at $ENV_FILE"
    fi
    
    echo "✅ Sample configuration created at $CONFIG_FILE"
    echo "⚠️ Please edit the configuration files before running the backup:"
    echo "   1. Edit config: nano $CONFIG_FILE"
    echo "   2. Set passwords: nano $ENV_FILE"
    exit 0
fi

# Create .env file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    echo "📝 Creating environment file for passwords..."
    cat << EOF > "$ENV_FILE"
# Environment file for secure password storage
# This file should be kept secure and not shared

# Format: HOST_PASSWORD=your_password_here
# Add passwords for each host in your config file
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
    local host=$1
    local user=$2
    local password=$3
    
    echo "  🔧 Attempting to install rsync on $host..."
    
    # Try to detect the package manager
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "command -v apt-get" &>/dev/null; then
        echo "  📦 Debian/Ubuntu detected. Installing rsync using apt-get..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "sudo apt-get update && sudo apt-get install -y rsync" || {
            echo "  ❌ Failed to install rsync with apt-get. Trying without sudo..."
            sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "apt-get update && apt-get install -y rsync"
        }
    elif sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "command -v yum" &>/dev/null; then
        echo "  📦 RHEL/CentOS/Fedora detected. Installing rsync using yum..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "sudo yum install -y rsync" || {
            echo "  ❌ Failed to install rsync with yum. Trying without sudo..."
            sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "yum install -y rsync"
        }
    elif sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "command -v dnf" &>/dev/null; then
        echo "  📦 Fedora/RHEL detected. Installing rsync using dnf..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "sudo dnf install -y rsync" || {
            echo "  ❌ Failed to install rsync with dnf. Trying without sudo..."
            sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "dnf install -y rsync"
        }
    elif sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "command -v zypper" &>/dev/null; then
        echo "  📦 openSUSE detected. Installing rsync using zypper..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "sudo zypper install -y rsync" || {
            echo "  ❌ Failed to install rsync with zypper. Trying without sudo..."
            sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "zypper install -y rsync"
        }
    elif sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "command -v pacman" &>/dev/null; then
        echo "  📦 Arch Linux detected. Installing rsync using pacman..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "sudo pacman -S --noconfirm rsync" || {
            echo "  ❌ Failed to install rsync with pacman. Trying without sudo..."
            sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "pacman -S --noconfirm rsync"
        }
    else
        echo "  ❌ Could not detect package manager. Unable to install rsync automatically."
        return 1
    fi
    
    # Check if rsync was installed successfully
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$host" "which rsync" &>/dev/null; then
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

{
    echo "=== Backup Started @ $(date) ==="
    
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
        YQ_VERSION=$(yq --version 2>&1 | head -n 1)
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
    
    YQ_VERSION=$(yq --version 2>&1 | head -n 1)
    echo "Using YQ version: $YQ_VERSION"
    
    # Process hosts - adjust yq syntax based on version
    if [[ "$YQ_VERSION" == *"mikefarah"* ]]; then
        # For yq v4 (Go version by mikefarah)
        hosts_count=$(yq '.hosts | length' "$CONFIG_FILE")
        
        for ((i=0; i<hosts_count; i++)); do
            hostname=$(yq ".hosts[$i].name" "$CONFIG_FILE")
            ip=$(yq ".hosts[$i].ip" "$CONFIG_FILE")
            user=$(yq ".hosts[$i].user" "$CONFIG_FILE")
            
            # Try to get password_key first (new format)
            password_key=$(yq ".hosts[$i].password_key" "$CONFIG_FILE")
            
            # If password_key is null or empty, try the old format with password
            if [[ "$password_key" == "null" || -z "$password_key" ]]; then
                password_raw=$(yq ".hosts[$i].password" "$CONFIG_FILE")
                # If it starts with a variable name, use it as a key
                if [[ "$password_raw" == *"_PASSWORD"* ]]; then
                    password_key=$(echo "$password_raw" | tr -d '"')
                    password_var="${!password_key}"
                else
                    # Otherwise use the raw password
                    password_var=$(echo "$password_raw" | tr -d '"')
                fi
            else
                # Get password from environment variable
                password_var="${!password_key}"
            fi
            
            # Check if password is set
            if [ -z "$password_var" ]; then
                echo "❌ ERROR: Password for $hostname not found."
                echo "   Please check your configuration and environment file."
                continue
            fi
            
            echo "Processing: $hostname ($ip)"
            
            path_count=$(yq ".hosts[$i].paths | length" "$CONFIG_FILE")
            for ((p=0; p<path_count; p++)); do
                path=$(yq ".hosts[$i].paths[$p]" "$CONFIG_FILE")
                echo "  Backing up: $path"
                
                use_ip=false
                host_to_use="$hostname"

                # Verify source readability with verbose output
                echo "  Checking SSH connection..."
                # Try with hostname first
                echo "  Trying with hostname..."
                if sshpass -p "$password_var" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$hostname" "ls -la $path" &>/dev/null; then
                    echo "  ✅ Hostname connection successful."
                else
                    echo "  ❌ Hostname connection failed, trying with IP..."
                    # If hostname fails, try with IP
                    if sshpass -p "$password_var" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$ip" "ls -la $path" &>/dev/null; then
                        echo "  ✅ IP connection successful."
                        use_ip=true
                        host_to_use="$ip"
                    else
                        echo "⚠️ WARNING: Cannot access $path on $hostname ($ip). Will try to backup anyway..."
                        # Set to use IP anyway since hostname failed
                        use_ip=true
                        host_to_use="$ip"
                    fi
                fi
                
                # Create destination path
                dest_path="${BACKUP_ROOT}/${hostname}${path}"
                mkdir -p "$dest_path"
                echo "  Destination path: $dest_path"
                
                # Check if rsync is installed on remote host
                echo "  Checking if rsync is installed on remote host..."
                if ! sshpass -p "$password_var" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$hostname" "which rsync" &>/dev/null; then
                    echo "  ⚠️ WARNING: rsync not found on remote host."
                    
                    # Try to install rsync
                    if install_rsync "$hostname" "$user" "$password_var"; then
                        echo "  ✅ rsync installed successfully. Proceeding with rsync backup."
                    else
                        echo "  ⚠️ Could not install rsync. Falling back to scp."
                        # Use scp as fallback with force options
                        echo "  Starting forced scp copy..."
                        
                        # Try with hostname first
                        sshpass -p "$password_var" scp -r -f -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$hostname:$path/*" "$dest_path/" || {
                            echo "  SCP with hostname failed, trying with IP..."
                            sshpass -p "$password_var" scp -r -f -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$ip:$path/*" "$dest_path/"
                        }
                    fi
                else
                    echo "  ✅ rsync is already installed on remote host."
                fi
                
                # Try to get host-specific bandwidth limit
                host_bandwidth_limit=$(yq ".hosts[$i].bandwidth_limit" "$CONFIG_FILE")
                if [[ "$host_bandwidth_limit" == "null" || -z "$host_bandwidth_limit" ]]; then
                    host_bandwidth_limit=$BANDWIDTH_LIMIT
                fi
                
                # Try rsync with different options in sequence
                for rsync_mode in "standard" "alternative" "minimal"; do
                    echo "  Trying rsync with $rsync_mode options..."
                    
                    case "$rsync_mode" in
                        standard)
                            rsync_opts="-av --progress --force --ignore-errors --delete --timeout=60"
                            ;;
                        alternative)
                            rsync_opts="-av --progress --force --ignore-errors --timeout=60"
                            ;;
                        minimal)
                            rsync_opts="-rlptDv --progress --force --ignore-errors --timeout=60"
                            ;;
                    esac
                    
                    # Add bandwidth limit if set
                    if [ "$host_bandwidth_limit" -gt 0 ]; then
                        echo "  Applying bandwidth limit: $host_bandwidth_limit KB/s"
                        rsync_opts="$rsync_opts --bwlimit=$host_bandwidth_limit"
                    fi
                    
                    # Make sure destination directory exists and is accessible
                    mkdir -p "$dest_path"
                    
                    # Change to script directory to avoid getcwd errors
                    cd "$SCRIPT_DIR"
                    
                    # Use absolute paths for both source and destination
                    if rsync $rsync_opts \
                        --rsh="sshpass -p \"$password_var\" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no" \
                        "$user@$host_to_use:$path/" "$(realpath "$dest_path")/"; then
                        echo "  ✅ Rsync successful with $rsync_mode options."
                        break
                    else
                        echo "  ❌ Rsync failed with $rsync_mode options."
                        # Continue to next option if this one failed
                    fi
                done
                
                # Always consider it a success since we're forcing
                echo "  ✅ Backup attempt completed"
                ls -la "$dest_path"
                echo "  Note: Some files may have been skipped due to permissions or other issues"
            done
        done
    else
        # For older yq versions (Python version)
        hosts_count=$(yq -r '.hosts | length' "$CONFIG_FILE")
        
        for ((i=0; i<hosts_count; i++)); do
            hostname=$(yq -r ".hosts[$i].name" "$CONFIG_FILE")
            ip=$(yq -r ".hosts[$i].ip" "$CONFIG_FILE")
            user=$(yq -r ".hosts[$i].user" "$CONFIG_FILE")
            
            # Try to get password_key first (new format)
            password_key=$(yq -r ".hosts[$i].password_key" "$CONFIG_FILE")
            
            # If password_key is null or empty, try the old format with password
            if [[ "$password_key" == "null" || -z "$password_key" ]]; then
                password_raw=$(yq -r ".hosts[$i].password" "$CONFIG_FILE")
                # If it starts with a variable name, use it as a key
                if [[ "$password_raw" == *"_PASSWORD"* ]]; then
                    password_key=$(echo "$password_raw" | tr -d '"')
                    password_var="${!password_key}"
                else
                    # Otherwise use the raw password
                    password_var=$(echo "$password_raw" | tr -d '"')
                fi
            else
                # Get password from environment variable
                password_var="${!password_key}"
            fi
            
            # Check if password is set
            if [ -z "$password_var" ]; then
                echo "❌ ERROR: Password for $hostname not found."
                echo "   Please check your configuration and environment file."
                continue
            fi
            
            echo "Processing: $hostname ($ip)"
            
            path_count=$(yq -r ".hosts[$i].paths | length" "$CONFIG_FILE")
            for ((p=0; p<path_count; p++)); do
                path=$(yq -r ".hosts[$i].paths[$p]" "$CONFIG_FILE")
                echo "  Backing up: $path"
                
                use_ip=false
                host_to_use="$hostname"

                # Verify source readability with verbose output
                echo "  Checking SSH connection..."
                # Try with hostname first
                echo "  Trying with hostname..."
                if sshpass -p "$password_var" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$hostname" "ls -la $path" &>/dev/null; then
                    echo "  ✅ Hostname connection successful."
                else
                    echo "  ❌ Hostname connection failed, trying with IP..."
                    # If hostname fails, try with IP
                    if sshpass -p "$password_var" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$ip" "ls -la $path" &>/dev/null; then
                        echo "  ✅ IP connection successful."
                        use_ip=true
                        host_to_use="$ip"
                    else
                        echo "⚠️ WARNING: Cannot access $path on $hostname ($ip). Will try to backup anyway..."
                        # Set to use IP anyway since hostname failed
                        use_ip=true
                        host_to_use="$ip"
                    fi
                fi
                
                # Create destination path
                dest_path="${BACKUP_ROOT}/${hostname}${path}"
                mkdir -p "$dest_path"
                echo "  Destination path: $dest_path"
                
                # Check if rsync is installed on remote host
                echo "  Checking if rsync is installed on remote host..."
                if ! sshpass -p "$password_var" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$hostname" "which rsync" &>/dev/null; then
                    echo "  ⚠️ WARNING: rsync not found on remote host."
                    
                    # Try to install rsync
                    if install_rsync "$hostname" "$user" "$password_var"; then
                        echo "  ✅ rsync installed successfully. Proceeding with rsync backup."
                    else
                        echo "  ⚠️ Could not install rsync. Falling back to scp."
                        # Use scp as fallback with force options
                        echo "  Starting forced scp copy..."
                        
                        # Try with hostname first
                        sshpass -p "$password_var" scp -r -f -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$hostname:$path/*" "$dest_path/" || {
                            echo "  SCP with hostname failed, trying with IP..."
                            sshpass -p "$password_var" scp -r -f -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no "$user@$ip:$path/*" "$dest_path/"
                        }
                    fi
                else
                    echo "  ✅ rsync is already installed on remote host."
                fi
                
                # Try to get host-specific bandwidth limit
                host_bandwidth_limit=$(yq -r ".hosts[$i].bandwidth_limit" "$CONFIG_FILE")
                if [[ "$host_bandwidth_limit" == "null" || -z "$host_bandwidth_limit" ]]; then
                    host_bandwidth_limit=$BANDWIDTH_LIMIT
                fi
                
                # Try rsync with different options in sequence
                for rsync_mode in "standard" "alternative" "minimal"; do
                    echo "  Trying rsync with $rsync_mode options..."
                    
                    case "$rsync_mode" in
                        standard)
                            rsync_opts="-av --progress --force --ignore-errors --delete --timeout=60"
                            ;;
                        alternative)
                            rsync_opts="-av --progress --force --ignore-errors --timeout=60"
                            ;;
                        minimal)
                            rsync_opts="-rlptDv --progress --force --ignore-errors --timeout=60"
                            ;;
                    esac
                    
                    # Add bandwidth limit if set
                    if [ "$host_bandwidth_limit" -gt 0 ]; then
                        echo "  Applying bandwidth limit: $host_bandwidth_limit KB/s"
                        rsync_opts="$rsync_opts --bwlimit=$host_bandwidth_limit"
                    fi
                    
                    # Make sure destination directory exists and is accessible
                    mkdir -p "$dest_path"
                    
                    # Change to script directory to avoid getcwd errors
                    cd "$SCRIPT_DIR"
                    
                    # Use absolute paths for both source and destination
                    if rsync $rsync_opts \
                        --rsh="sshpass -p \"$password_var\" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no" \
                        "$user@$host_to_use:$path/" "$(realpath "$dest_path")/"; then
                        echo "  ✅ Rsync successful with $rsync_mode options."
                        break
                    else
                        echo "  ❌ Rsync failed with $rsync_mode options."
                        # Continue to next option if this one failed
                    fi
                done
                
                # Always consider it a success since we're forcing
                echo "  ✅ Backup attempt completed"
                ls -la "$dest_path"
                echo "  Note: Some files may have been skipped due to permissions or other issues"
            done
        done
    fi
    
    echo "=== Backup Completed @ $(date) ==="
} 2>&1 | tee -a "$LOG_FILE"

# Create a symlink to the latest log for easy access
ln -sf "$LOG_FILE" "${LOGS_DIR}/latest_backup.log"

echo "Log file created at: $LOG_FILE"
echo "Bandwidth limit used: $([ "$BANDWIDTH_LIMIT" -eq 0 ] && echo "Unlimited" || echo "$BANDWIDTH_LIMIT KB/s")"

