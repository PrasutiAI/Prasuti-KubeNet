#!/bin/bash
set -e

# Wrapper script to run Kubernetes setup on remote server
# Usage: ./run_remote_setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/server_config.env"
SETUP_SCRIPT="$SCRIPT_DIR/setup_k8s_master.sh"

# 1. Load Configuration
if [ -f "$CONFIG_FILE" ]; then
    # Convert line endings just in case
    sed -i 's/\r$//' "$CONFIG_FILE"
    source "$CONFIG_FILE"
else
    echo "Error: server_config.env not found."
    exit 1
fi

# 2. Key Handling
# We use the key from the config, but we need to ensure it has correct permissions
# Since we are in WSL, we might need to copy it to a secure location if it's on /mnt/c
SSH_KEY_LOCAL="$SCRIPT_DIR/$SSH_KEY_PATH"
SSH_KEY_SECURE="$HOME/.ssh/k8s_setup_key.pem"

mkdir -p "$HOME/.ssh"
cp "$SSH_KEY_LOCAL" "$SSH_KEY_SECURE"
chmod 400 "$SSH_KEY_SECURE"

# 3. Prepare Setup Script
if [ -f "$SETUP_SCRIPT" ]; then
    sed -i 's/\r$//' "$SETUP_SCRIPT"
else
    echo "Error: setup_k8s_master.sh not found."
    exit 1
fi

# 4. Upload Script
echo "Uploading setup script to $SERVER_HOST..."
scp -i "$SSH_KEY_SECURE" -P "$SERVER_PORT" -o StrictHostKeyChecking=no "$SETUP_SCRIPT" "$SERVER_USER@$SERVER_HOST:~/setup_k8s_master.sh"

# 5. Execute Remote Script
echo "Executing setup script on remote server..."
echo "This may take a few minutes..."
ssh -i "$SSH_KEY_SECURE" -p "$SERVER_PORT" -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" "chmod +x ~/setup_k8s_master.sh && sudo ~/setup_k8s_master.sh"
