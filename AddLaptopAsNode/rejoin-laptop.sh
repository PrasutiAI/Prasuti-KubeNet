#!/bin/bash
# Re-runnable Consolidated Script to Add Laptop as Kubernetes Node (WSL2)
# Version: 1.6 (cgroupfs Workaround)

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Resilient Kubernetes Node Setup (WSL2 cgroupfs) ===${NC}"

# 1. Full Reset & Cleanup
echo -e "${YELLOW}[1/7] Cleaning up previous state...${NC}"
systemctl stop kubelet || true
kubeadm reset -f || true
rm -f /etc/apt/sources.list.d/kubernetes*.list
rm -rf /etc/cni/net.d
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/*
ip link delete cni0 || true
ip link delete flannel.1 || true

# 2. Kernel & Networking
echo -e "${YELLOW}[2/7] Configuring networking...${NC}"
modprobe overlay || true
modprobe br_netfilter || true
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 3. Containerd (cgroupfs)
echo -e "${YELLOW}[3/7] Ensuring Containerd is configured with cgroupfs...${NC}"
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
# Set SystemdCgroup = false (explicitly)
sed -i 's/SystemdCgroup = true/SystemdCgroup = false/g' /etc/containerd/config.toml
systemctl restart containerd

# 4. Install Components
echo -e "${YELLOW}[4/7] Installing stable versions...${NC}"
mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-*.gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-1.29.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1.29.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-1.31.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-1.31.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" >> /etc/apt/sources.list.d/kubernetes.list

apt-get update
# Use kubeadm/kubectl 1.29.15 and kubelet 1.31.2
apt-get install -y --allow-change-held-packages --allow-downgrades \
    kubelet=1.31.2-1.1 \
    kubeadm=1.29.15-1.1 \
    kubectl=1.29.15-1.1
    
apt-mark hold kubelet kubeadm kubectl

# 5. Systemd Configuration (Drop-in)
echo -e "${YELLOW}[5/7] Configuring kubelet service drop-in...${NC}"
mkdir -p /etc/systemd/system/kubelet.service.d/
cat <<EOF | tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF

# Use cgroup-driver=cgroupfs to match containerd
echo 'KUBELET_EXTRA_ARGS="--fail-swap-on=false --cgroup-driver=cgroupfs --cgroups-per-qos=false --enforce-node-allocatable="' | tee /etc/default/kubelet
systemctl daemon-reload

# 6. Join Cluster
echo -e "${YELLOW}[6/7] Joining Cluster...${NC}"
JOIN_CMD="kubeadm join 45.194.3.82:6443 --token e7pfyn.94efbajuyo7zopmv --discovery-token-ca-cert-hash sha256:e4ca8feb60449c29a8f6bdce3231b3e40c9c067ff2e63c1df2d152f3da41c19e --ignore-preflight-errors=Swap,SystemVerification"

$JOIN_CMD || true

# 7. Final Verification
echo -e "${YELLOW}[7/7] Final verification...${NC}"
# Patch the config.yaml to ensure cgroupDriver is cgroupfs
CONFIG_FILE="/var/lib/kubelet/config.yaml"
if [ -f "$CONFIG_FILE" ]; then
    sed -i 's/cgroupDriver: systemd/cgroupDriver: cgroupfs/g' "$CONFIG_FILE"
fi

systemctl restart kubelet
sleep 15

if systemctl is-active --quiet kubelet; then
    echo -e "${GREEN}=== Node successfully joined using cgroupfs! ===${NC}"
else
    echo -e "${RED}Still failing. Attempting raw start...${NC}"
    /usr/bin/kubelet --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock --fail-swap-on=false --cgroup-driver=cgroupfs --v=5 &
    RAW_PID=$!
    sleep 10
    kill $RAW_PID || true
    systemctl restart kubelet
    sleep 5
    systemctl is-active --quiet kubelet && echo -e "${GREEN}Running!${NC}" || echo -e "${RED}Fatal failure.${NC}"
fi
