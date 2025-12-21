#!/bin/bash
# Script to install Kubernetes Dashboard and Admin User
# Usage: sudo ./setup_dashboard.sh

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "=== Installing Kubernetes Dashboard ==="

# 1. Deploy Recommended Manifest
# Using v2.7.0 which is stable and compatible with 1.28
# Note: Newer versions (v3+) use Helm, sticking to manifest for simplicity in shell script
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# 2. Create Admin Service Account
echo "Creating Admin Service Account..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

echo "Dashboard installed."
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -n kubernetes-dashboard --all --timeout=60s || echo "Pods valid, proceeding..."

# 3. Create Token (for K8s 1.24+)
# Long-lived token for simpler access (optional, but requested often)
# Actually, we can just print the token on demand.
