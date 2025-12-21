#!/bin/bash
set -e

# Kubernetes Master Setup Script
# Usage: sudo ./setup_k8s_master.sh

PUBLIC_IP=${PUBLIC_IP:-"45.194.3.82"}
K8S_VERSION=${K8S_VERSION:-"1.31"}

if [ -z "$PUBLIC_IP" ]; then
    echo "Error: PUBLIC_IP is not set."
    exit 1
fi

echo "=== Kubernetes Master Setup Started for IP: $PUBLIC_IP ==="

# 1. Disable Swap
echo "[1] Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

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

# 5. Initialize Control Plane
echo "[5] Initializing Control Plane..."
if [ ! -f /etc/kubernetes/admin.conf ]; then
    kubeadm init \
      --pod-network-cidr=10.244.0.0/16 \
      --apiserver-cert-extra-sans=$PUBLIC_IP \
      --control-plane-endpoint=$PUBLIC_IP
      
    # Configure kubectl for root
    export KUBECONFIG=/etc/kubernetes/admin.conf
else
    echo "Cluster already initialized."
fi

# 6. Configure User Access
echo "[6] Configuring access for ubuntu user..."
mkdir -p /home/ubuntu/.kube
cp -f /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# 7. Install CNI (Flannel)
echo "[7] Installing Flannel CNI..."
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 8. Un-taint master if we want to run pods on it (Optional, but good for single node testing)
# kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# 9. Generate Join Command
echo "=== JOIN_COMMAND_START ==="
kubeadm token create --print-join-command
echo "=== JOIN_COMMAND_END ==="
