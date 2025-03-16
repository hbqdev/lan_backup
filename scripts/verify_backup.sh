#!/bin/bash
# Backup Verification Script
# This script verifies the integrity of backups by comparing source and destination files

# Source the variables
source "$(dirname "${BASH_SOURCE[0]}")/../config/backup_vars.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../configs/.env"

# Function to display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --host HOSTNAME       Specify a single host to verify (default: all hosts)"
    echo "  --path PATH           Specify a single path to verify (requires --host)"
    echo "  --checksum            Use MD5 checksums for verification (slower but more thorough)"
    echo "  --fix                 Fix any discrepancies found (copy from source to destination)"
    echo "  --help                Show this help message"
    echo
    echo "Example:"
    echo "  $0 --host nightfurys --path /home/nightfury/selfhosted/open-webui --checksum"
}

# Parse command line arguments
HOST=""
PATH_TO_VERIFY=""
USE_CHECKSUM=false
FIX_DISCREPANCIES=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --host) HOST="$2"; shift ;;
        --path) PATH_TO_VERIFY="$2"; shift ;;
        --checksum) USE_CHECKSUM=true ;;
        --fix) FIX_DISCREPANCIES=true ;;
        --help) show_usage; exit 0 ;;
        *) echo "Unknown parameter: $1"; show_usage; exit 1 ;;
    esac
    shift
done

# Function to verify a single path
verify_path() {
    local hostname=$1
    local ip=$2
    local user=$3
    local password=$4
    local path=$5
    local dest_path="${BACKUP_ROOT}/${hostname}${path}"
    
    echo "🔍 Verifying backup for $hostname:$path"
    
    # Check if destination path exists
    if [ ! -d "$dest_path" ]; then
        echo "❌ ERROR: Destination path $dest_path does not exist"
        return 1
    fi
    
    # Build rsync verification command
    local rsync_opts="-Pahn --stats"
    if [ "$USE_CHECKSUM" = true ]; then
        rsync_opts="$rsync_opts --checksum"
        echo "  Using checksum verification (this may take longer)"
    fi
    
    # Create temporary file for results
    local temp_file=$(mktemp)
    
    # Run verification
    echo "  Running verification..."
    
    # Connection check function
    check_connection() {
        local target=$1
        if sshpass -p "$password" ssh $SSH_OPTS "$user@$target" "ls -la $path" &>/dev/null; then
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
        echo "❌ ERROR: Cannot access $path on $hostname ($ip)"
        return 1
    fi
    
    # Run verification command
    local rsync_cmd="rsync $rsync_opts --rsh=\"sshpass -p \\\"$password\\\" ssh $SSH_OPTS\" \"$user@$host_to_use:$path/\" \"$dest_path/\" | sed '/\/$/d'"
    eval "$rsync_cmd" > "$temp_file"
    
    # Count discrepancies
    local discrepancy_count=$(grep -c "^>" "$temp_file")
    
    if [ "$discrepancy_count" -eq 0 ]; then
        echo "  ✅ Verification successful! No discrepancies found."
        local total_files=$(find "$dest_path" -type f | wc -l)
        local total_size=$(du -sh "$dest_path" | cut -f1)
        echo "  📊 Backup Statistics:"
        echo "    - 📁 Total Files: $total_files"
        echo "    - 💾 Total Size: $total_size"
    else
        echo "  ⚠️ Found $discrepancy_count discrepancies!"
        grep "^>" "$temp_file" | head -n 10 > "$temp_file.discrepancies"
        
        if [ "$discrepancy_count" -gt 10 ]; then
            echo "  Showing first 10 discrepancies (total: $discrepancy_count):"
        else
            echo "  Discrepancies:"
        fi
        
        cat "$temp_file.discrepancies"
        
        # Fix discrepancies if requested
        if [ "$FIX_DISCREPANCIES" = true ]; then
            echo "  🔧 Fixing discrepancies..."
            local fix_cmd="rsync -Pah --stats"
            if [ "$USE_CHECKSUM" = true ]; then
                fix_cmd="$fix_cmd --checksum"
            fi
            fix_cmd="$fix_cmd --rsh=\"sshpass -p \\\"$password\\\" ssh $SSH_OPTS\" \"$user@$host_to_use:$path/\" \"$dest_path/\""
            eval "$fix_cmd"
            echo "  ✅ Discrepancies fixed!"
        else
            echo "  ℹ️ Run with --fix to correct these discrepancies"
        fi
        
        rm -f "$temp_file.discrepancies"
    fi
    
    # Clean up
    rm -f "$temp_file"
    
    return 0
}

# Main function
main() {
    echo "=== Backup Verification Started @ $(date) ==="
    
    # Source the environment file to load passwords
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ ERROR: Environment file not found at $ENV_FILE"
        exit 1
    fi
    source "$ENV_FILE"
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ ERROR: Configuration file not found at $CONFIG_FILE"
        exit 1
    fi
    
    # Process hosts
    local hosts_count=$(yq '.hosts | length' "$CONFIG_FILE")
    local verified_count=0
    local failed_count=0
    
    for ((i=0; i<hosts_count; i++)); do
        local hostname=$(yq ".hosts[$i].name" "$CONFIG_FILE" | tr -d '"')
        
        # Skip if a specific host was requested and this isn't it
        if [ -n "$HOST" ] && [ "$hostname" != "$HOST" ]; then
            continue
        fi
        
        local ip=$(yq ".hosts[$i].ip" "$CONFIG_FILE" | tr -d '"')
        local user=$(yq ".hosts[$i].user" "$CONFIG_FILE" | tr -d '"')
        local password_key=$(yq ".hosts[$i].password_key" "$CONFIG_FILE" | tr -d '"')
        local password="${!password_key}"
        
        if [ -z "$password" ]; then
            echo "❌ ERROR: Password for $hostname not found"
            continue
        fi
        
        echo "🔄 Verifying backup for host: $hostname ($ip)"
        
        # Process paths
        local path_count=$(yq ".hosts[$i].paths | length" "$CONFIG_FILE")
        
        for ((p=0; p<path_count; p++)); do
            local path=$(yq ".hosts[$i].paths[$p].path" "$CONFIG_FILE")
            if [[ "$path" == "null" || -z "$path" ]]; then
                path=$(yq ".hosts[$i].paths[$p]" "$CONFIG_FILE")
            fi
            
            # Skip if a specific path was requested and this isn't it
            if [ -n "$PATH_TO_VERIFY" ] && [ "$path" != "$PATH_TO_VERIFY" ]; then
                continue
            fi
            
            if verify_path "$hostname" "$ip" "$user" "$password" "$path"; then
                verified_count=$((verified_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
            
            echo "-------------------------------------------"
        done
    done
    
    echo "=== Backup Verification Completed @ $(date) ==="
    echo "📊 Summary:"
    echo "  ✅ Successfully verified: $verified_count paths"
    echo "  ❌ Failed to verify: $failed_count paths"
}

# Run the main function
main 