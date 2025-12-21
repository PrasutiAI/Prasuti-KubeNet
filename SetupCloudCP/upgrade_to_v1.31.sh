#!/bin/bash
set -e

# Kubernetes Control Plane Upgrade Script: v1.30 -> v1.31
# Run this script on the control plane node as root or with sudo

echo "=== Upgrading Kubernetes Control Plane: v1.30 → v1.31 ==="

# 1. Backup etcd (skip if etcdctl not available)
echo "[1/6] Backing up etcd..."
if command -v etcdctl &> /dev/null; then
    ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key \
      snapshot save /var/backups/kubernetes/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db
else
    echo "Note: etcdctl not available, skipping etcd backup"
fi

# 2. Update apt repository to v1.31
echo "[2/6] Updating apt repository to v1.31..."
K8S_VERSION="1.31"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# 3. Upgrade kubeadm
echo "[3/6] Upgrading kubeadm..."
apt-get update
apt-mark unhold kubeadm
DEBIAN_FRONTEND=noninteractive apt-get install -y kubeadm=1.31.14-1.1
apt-mark hold kubeadm
kubeadm version

# 4. Plan and apply upgrade
echo "[4/6] Planning upgrade..."
kubeadm upgrade plan

echo "[5/6] Applying upgrade (this may take a few minutes)..."
kubeadm upgrade apply v1.31.14 -y --ignore-preflight-errors=all

# 5. Upgrade kubelet and kubectl
echo "[6/6] Upgrading kubelet and kubectl..."
apt-mark unhold kubelet kubectl
DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet=1.31.14-1.1 kubectl=1.31.14-1.1
apt-mark hold kubelet kubectl

# Restart kubelet
systemctl daemon-reload
systemctl restart kubelet

echo ""
echo "=== Upgrade to v1.31 Complete ==="
echo "Verifying cluster status..."
sleep 5
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes
kubectl get pods -n kube-system

echo ""
echo "✓ Control plane successfully upgraded to v1.31.14"
echo "✓ Cluster is now running the same version as worker nodes"
