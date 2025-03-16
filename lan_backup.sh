#!/bin/bash
# LAN Backup Script v4.4 (With auto rsync installation, improved logging, and bandwidth control)

# Source the variables
source "$(dirname "${BASH_SOURCE[0]}")/config/backup_vars.sh"

# Source environment file early
if [ -f "$ENV_FILE" ]; then
    echo "Debug - Sourcing environment file: $ENV_FILE"
    source "$ENV_FILE"
    # Verify environment variables
    echo "Debug - NIGHTFURYS_PASSWORD exists: $([[ -n "$NIGHTFURYS_PASSWORD" ]] && echo "yes" || echo "no")"
else
    echo "❌ Environment file not found: $ENV_FILE"
    exit 1
fi

# Function to cleanup PID file on exit
cleanup() {
    rm -f "$PID_FILE"
}

# Function to check if backup is already running
check_running() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "⚠️ Backup process is already running with PID: $pid"
            echo "To stop it, run: ./lan_backup.sh --stop"
            exit 1
        else
            # Remove stale PID file
            rm -f "$PID_FILE"
        fi
    fi
}

# Function to check and setup prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    # First, ensure yq is installed and is the correct version locally
    echo "📦 Checking yq installation..."
    if ! command -v yq &> /dev/null; then
        echo "⚠️ yq not found. Installing..."
        if ! bash "$(dirname "${BASH_SOURCE[0]}")/scripts/install_yq.sh"; then
            echo "❌ Failed to install yq. Please run ./scripts/install_yq.sh manually"
            exit 1
        fi
    else
        # Check version
        current_version=$(yq --version 2>&1)
        if [[ "$current_version" != *"$YQ_VERSION"* ]]; then
            echo "⚠️ Wrong yq version detected: $current_version"
            echo "🔄 Installing correct version: $YQ_VERSION"
            if ! bash "$(dirname "${BASH_SOURCE[0]}")/scripts/install_yq.sh"; then
                echo "❌ Failed to update yq. Please run ./scripts/install_yq.sh manually"
                exit 1
            fi
        fi
    fi
    echo "✅ yq check passed"
    
    # Check if sshpass is installed
    echo "📦 Checking sshpass installation..."
    if ! command -v sshpass &> /dev/null; then
        echo "⚠️ sshpass not found. Installing..."
        if ! install_sshpass; then
            echo "❌ Failed to install sshpass"
            exit 1
        fi
    fi
    echo "✅ sshpass check passed"
    
    # Create necessary directories
    echo "📁 Setting up directory structure..."
    source "$(dirname "${BASH_SOURCE[0]}")/scripts/setup_lan_backup.sh"
    create_directory_structure
    echo "✅ Directory structure check passed"
    
    # Check if config file exists
    echo "📝 Checking configuration..."
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "⚠️ Configuration file not found. Running setup..."
        setup_lan_backup
        exit 0
    fi
    echo "✅ Configuration check passed"
    
    # Source the environment file
    if [ -f "$ENV_FILE" ]; then
        echo "📦 Loading environment variables..."
        source "$ENV_FILE"
    else
        echo "❌ Environment file not found at $ENV_FILE"
        exit 1
    fi
    
    echo "✅ All prerequisites checked and ready"
}

# Parse command line arguments first
BANDWIDTH_LIMIT=$DEFAULT_BANDWIDTH_LIMIT
SLEEP_BETWEEN_HOSTS=$DEFAULT_SLEEP_BETWEEN_HOSTS
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stop)
            if [ -f "$PID_FILE" ]; then
                pid=$(cat "$PID_FILE")
                if ps -p "$pid" > /dev/null 2>&1; then
                    echo "🛑 Stopping backup process with PID: $pid"
                    kill "$pid"
                    rm -f "$PID_FILE"
                    exit 0
                else
                    echo "No running backup process found (stale PID file removed)"
                    rm -f "$PID_FILE"
                    exit 1
                fi
            else
                echo "No backup process found"
                exit 1
            fi
            ;;
        --bwlimit|--bandwidth-limit) BANDWIDTH_LIMIT="$2"; shift ;;
        --bwlimit=*|--bandwidth-limit=*) BANDWIDTH_LIMIT="${1#*=}" ;;
        --unlimited) BANDWIDTH_LIMIT=0 ;;
        --sleep) SLEEP_BETWEEN_HOSTS="$2"; shift ;;
        --sleep=*) SLEEP_BETWEEN_HOSTS="${1#*=}" ;;
        --no-sleep) SLEEP_BETWEEN_HOSTS=0 ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --stop                             Stop a running backup process"
            echo "  --bwlimit, --bandwidth-limit VALUE Set bandwidth limit in KB/s (default: $DEFAULT_BANDWIDTH_LIMIT)"
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
        *) echo "Unknown parameter: $1"; echo "Use --help for usage information"; exit 1 ;;
    esac
    shift
done

# Check if already running
check_running

# Write PID file
echo $$ > "$PID_FILE"

# Set up trap to clean up PID file on exit
trap cleanup EXIT

# Check all prerequisites
check_prerequisites

# Now source the functions after ensuring directories exist
source "$(dirname "${BASH_SOURCE[0]}")/corelib/backup_functions.sh"

# Generate a unique log filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/backup_${TIMESTAMP}_${BACKUP_ID}.log"

# Main processing logic
{
    echo "=== Backup Started @ $(date) ==="
    echo "🚀 Starting backup process..."
    
    # Create a symlink to the latest log for easy access
    ln -sf "$LOG_FILE" "${LOGS_DIR}/latest_backup.log"
    
    # Process all hosts
    hosts_count=$(yq '.hosts | length' "$CONFIG_FILE")
    for ((i=0; i<hosts_count; i++)); do
        process_host $i "yq"
        
        # Sleep between hosts if configured
        if [ "$i" -lt "$((hosts_count-1))" ] && [ "$SLEEP_BETWEEN_HOSTS" -gt 0 ]; then
            echo "💤 Sleeping for $SLEEP_BETWEEN_HOSTS seconds before next host..."
            sleep "$SLEEP_BETWEEN_HOSTS"
        fi
    done
    
    echo "=== Backup Completed @ $(date) ==="
    echo "🎉 Backup process completed!"
} 2>&1 | tee -a "$LOG_FILE"

echo "Log file created at: $LOG_FILE"
echo "Bandwidth limit used: $([ "$BANDWIDTH_LIMIT" -eq 0 ] && echo "Unlimited" || echo "$BANDWIDTH_LIMIT KB/s")"
echo "Sleep between hosts: $([ "$SLEEP_BETWEEN_HOSTS" -eq 0 ] && echo "None" || echo "$SLEEP_BETWEEN_HOSTS seconds")"

