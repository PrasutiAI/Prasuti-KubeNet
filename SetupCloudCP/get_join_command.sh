#!/bin/bash
# Script to retrieve join command from the remote cluster
# Usage: ./get_join_command.sh

SSH_KEY=~/prasuti-key.pem
HOST=45.194.3.82
USER=ubuntu

# Get the join command
echo "Retrieving join command..."
JOIN_CMD=$(ssh -i $SSH_KEY -p 22 -o StrictHostKeyChecking=no $USER@$HOST "sudo kubeadm token create --print-join-command")

if [ $? -eq 0 ]; then
    echo "Join Command:"
    echo "$JOIN_CMD"
    
    # Save to file in Windows path for easy access
    # Assuming standard WSL mount
    echo "$JOIN_CMD" > /mnt/c/DATA/Work/CICD/Prasuti-KubeNet/SetupCloudCP/join_command.txt
    
    echo "--------------------------------"
    echo "Saved to join_command.txt"
else
    echo "Error retrieving join command."
    echo "$JOIN_CMD"
fi

# Check nodes
echo ""
echo "Cluster Nodes Status:"
ssh -i $SSH_KEY -p 22 -o StrictHostKeyChecking=no $USER@$HOST "kubectl get nodes"
