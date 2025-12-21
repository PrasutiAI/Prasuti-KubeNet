#!/bin/bash
# Orchestration script to run the full upgrade sequence on the remote server
# Usage: ./run_upgrade.sh

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/server_config.env"

# Load configuration
source "$CONFIG_FILE"

# Build SSH command
SSH_KEY="$SCRIPT_DIR/$SSH_KEY_PATH"
chmod 600 "$SSH_KEY"
SSH_CMD="ssh -i $SSH_KEY -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"

echo "=== Kubernetes Control Plane Upgrade Orchestration ==="
echo "Target: $SERVER_USER@$SERVER_HOST"
echo ""

# Function to upload and run a script
upload_and_run() {
    local script_name=$1
    local script_path="$SCRIPT_DIR/$script_name"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Uploading and executing: $script_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Upload script
    scp -i "$SSH_KEY" -P "$SERVER_PORT" "$script_path" "$SERVER_USER@$SERVER_HOST:/tmp/"
    
    # Make executable and run
    $SSH_CMD "chmod +x /tmp/$script_name && sudo /tmp/$script_name"
    
    echo ""
    echo "✓ $script_name completed successfully"
    echo ""
    
    # Wait between upgrades
    if [ "$script_name" != "upgrade_to_v1.31.sh" ]; then
        echo "Waiting 10 seconds before next upgrade..."
        sleep 10
    fi
}

# Confirm with user
echo "This will upgrade the control plane through 3 versions:"
echo "  v1.28 → v1.29 → v1.30 → v1.31"
echo ""
read -p "Do you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Upgrade cancelled."
    exit 0
fi

echo ""
echo "Starting upgrade sequence..."
echo ""

# Execute upgrades in sequence
upload_and_run "upgrade_to_v1.29.sh"
upload_and_run "upgrade_to_v1.30.sh"
upload_and_run "upgrade_to_v1.31.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ All upgrades completed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Downloading updated kubeconfig..."
$SSH_CMD "sudo cat /etc/kubernetes/admin.conf" > "$SCRIPT_DIR/kubeconfig"
echo "✓ Kubeconfig updated"
echo ""
echo "Final cluster status:"
kubectl --kubeconfig="$SCRIPT_DIR/kubeconfig" get nodes
echo ""
kubectl --kubeconfig="$SCRIPT_DIR/kubeconfig" version --short
