#!/bin/bash
# Script to allow workloads on the master node (remove taint)
# Usage: ./allow_workloads_on_master.sh

SSH_KEY=~/prasuti-key.pem
HOST=45.194.3.82
USER=ubuntu

echo "Untainting master node to allow workloads..."
ssh -i $SSH_KEY -p 22 -o StrictHostKeyChecking=no $USER@$HOST "kubectl taint nodes --all node-role.kubernetes.io/control-plane-"

if [ $? -eq 0 ]; then
    echo "Success! The master node can now run pods."
else
    echo "Note: If it failed with 'not found', the node might already be untainted."
fi

echo ""
echo "Verifying node roles..."
ssh -i $SSH_KEY -p 22 -o StrictHostKeyChecking=no $USER@$HOST "kubectl get nodes"
