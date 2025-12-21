#!/bin/bash
# Script to access the remote Kubernetes Dashboard securely
# Usage: ./access_dashboard.sh

SSH_KEY=~/prasuti-key.pem
HOST=45.194.3.82
USER=ubuntu

echo "=== Kubernetes Dashboard Access ==="

# 1. Get the Login Token
echo "Retrieving access token..."
TOKEN=$(ssh -i $SSH_KEY -p 22 -o StrictHostKeyChecking=no $USER@$HOST "kubectl -n kubernetes-dashboard create token admin-user --duration=24h")

echo ""
echo "--------------------------------------------------------"
echo "TOKEN (Copy this for login):"
echo "$TOKEN"
echo "--------------------------------------------------------"
echo ""

# 2. Start SSH Tunnel and Port Forward
echo "Starting secure connection to the dashboard..."
echo "You can access the dashboard at:"
echo "   https://localhost:8443"
echo ""
echo "NOTE: You will see a 'Privacy Error' or 'Not Secure' warning."
echo "      This is normal (self-signed certificate). Click 'Advanced' -> 'Proceed to localhost'"
echo ""
echo "Press Ctrl+C to stop."

# Start port-forward on remote (bind to localhost:8443) and tunnel local 8443 to it
ssh -i $SSH_KEY -p 22 -o StrictHostKeyChecking=no -L 8443:localhost:8443 $USER@$HOST \
    "kubectl -n kubernetes-dashboard port-forward service/kubernetes-dashboard 8443:443"
