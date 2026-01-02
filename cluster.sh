#!/bin/bash

# ==============================================================================
# Prasuti Unified Cluster Orchestrator (Bash SSH-Only Edition V6)
# ==============================================================================
# Orchestrates Kubernetes multi-node clusters across Cloud and WSL2 nodes.
# All operations are strictly SSH-based using the provided .pem key.
#
# Usage:
#   ./cluster.sh setup-master
#   ./cluster.sh setup-worker [cloud|wsl] [IP]
#   ./cluster.sh download-kubeconfig
#   ./cluster.sh status
# ==============================================================================

# --- Configuration ---
CLOUD_MASTER_IP="46.28.44.143"
VPN_MASTER_IP="100.90.139.24"
INTERNAL_KEY="$HOME/.ssh/id_prasuti_cluster"
SSH_KEY_FILE="$INTERNAL_KEY"
KUBECONFIG_DEST="SetupCloudCP/kubeconfig"

# Source secrets if available - stripped of quotes
if [ -f "application_secrets.prod.env" ]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.* ]] && continue
        [ -z "$key" ] && continue
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        export "$key"="$value"
    done < "application_secrets.prod.env"
fi

# WSL Sudo Password - used only for one-time passwordless sudo configuration
WSL_PASSWORD="UnitedFamily@2247"

# --- Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

LOG_FILE="cluster_orchestration.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo -e "${CYAN}--- Orchestration Session Started: $(date) ---${NC}"

# --- Initialization ---
prepare_ssh() {
    mkdir -p "$HOME/.ssh"
    if [ -f "$SSH_KEY_FILE" ]; then
        cp "$SSH_KEY_FILE" "$INTERNAL_KEY"
        chmod 600 "$INTERNAL_KEY" || true
    fi
}

# --- SSH Command Executor ---
# Uses Base64 encoding to bridge complex commands across SSH sessions without escaping hell.
invoke_ssh() {
    local host=$1; local user=$2; local cmd=$3; local is_wsl=$4
    prepare_ssh
    local b64_cmd=$(echo "$cmd" | base64 | tr -d '\n\r')
    local port=${SSH_PORT:-22}
    local sudo_cmd=${SUDO_CMD-"sudo"}
    echo -e "${NC}SSH: $user@$host:$port | Tasking...${NC}"
    if ! ssh -p "$port" -i "$INTERNAL_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no $SSH_OPTS "$user@$host" \
        "$sudo_cmd bash -c \"echo $b64_cmd | base64 -d | bash\""; then
        echo -e "${RED}ERROR: Task failed on $host${NC}"
        return 1
    fi
    return 0
}

# --- One-time Setup for Passwordless Sudo (WSL Only) ---
enable_passwordless_sudo() {
    local host=$1; local user=$2
    prepare_ssh
    local port=${SSH_PORT:-22}
    echo -e "${YELLOW}Configuring passwordless sudo for $user@$host:$port...${NC}"
    ssh -p "$port" -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no $SSH_OPTS "$user@$host" \
        "echo '$WSL_PASSWORD' | sudo -S bash -c 'echo \"$user ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/prasuti-nopasswd && chmod 0440 /etc/sudoers.d/prasuti-nopasswd'"
}

copy_to() {
    local host=$1; local user=$2; local src=$3; local dest=$4
    prepare_ssh
    local port=${SSH_PORT:-22}
    # Use cat over SSH as fallback for missing SFTP/SCP on target (e.g. Termux)
    # We use base64 to ensure binary safety if needed, but plain cat is usually fine for scripts.
    # To be safe against weird chars, we base64 encode then decode.
    local b64_content=$(base64 -w 0 "$src")
    if ! ssh -p "$port" -i "$INTERNAL_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no $SSH_OPTS "$user@$host" \
         "echo \"$b64_content\" | base64 -d > \"$dest\""; then
         echo -e "${RED}ERROR: Copy failed to $host:${dest}${NC}"
         return 1
    fi
}

# --- Main Actions ---
ACTION=$1; TYPE=$2; ADDR=$3

case $ACTION in
    "download-kubeconfig")
        echo -e "${GREEN}Syncing Kubeconfig from Master...${NC}"
        prepare_ssh
        ssh -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no ubuntu@$CLOUD_MASTER_IP "sudo cat /etc/kubernetes/admin.conf" | \
        sed -n '/apiVersion:/,$p' > "$KUBECONFIG_DEST"
        echo -e "${GREEN}✓ Done: $KUBECONFIG_DEST${NC}"
        ;;

    "setup-master")
        echo -e "${CYAN}--- Configuring Control Plane [$CLOUD_MASTER_IP] ---${NC}"
        copy_to "$CLOUD_MASTER_IP" "ubuntu" "scripts/node-prepare.sh" "/home/ubuntu/node-prepare.sh"
        invoke_ssh "$CLOUD_MASTER_IP" "ubuntu" "export TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' && chmod +x /home/ubuntu/node-prepare.sh && /home/ubuntu/node-prepare.sh" "false" || exit 1
        
        echo -e "${YELLOW}Initializing K8s Master...${NC}"
        invoke_ssh "$CLOUD_MASTER_IP" "ubuntu" "kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$VPN_MASTER_IP --control-plane-endpoint=$VPN_MASTER_IP --apiserver-cert-extra-sans=$VPN_MASTER_IP,$CLOUD_MASTER_IP" "false" || exit 1
        
        echo -e "${YELLOW}Deploying CNI (Flannel)...${NC}"
        invoke_ssh "$CLOUD_MASTER_IP" "ubuntu" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" "false" || exit 1
        bash $0 download-kubeconfig
        ;;

    "remove-worker")
        USER="ubuntu"; HOST="$ADDR"; IS_WSL="false"
        if [ "$TYPE" == "wsl" ]; then USER=${WORKER_USER:-"sangamesh"}; HOST="localhost"; IS_WSL="true"; fi
        [ -z "$HOST" ] && echo "Address Required" && exit 1
        
        echo -e "${YELLOW}Identifying Node Name at $HOST...${NC}"
        NODE_NAME=$(ssh -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no "$USER@$HOST" "hostname" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\n\r')
        
        if [ -n "$NODE_NAME" ]; then
            echo -e "${RED}Deleting Node $NODE_NAME from Cluster...${NC}"
            ssh -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no "ubuntu@$CLOUD_MASTER_IP" "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete node $NODE_NAME 2>/dev/null" || true
        fi
        
        echo -e "${YELLOW}Resetting Node Machine $HOST...${NC}"
        invoke_ssh "$HOST" "$USER" "kubeadm reset -f --cri-socket unix:///var/run/containerd/containerd.sock 2>/dev/null || true" "$IS_WSL"
        ;;

    "setup-worker")
        USER="ubuntu"; HOST="$ADDR"; IS_WSL="false"
        if [[ "$HOST" == *":"* ]]; then
            export SSH_PORT=$(echo $HOST | cut -d':' -f2)
            HOST=$(echo $HOST | cut -d':' -f1)
            ADDR=$HOST
        fi
        if [ "$TYPE" == "wsl" ]; then
            # Allow overriding user for other local-ish nodes (like Android)
            USER=${WORKER_USER:-"sangamesh"}
            # If ADDR was passed (e.g. localhost:2222), keep it. If empty, default to localhost.
            [ -z "$ADDR" ] && ADDR="localhost"
            HOST=$ADDR
            
            # Handle port parsing again if needed (though top block handles it, HOST reset above might kill it)
            if [[ "$HOST" == *":"* ]]; then
                export SSH_PORT=$(echo $HOST | cut -d':' -f2)
                HOST=$(echo $HOST | cut -d':' -f1)
            fi
            
            IS_WSL="true"
            # Only run this for the actual WSL laptop user
            if [ "$USER" == "sangamesh" ]; then
                 enable_passwordless_sudo "$HOST" "$USER"
            fi
        fi
        [ -z "$HOST" ] && echo "Target IP Required" && exit 1

        # SAFETY: Only remove previous node if FORCE_REMOVE is set
        # This prevents accidentally deleting existing cluster nodes
        if [ "$FORCE_REMOVE" == "true" ]; then
            echo -e "${YELLOW}FORCE_REMOVE=true: Cleaning previous node registration...${NC}"
            bash $0 remove-worker "$TYPE" "$ADDR"
        fi

        echo -e "${CYAN}--- Provisioning Worker: $HOST ($TYPE) ---${NC}"
        copy_to "$HOST" "$USER" "scripts/node-prepare.sh" "node-prepare.sh"
        # We use bash explicitly to handle Termux where #!/bin/bash might fail
        invoke_ssh "$HOST" "$USER" "export TAILSCALE_AUTH_KEY='$TAILSCALE_AUTH_KEY' && bash node-prepare.sh" "$IS_WSL" || echo "Warning: Node preparation had errors, continuing..."
        
        JOIN_CMD=$(ssh -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no ubuntu@$CLOUD_MASTER_IP "sudo kubeadm token create --print-join-command" | tr -d '\r')
        
        if [ "$IS_WSL" = "true" ]; then
            echo -e "${YELLOW}Launching WSL2 Persistence Watcher...${NC}"
            WATCHER='nohup bash -c "( for i in {1..60}; do if [ -f /var/lib/kubelet/config.yaml ]; then sed -i \"s/cgroupDriver: systemd/cgroupDriver: cgroupfs/g\" /var/lib/kubelet/config.yaml; if [ -f /var/lib/kubelet/kubeadm-flags.env ]; then if ! grep -q \"bootstrap-kubeconfig\" /var/lib/kubelet/kubeadm-flags.env; then echo \"KUBELET_KUBECONFIG_ARGS=\\\"--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --kubelet-cgroups=/ --runtime-cgroups=/ --enforce-node-allocatable=\\\"\\\"\\\"\" >> /var/lib/kubelet/kubeadm-flags.env; systemctl restart kubelet; break; fi; fi; fi; sleep 2; done )" > /dev/null 2>&1 &'
            invoke_ssh "$HOST" "$USER" "$WATCHER" "true"
            
            echo -e "${YELLOW}Syncing Cluster Access to Worker...${NC}"
            port=${SSH_PORT:-22}
            ssh -p "$port" -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no "$USER@$HOST" "mkdir -p ~/.kube"
            ssh -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no "ubuntu@$CLOUD_MASTER_IP" "sudo cat /etc/kubernetes/admin.conf" | ssh -p "$port" -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no "$USER@$HOST" "cat > ~/.kube/config && chmod 600 ~/.kube/config"
        fi

        # Use --ignore-preflight-errors=all for phone/PRoot environments
        # For standard nodes, we could be more selective, but this ensures compatibility
        
        # If cloud node, we might need to use CLOUD_MASTER_IP if Tailscale is down
        if [ "$TYPE" == "cloud" ]; then
            JOIN_CMD=$(echo "$JOIN_CMD" | sed "s/$VPN_MASTER_IP/$CLOUD_MASTER_IP/g")
        fi
        
        invoke_ssh "$HOST" "$USER" "$JOIN_CMD --ignore-preflight-errors=all --cri-socket unix:///var/run/containerd/containerd.sock" "$IS_WSL" || exit 1
        echo -e "${GREEN}✓ Node setup successfully completed.${NC}"
        ;;

    "deploy")
        SERVICE=$2; ENV=$3
        [ -z "$SERVICE" ] && echo "Service name required (e.g. www, services)" && exit 1
        [ -z "$ENV" ] && ENV="prod"
        
        # Mapping
        case $SERVICE in
            www) PROJECT="Prasuti-Mainsite" ;;
            services) PROJECT="Prasuti-Services" ;;
            accounts) PROJECT="Prasuti-Accounts" ;;
            *) PROJECT="Prasuti-$SERVICE" ;;
        esac

        echo -e "${CYAN}--- Building & Deploying $SERVICE to $ENV ---${NC}"
        
        # Build & Push & Deploy from WSL node (where Docker/Files/Kubeconfig are available)
        # We use 'sudo' for docker since node-prepare.sh installs it that way for isolation.
        DEPLOY_SCRIPT="
            cd /mnt/c/DATA/Work/Prasuti/$PROJECT
            echo 'Logging into GHCR...'
            echo '$GIT_TOKEN' | sudo docker login ghcr.io -u sangamesh --password-stdin
            echo 'Building Image...'
            sudo docker build -t ghcr.io/prasutiai/prasuti-$SERVICE:latest .
            echo 'Pushing Image...'
            sudo docker push ghcr.io/prasutiai/prasuti-$SERVICE:latest
            echo 'Applying Manifests via Kustomize...'
            KUBECONFIG=/home/sangamesh/.kube/config kubectl apply -k k8s/$ENV
        "
        invoke_ssh "localhost" "sangamesh" "$DEPLOY_SCRIPT" "true"
        echo -e "${GREEN}✓ Deployment task dispatched.${NC}"
        ;;

    "status")
        echo -e "${CYAN}--- Cluster Node Overview ---${NC}"
        prepare_ssh
        ssh -i "$INTERNAL_KEY" -o StrictHostKeyChecking=no ubuntu@$CLOUD_MASTER_IP "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
        ;;

    "bootstrap")
        bash $0 setup-master
        bash $0 setup-worker wsl
        bash $0 status
        ;;

    *)
        echo "Usage: $0 {download-kubeconfig | setup-master | setup-worker [cloud|wsl] [HOST] | status | bootstrap}"
        exit 1
        ;;
esac
