#!/bin/bash
# Script to download kubeconfig from remote server
# Usage: ./download_kubeconfig.sh

SSH_KEY=~/prasuti-key.pem
HOST=45.194.3.82
USER=ubuntu
LOCAL_KUBECONFIG="kubeconfig"

echo "Downloading kubeconfig from $HOST..."
scp -i $SSH_KEY -P 22 -o StrictHostKeyChecking=no $USER@$HOST:~/.kube/config ./$LOCAL_KUBECONFIG

if [ $? -eq 0 ]; then
    echo "Success! Saved as './$LOCAL_KUBECONFIG'"
    echo ""
    echo "To use it:"
    echo "  export KUBECONFIG=$(pwd)/$LOCAL_KUBECONFIG"
    echo "  kubectl get nodes"
    echo ""
    echo "Verifying server address in config..."
    grep "server:" $LOCAL_KUBECONFIG
else
    echo "Failed to download kubeconfig."
fi
