#!/bin/bash

# Source the variables for SSH configuration
source "$(dirname "${BASH_SOURCE[0]}")/../config/backup_vars.sh"

# YQ version to install
YQ_VERSION="v4.45.1"
YQ_BINARY="yq_linux_amd64"
YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

# Function to install yq locally
install_yq_local() {
    echo "🔧 Installing yq ${YQ_VERSION} locally..."
    
    # Remove any existing yq installations
    sudo rm -f /usr/local/bin/yq /usr/bin/yq ~/yq 2>/dev/null
    
    # Download and install new yq
    wget -q "$YQ_URL" -O /tmp/yq && \
    sudo mv /tmp/yq /usr/local/bin/yq && \
    sudo chmod +x /usr/local/bin/yq
    
    if command -v yq &>/dev/null; then
        echo "✅ yq installed successfully locally"
        return 0
    else
        echo "❌ Failed to install yq locally"
        return 1
    fi
}

# Check current yq version
current_version=$(yq --version 2>&1)
if [[ "$current_version" == *"$YQ_VERSION"* ]]; then
    echo "✅ Correct yq version already installed: $current_version"
else
    echo "⚠️ Wrong yq version detected: $current_version"
    echo "🔄 Installing correct version: $YQ_VERSION"
    install_yq_local
fi

echo "🎉 yq installation completed!" 