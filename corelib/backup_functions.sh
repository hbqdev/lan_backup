#!/bin/bash
# Backup Script Functions

# Source the variables
source "$(dirname "${BASH_SOURCE[0]}")/../config/backup_vars.sh"

# Process host function with proper variable scoping
process_host() {
    local i=$1
    local yq_cmd=${2:-"yq"}
    
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
        password_key=$(echo "$password_key" | tr -d '"')
        local password_var="${!password_key}"
    fi
    
    # Check if password is set
    if [ -z "$password_var" ]; then
        echo "❌ ERROR: Password for $hostname not found."
        echo "   Please check your configuration and environment file."
        return
    fi
    
    echo "Processing host: $hostname ($ip)"
    echo "🔄 Starting backup for host: $hostname"
    
    # Process each path
    local path_count=$($yq_cmd ".hosts[$i].paths | length" "$CONFIG_FILE")
    
    # Get host-level backup strategy
    local host_strategy=$($yq_cmd ".hosts[$i].backup_strategy" "$CONFIG_FILE")
    if [[ "$host_strategy" == "null" || -z "$host_strategy" ]]; then
        host_strategy="large-incremental"  # Default if no host strategy specified
    fi
    
    for ((p=0; p<path_count; p++)); do
        local path=$($yq_cmd ".hosts[$i].paths[$p].path" "$CONFIG_FILE")
        if [[ "$path" == "null" || -z "$path" ]]; then
            path=$($yq_cmd ".hosts[$i].paths[$p]" "$CONFIG_FILE")
        fi
        
        echo "  Processing path: $path (Strategy: \"$host_strategy\")"
        
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
        local host_to_use="$hostname"
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
        local dest_path="${BACKUP_ROOT}/${hostname}${path}"
        mkdir -p "$dest_path"
        echo "  Destination path: $dest_path"
        echo "  Backing up: $path"
        echo "  📂 Path: $path"
        
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
        fi
        
        # Get host-specific bandwidth limit
        local host_bandwidth_limit=$($yq_cmd ".hosts[$i].bandwidth_limit" "$CONFIG_FILE")
        if [[ "$host_bandwidth_limit" == "null" || -z "$host_bandwidth_limit" ]]; then
            host_bandwidth_limit=$BANDWIDTH_LIMIT
        fi
        
        # Select backup strategy
        echo "  Selecting appropriate backup strategy..."
        
        # Check if this is a special backup type
        if [[ " ${SPECIAL_BACKUP_TYPES[@]} " =~ " $host_strategy " ]]; then
            case $host_strategy in
                "postgres")
                    backup_postgres "$host_to_use" "$path" "$dest_path" "$password_var" "$user"
                    ;;
                *)
                    echo "  ❌ Unknown special backup type: $host_strategy"
                    return 1
                    ;;
            esac
            continue
        fi
        
        # Get rsync options for selected strategy
        local rsync_opts="${backup_strategies[$host_strategy]}"
        if [[ -z "$rsync_opts" ]]; then
            echo "  ❌ Unknown backup strategy: $host_strategy"
            echo "  ⚠️ Falling back to safe strategy..."
            rsync_opts="${backup_strategies[safe]}"
        fi
        
        # Add common options
        rsync_opts="$rsync_opts --human-readable --partial --info=progress2 --no-inc-recursive"
        
        # Add bandwidth limit if set
        if [ "$host_bandwidth_limit" -gt 0 ]; then
            echo "  Applying bandwidth limit: $host_bandwidth_limit KB/s"
            rsync_opts="$rsync_opts --bwlimit=$host_bandwidth_limit"
        fi
        
        # Create snapshot directory if using incremental backup
        if [[ "$host_strategy" == "incremental" || "$host_strategy" == "large-incremental" ]]; then
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
        
        echo "  Using backup strategy: $host_strategy"
        
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
            echo "  ✅ Backup successful with $host_strategy strategy."
            
            # Create success marker
            echo "$(date)" > "$(realpath "$dest_path")/.backup_success"
            
            # Show backup stats
            echo "  📊 Backup Statistics:"
            echo "    - 📁 Total Files: $(find "$(realpath "$dest_path")" -type f | wc -l)"
            echo "    - 💾 Total Size: $(du -sh "$(realpath "$dest_path")" | cut -f1)"
            
            # Show snapshot info if applicable
            if [[ "$host_strategy" == "incremental" && -d "$snapshot_dir" ]]; then
                local latest_snapshot=$(ls -1t "$snapshot_dir" 2>/dev/null | head -n 1)
                if [[ -n "$latest_snapshot" ]]; then
                    echo "    - Latest Snapshot: $latest_snapshot"
                    echo "    - Snapshot Size: $(du -sh "$snapshot_dir/$latest_snapshot" 2>/dev/null | cut -f1)"
                    echo "    - Changed Files: $(find "$snapshot_dir/$latest_snapshot" -type f | wc -l)"
                fi
            fi
        else
            echo "  ❌ Backup failed with $host_strategy strategy."
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
    done
}

# Function to backup PostgreSQL database in Docker
backup_postgres() {
    local host=$1
    local path=$2
    local dest_path=$3
    local password=$4
    local user=$5
    local postgres_config=$6

    echo "  🐘 Performing PostgreSQL backup for Docker container at $path"
    
    # Create postgres backup directory if it doesn't exist
    mkdir -p "$dest_path"
    
    # Get postgres configuration
    local db_name=$(echo "$postgres_config" | yq -r '.database')
    local container_name="immich_postgres"  # This is from your docker-compose
    
    # Generate timestamp for backup file
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="backup_${timestamp}.sql"
    
    # Create the docker pg_dump command
    local pg_dump_cmd="docker exec $container_name pg_dump -U \$DB_USERNAME -d \$DB_DATABASE_NAME -Fc -f /tmp/$backup_file && docker cp $container_name:/tmp/$backup_file $dest_path/ && docker exec $container_name rm /tmp/$backup_file"
    
    # Execute pg_dump through SSH with sudo
    if sshpass -p "$password" ssh $SSH_OPTS "$user@$host" "echo \"$password\" | sudo -S bash -c '$pg_dump_cmd'"; then
        echo "  ✅ PostgreSQL Docker backup completed successfully"
        echo "  📊 Backup Statistics:"
        echo "    - 📁 Backup File: $backup_file"
        echo "    - 💾 Backup Size: $(du -sh "$dest_path/$backup_file" 2>/dev/null | cut -f1)"
        
        # Keep only the latest 5 backups
        find "$dest_path" -name "backup_*.sql" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null
        
        # Create success marker
        echo "$(date)" > "$dest_path/.backup_success"
        
        # Also backup the Docker volume directory with sudo
        local volume_backup_cmd="tar czf $dest_path/postgres_data_${timestamp}.tar.gz -C $(dirname $path) $(basename $path)"
        if sshpass -p "$password" ssh $SSH_OPTS "$user@$host" "echo \"$password\" | sudo -S bash -c '$volume_backup_cmd'"; then
            echo "  ✅ PostgreSQL data directory backup completed successfully"
            echo "  💾 Data directory backup size: $(du -sh "$dest_path/postgres_data_${timestamp}.tar.gz" 2>/dev/null | cut -f1)"
            
            # Keep only the latest 5 volume backups
            find "$dest_path" -name "postgres_data_*.tar.gz" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null
        else
            echo "  ❌ PostgreSQL data directory backup failed"
        fi
    else
        echo "  ❌ PostgreSQL backup failed"
        echo "$(date)" > "$dest_path/.backup_failed"
        return 1
    fi
}

# Function to install rsync on remote host
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

# Function to check if rsync is installed on remote host
check_rsync_remote() {
    local host=$1
    local user=$2
    local password=$3
    local host_to_use=$4

    if ! sshpass -p "$password" ssh $SSH_OPTS "$user@$host_to_use" "command -v rsync >/dev/null 2>&1"; then
        echo "  ⚠️ WARNING: rsync not found on remote host."
        install_rsync "$host" "$user" "$password"
        return $?
    fi
    return 0
}

process_path() {
    local hostname=$1
    local host_to_use=$2
    local user=$3
    local password=$4
    local path=$5
    local backup_strategy=$6
    local bandwidth_limit=$7
    local exclude_patterns=$8

    echo "  Processing path: $path (Strategy: \"$backup_strategy\")"
    
    # Check remote path accessibility
    if ! sshpass -p "$password" ssh $SSH_OPTS "$user@$host_to_use" "test -e '$path'"; then
        echo "⚠️ WARNING: Cannot access $path on \"$hostname\" (\"$host_to_use\"). Will try to backup anyway..."
    fi

    # Create destination path
    local dest_path="$BACKUP_ROOT/$hostname$path"
    echo "  Destination path: $dest_path"
    mkdir -p "$dest_path"

    echo "  Backing up: $path"
    echo "  📂 Path: $path"

    # Check and install rsync if needed
    if ! check_rsync_remote "$hostname" "$user" "$password" "$host_to_use"; then
        return 1
    fi

    # Rest of the function remains the same...
} 