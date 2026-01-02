#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== WSL2 Kubernetes Worker Node Setup (Tailscale/VPN Edition) ===${NC}"
echo "This script setup this node to join via Tailscale VPN for NAT traversal."

# Configuration - UPDATE THESE VALUES AS NEEDED
# If Tailscale is up, this should be the Master's Tailscale IP
CONTROL_PLANE_IP="46.28.44.143"
CONTROL_PLANE_PORT="6443"
JOIN_TOKEN="yx1uxf.noqhhweple925idk"
CA_CERT_HASH="sha256:4306779d1874851110ea012a4ad88ba45cb858912c03092e96f640b39ce14427"

# ============================================================================
# STEP 0: Tailscale Setup
# ============================================================================
echo -e "\n${GREEN}[0/8] Setting up Tailscale VPN...${NC}"

if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! tailscale ip -4 &> /dev/null; then
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        echo "Joining Tailscale VPN using Auth Key..."
        tailscale up --authkey "$TAILSCALE_AUTH_KEY"
    else
        echo "Please authenticate Tailscale..."
        tailscale up --qr
    fi
fi

TS_IP=$(tailscale ip -4)
echo -e "${GREEN}✓ Local Tailscale IP: $TS_IP${NC}"

# ============================================================================
# STEP 1: Pre-flight Checks
# ============================================================================
echo -e "\n${GREEN}[1/8] Pre-flight Checks...${NC}"

if grep -q "Program.*Files.*Docker" /proc/mounts 2>/dev/null; then
    echo -e "${RED}✗ ERROR: Docker Desktop WSL integration detected. Please disable it.${NC}"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}✗ This script must be run with sudo${NC}"
    exit 1
fi

# Set MTU (Still good practice in WSL2)
ip link set dev eth0 mtu 1400

# ============================================================================
# STEP 2: Clean Previous Installation
# ============================================================================
echo -e "\n${GREEN}[2/8] Cleaning Previous Installation...${NC}"
systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true

if [ -f /etc/kubernetes/kubelet.conf ]; then
    kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock || true
fi

rm -rf /etc/cni/net.d
rm -rf /etc/kubernetes/
mkdir -p /etc/kubernetes/manifests
rm -f /var/lib/kubelet/kubeadm-flags.env 

# ============================================================================
# STEP 3: System Prep
# ============================================================================
modprobe overlay
modprobe br_netfilter
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1

# ============================================================================
# STEP 4: Containerd
# ============================================================================
if ! command -v containerd &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq containerd.io
fi
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# ============================================================================
# STEP 5: Kubelet Config (VPN Optimized)
# ============================================================================
echo -e "\n${GREEN}[5/8] Configuring Kubelet for VPN...${NC}"

# Important: We tell kubelet to use the Tailscale IP specifically
tee /etc/default/kubelet > /dev/null <<EOF
KUBELET_EXTRA_ARGS=--fail-swap-on=false --cgroup-driver=systemd --runtime-cgroups=/system.slice/containerd.service --kubelet-cgroups=/system.slice/kubelet.service --node-ip=$TS_IP
EOF

# ============================================================================
# STEP 6: Join Cluster
# ============================================================================
echo -e "\n${GREEN}[6/8] Joining Kubernetes Cluster via VPN...${NC}"

# Background patcher for kubeadm-flags.env
(
    EXPECTED='--bootstrap-kubeconfig'
    for i in {1..20}; do
        if [ -f /var/lib/kubelet/kubeadm-flags.env ]; then
            CONTENT=$(cat /var/lib/kubelet/kubeadm-flags.env)
            if [[ "$CONTENT" != *"$EXPECTED"* ]]; then
                echo 'KUBELET_KUBECONFIG_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"' >> /var/lib/kubelet/kubeadm-flags.env
                systemctl restart kubelet
                exit 0
            fi
        fi
        sleep 2
    done
) &

JOIN_CMD="kubeadm join ${CONTROL_PLANE_IP}:${CONTROL_PLANE_PORT} --token ${JOIN_TOKEN} --discovery-token-ca-cert-hash ${CA_CERT_HASH} --ignore-preflight-errors=Swap --cri-socket unix:///var/run/containerd/containerd.sock"

echo "Executing: $JOIN_CMD"
if $JOIN_CMD; then
    echo -e "${GREEN}✓ Successfully joined cluster!${NC}"
else
    echo -e "${RED}✗ Join failed! Check if CONTROL_PLANE_IP ($CONTROL_PLANE_IP) is correct.${NC}"
    exit 1
fi

# ============================================================================
# STEP 7: Finalize
# ============================================================================
systemctl enable kubelet
systemctl start kubelet

echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo "Node IP: $TS_IP"
