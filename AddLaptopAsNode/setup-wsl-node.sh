#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Consolidating Setup: Adding Laptop Node to Kubernetes ===${NC}"

# Start fresh with a reset to ensure no conflict from previous runs
echo -e "\n${GREEN}[0/6] Ensuring Clean State...${NC}"
if [ -f /etc/kubernetes/kubelet.conf ]; then
    sudo kubeadm reset -f || true
fi
sudo rm -rf /etc/cni/net.d
sudo rm -rf /etc/kubernetes/
sudo mkdir -p /etc/kubernetes/manifests

# 1. Prerequisites
echo -e "\n${GREEN}[1/6] Enabling modules and settings...${NC}"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 2. Install Containerd
echo -e "\n${GREEN}[2/6] Checking/Installing Containerd...${NC}"
if ! command -v containerd &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y containerd.io
fi

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
# Set SystemdCgroup = true
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# 3. Install Kubernetes Components
echo -e "\n${GREEN}[3/6] Checking/Installing Kubeadm, Kubelet, Kubectl...${NC}"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Use v1.31 for kubelet (fixes cadvisor parsing on newer kernels)
if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
fi

sudo apt-get update
# We use kubeadm 1.29 to remain compatible with 1.28/1.29 control plane logic
# AND kubelet 1.31 to fix the WSL2 crash
sudo apt-get install -y kubelet=1.31.14-1.1 kubeadm=1.29.15-1.1 kubectl=1.29.15-1.1 --allow-downgrades --allow-change-held-packages
sudo apt-mark hold kubelet kubeadm kubectl

# 4. Configure Kubelet for WSL2
echo -e "\n${GREEN}[4/6] Configuring Kubelet for WSL2...${NC}"
echo "KUBELET_EXTRA_ARGS=--fail-swap-on=false" | sudo tee /etc/default/kubelet

# 5. Join Cluster
echo -e "\n${GREEN}[5/6] Joining Cluster...${NC}"
# Updated JOIN CMD with fresh token generated at $(date)
JOIN_CMD="sudo kubeadm join 45.194.3.82:6443 --token e7pfyn.94efbajuyo7zopmv --discovery-token-ca-cert-hash sha256:e4ca8feb60449c29a8f6bdce3231b3e40c9c067ff2e63c1df2d152f3da41c19e --ignore-preflight-errors=Swap"

echo "Executing: $JOIN_CMD"
if $JOIN_CMD; then
    echo -e "${GREEN}Successfully joined!${NC}"
else
    echo -e "${RED}Join failed!${NC}"
    exit 1
fi

# 6. Verify Support
echo -e "\n${GREEN}[6/6] Verifying Kubelet...${NC}"
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sleep 5
sudo systemctl is-active kubelet

echo -e "\n${GREEN}=== Setup Complete! Node should be Ready soon. ===${NC}"
