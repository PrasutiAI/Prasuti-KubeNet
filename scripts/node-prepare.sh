#!/bin/bash
# Unified Kubernetes Node Preparation Script
# This script is designed to run on BOTH Cloud and WSL nodes.

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/prasuti-node-prepare.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${GREEN}=== Unified Node Preparation Started: $(date) ===${NC}"
echo "Logging to $LOG_FILE"

# Detect Environment
IS_WSL=$(grep -qi microsoft /proc/version && echo "true" || echo "false")
echo "Environment: $([ "$IS_WSL" == "true" ] && echo "WSL2 Laptop" || echo "Cloud Server")"

# 1. Tailscale Setup
echo -e "\n${YELLOW}[1/6] Ensuring Tailscale VPN is active...${NC}"
if ! command -v tailscale &> /dev/null; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale ip -4 &> /dev/null; then
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        echo "Joining Tailscale VPN using Auth Key..."
        tailscale up --authkey "$TAILSCALE_AUTH_KEY" --hostname "$(hostname)-$(date +%s)" --accept-dns=false --reset || echo -e "${RED}Warning: Tailscale join failed. Node will proceed without VPN.${NC}"
    else
        echo -e "${YELLOW}Warning: Tailscale IP not found and TAILSCALE_AUTH_KEY is missing. Proceeding without VPN...${NC}"
    fi
fi

# Determine Local IP for K8s
TS_IP=$(tailscale ip -4 2>/dev/null || true)
if [ -z "$TS_IP" ]; then
    TS_IP=$(hostname -I | awk '{print $1}')
    echo -e "${YELLOW}!!! Tailscale Down. Using Public/Local IP: $TS_IP${NC}"
    
    # HOST REDIRECT HACK (Important for Kubeadm Join over Public IP)
    # The Master's advertise-address is set to the VPN IP (100.90.139.24).
    # If we join via Public IP, kubeadm will later try to connect to the VPN IP.
    # We redirect the VPN IP to the Public IP in /etc/hosts.
    MASTER_PUBLIC_IP="46.28.44.143"
    MASTER_VPN_IP="100.90.139.24"
    if ! grep -q "$MASTER_VPN_IP" /etc/hosts; then
        echo "Redirecting $MASTER_VPN_IP -> $MASTER_PUBLIC_IP in /etc/hosts"
        echo "$MASTER_PUBLIC_IP $MASTER_VPN_IP" | tee -a /etc/hosts
    fi
else
    echo -e "${GREEN}✓ Local VPN IP: $TS_IP${NC}"
fi

# 2. System Settings & Cleanup
echo -e "\n${YELLOW}[2/6] Configuring OS settings...${NC}"
systemctl stop kubelet 2>/dev/null || true

# Cleanup if already joined or failed
if [ -d /etc/kubernetes ] || [ -d /var/lib/kubelet ]; then
    echo "Cleaning up previous Kubernetes state..."
    kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock 2>/dev/null || true
    rm -rf /etc/kubernetes/* || true
    rm -rf /var/lib/kubelet/* || true
    rm -rf /etc/cni/net.d/* || true
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
fi

swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

modprobe overlay || true
modprobe br_netfilter || true
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1

# 3. Install Docker & Containerd
echo -e "\n${YELLOW}[3/6] Installing/Configuring Internal Containerd (WSL Isolation)...${NC}"

if [ "$IS_WSL" == "true" ]; then
    echo "Ensuring Docker Desktop interop is bypassed..."
    # Unmount Windows Docker mounts that break cAdvisor parsing
    umount /Docker/host 2>/dev/null || true
    umount /mnt/wsl/docker-desktop-bind-mounts/Ubuntu* 2>/dev/null || true
fi

if [ "$IS_WSL" == "true" ]; then
    echo "Purging Docker Desktop remnants in WSL..."
    # If binaries are symlinks to Docker Desktop, remove them
    for tool in docker docker-compose docker-credential-desktop kubectl kubeadm kubelet; do
        if [ -L "/usr/bin/$tool" ] && readlink "/usr/bin/$tool" | grep -q "docker-desktop"; then rm -f "/usr/bin/$tool"; fi
        if [ -L "/usr/local/bin/$tool" ] && readlink "/usr/local/bin/$tool" | grep -q "docker-desktop"; then rm -f "/usr/local/bin/$tool"; fi
    done
    # Cleanup broken CLI plugins
    find /usr/local/lib/docker/cli-plugins /usr/lib/docker/cli-plugins -type l -xtype l -delete 2>/dev/null || true
    find /usr/local/lib/docker/cli-plugins /usr/lib/docker/cli-plugins -type l 2>/dev/null | xargs -I {} bash -c 'if readlink "{}" | grep -q "docker-desktop"; then rm -f "{}"; fi' || true
fi

if ! command -v docker &> /dev/null || ! command -v containerd &> /dev/null; then
    echo "Installing Internal Docker Engine..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg conntrack socat
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || \
    apt-get install -y -qq docker.io containerd
else
    # Ensure conntrack and socat are present even if docker is already installed
    apt-get update -qq && apt-get install -y -qq conntrack socat containerd
fi

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
if [ "$IS_WSL" == "true" ]; then
    echo "WSL: Using isolated config for containerd"
    sed -i 's/SystemdCgroup = true/SystemdCgroup = false/g' /etc/containerd/config.toml
else
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
fi
systemctl restart containerd
systemctl enable containerd >/dev/null 2>&1

K8S_VERSION="1.31"

CURRENT_VER=$(kubeadm version -o short 2>/dev/null || echo "none")
if [[ "$CURRENT_VER" != "v$K8S_VERSION"* ]]; then
    echo "Updating Kubernetes components to v$K8S_VERSION..."
    apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
    apt-get update -qq && apt-get install -y -qq apt-transport-https ca-certificates curl gpg
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update -qq
    apt-get install -y -qq kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
fi

# 5. Environment Specific Fixes
if [ "$IS_WSL" == "true" ]; then
    echo "Applying WSL2-specific fixes (MTU, Kubelet args)..."
    ip link set dev eth0 mtu 1400
    # Use cgroupfs in WSL to avoid the cAdvisor mountinfo error (v1.31)
    # We also pass cgroupfs explicitly to kubelet
    tee /etc/default/kubelet > /dev/null <<EOF
KUBELET_EXTRA_ARGS=--fail-swap-on=false --node-ip=$TS_IP --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock --cgroup-driver=cgroupfs
EOF
else
    # Cloud specific
    tee /etc/default/kubelet > /dev/null <<EOF
KUBELET_EXTRA_ARGS=--node-ip=$TS_IP
EOF
fi

echo -e "${GREEN}✓ Node preparation complete!${NC}"
echo -e "${YELLOW}Proceeding to Join/Initialize...${NC}"
