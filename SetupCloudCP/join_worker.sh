#!/bin/bash
set -e

# Parameterized Script to join this machine to the Kubernetes cluster
# Usage: sudo ./join_worker.sh "<JOIN_COMMAND>" [K8S_VERSION]

JOIN_COMMAND=$1
K8S_VERSION=${2:-"1.31"}

if [ -z "$JOIN_COMMAND" ]; then
    echo "Usage: sudo ./join_worker.sh '<JOIN_COMMAND>' [K8S_VERSION]"
    exit 1
fi

echo "=== Joining Worker Node to Cluster (K8s v$K8S_VERSION) ==="

# 1. Disable Swap
echo "[1] Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

# 2. Kernel Modules and Sysctl
echo "[2] Loading kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "[2] Setting sysctl params..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# 3. Install Containerd
echo "[3] Installing containerd..."
if ! command -v containerd &> /dev/null; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y containerd.io
    
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml >/dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    systemctl restart containerd
else
    echo "Containerd already installed."
fi

# 4. Install Kubeadm, Kubelet, Kubectl
echo "[4] Installing Kubernetes components..."
apt-get update && apt-get install -y conntrack socat
if ! command -v kubeadm &> /dev/null; then
    apt-get install -y apt-transport-https ca-certificates curl gpg
    if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    fi
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
else
    echo "Kubernetes components already installed."
fi

# 5. Join Cluster
echo "[5] Joining cluster..."
# Execute the join command provided as argument
eval "$JOIN_COMMAND"

echo "=== Worker Node Joined Successfully ==="
