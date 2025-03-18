#!/bin/bash
# Backup Script Variables and Configurations

# Base paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && cd .. && pwd )"
CONFIG_FILE="${SCRIPT_DIR}/configs/backup_config.yaml"
ENV_FILE="${SCRIPT_DIR}/configs/.env"
BACKUP_ROOT="${SCRIPT_DIR}/data"
LOGS_DIR="${SCRIPT_DIR}/logs"

# Add PID file location
PID_FILE="${SCRIPT_DIR}/lan_backup.pid"

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

# Backup strategies configuration
declare -A backup_strategies
backup_strategies=(
    ["mirror"]="--archive --hard-links --acls --xattrs --delete --delete-excluded --progress --stats --timeout=120 --no-compress"
    ["incremental"]="--archive --hard-links --acls --xattrs --backup --backup-dir=\"\$(realpath \"\$dest_path\")/../.snapshots/\$(date +%Y-%m-%d_%H-%M-%S)\" --progress --stats --timeout=120 --no-compress --block-size=128K"
    ["safe"]="--archive --hard-links --acls --xattrs --update --progress --stats --timeout=120 --no-compress --block-size=128K"
    ["large-incremental"]="--archive --whole-file --block-size=128K --hard-links --acls --xattrs --backup --backup-dir=\"\$(realpath \"\$dest_path\")/../.snapshots/\$(date +%Y-%m-%d_%H-%M-%S)\" --info=progress2 --timeout=180 --no-compress"
)


# Add YQ version specification
YQ_VERSION="v4.45.1"
YQ_BINARY="yq_linux_amd64" 