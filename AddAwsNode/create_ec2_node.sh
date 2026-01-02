#!/bin/bash
# Prasuti Unified AWS Worker Node Orchestrator
# This script creates an AWS EC2 instance and joins it to the Kubernetes cluster.
# Designed to be run on any Linux/Unix environment (including WSL) via SSH.
set -e

# Pathing logic that works if run from its own dir or root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == *"/AddAwsNode" ]]; then
    ROOT_DIR="$(dirname "$SCRIPT_DIR")"
else
    ROOT_DIR="$SCRIPT_DIR"
    SCRIPT_DIR="$ROOT_DIR/AddAwsNode"
fi

# Source secrets if available - stripped of quotes and \r
if [ -f "$ROOT_DIR/application_secrets.prod.env" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        [[ "$key" =~ ^#.* ]] && continue
        [ -z "$key" ] && continue
        # Strip \r and quotes
        value=$(echo "$value" | tr -d '\r' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        export "$key"="$value"
    done < "$ROOT_DIR/application_secrets.prod.env"
fi

# --- Configuration & Credentials ---
if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: AWS_ACCESS_KEY and AWS_SECRET_ACCESS_KEY must be set (source application_secrets.prod.env)"
    exit 1
fi
REGION=${REGION:-"us-east-1"}
INSTANCE_TYPE="t2.micro"
KEY_NAME="prasuti-cluster-key"
SG_NAME="prasuti-worker-ssh-sg"

LOCAL_KEY_PATH="$HOME/.ssh/id_prasuti_cluster"
CLUSTER_ORCHESTRATOR="$ROOT_DIR/cluster.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}   PRASUTI CLUSTER: AWS EC2 NODE PROVISIONER      ${NC}"
echo -e "${CYAN}==================================================${NC}"

# Find AWS binary
AWS_BIN=$(command -v aws || echo "/usr/local/bin/aws")

# 1. Ensure AWS CLI is installed and functional
if ! "$AWS_BIN" --version &> /dev/null; then
    echo -e "${YELLOW}AWS CLI not detected. Attempting to install...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y -qq unzip curl
    sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -o -q awscliv2.zip
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    AWS_BIN="/usr/local/bin/aws"
fi

echo -e "${GREEN}✓ AWS CLI is ready: $("$AWS_BIN" --version | head -n 1)${NC}"

# 2. Configure AWS Environment
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$REGION

# 3. SSH Key Management (AWS Import)
if [ ! -f "$LOCAL_KEY_PATH" ]; then
    echo -e "${RED}Error: Cluster private key not found at $LOCAL_KEY_PATH${NC}"
    exit 1
fi

if ! "$AWS_BIN" ec2 describe-key-pairs --key-names "$KEY_NAME" > /dev/null 2>&1; then
    echo "Importing public key to AWS as '$KEY_NAME'..."
    cp "$LOCAL_KEY_PATH" /tmp/prasuti_temp_key
    chmod 600 /tmp/prasuti_temp_key
    
    # Save to temp file and import using fileb:// to avoid encoding issues
    ssh-keygen -y -f /tmp/prasuti_temp_key > /tmp/prasuti_temp_key.pub
    "$AWS_BIN" ec2 import-key-pair --key-name "$KEY_NAME" --public-key-material "fileb:///tmp/prasuti_temp_key.pub"
    rm /tmp/prasuti_temp_key.pub
    
    rm /tmp/prasuti_temp_key
    echo -e "${GREEN}✓ Key imported successfully.${NC}"
else
    echo -e "${GREEN}✓ Key pair '$KEY_NAME' exists in AWS.${NC}"
fi

# 4. AMI Selection (Ubuntu 24.04 LTS)
echo "Locating Ubuntu 24.04 AMI..."
AMI_ID=$("$AWS_BIN" ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)
echo "AMI ID: $AMI_ID"

# 5. Security Group
if ! "$AWS_BIN" ec2 describe-security-groups --group-names "$SG_NAME" > /dev/null 2>&1; then
    echo "Creating Security Group '$SG_NAME'..."
    VPC_ID=$("$AWS_BIN" ec2 describe-vpcs --filter "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
    SG_ID=$("$AWS_BIN" ec2 create-security-group --group-name "$SG_NAME" --description "Prasuti Worker Node Security" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
else
    SG_ID=$("$AWS_BIN" ec2 describe-security-groups --group-names "$SG_NAME" --query "SecurityGroups[0].GroupId" --output text)
    echo -e "${GREEN}✓ Security Group '$SG_NAME' exists ($SG_ID).${NC}"
fi

echo "Ensuring inbound traffic rules (SSH, K8s, Flannel, Tailscale, ICMP)..."
# Rules are added idempotently; AWS will ignore if they already exist
"$AWS_BIN" ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 2>/dev/null || true
"$AWS_BIN" ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 10250 --cidr 0.0.0.0/0 2>/dev/null || true
"$AWS_BIN" ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0 2>/dev/null || true
"$AWS_BIN" ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol udp --port 8472 --cidr 0.0.0.0/0 2>/dev/null || true
"$AWS_BIN" ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol udp --port 41641 --cidr 0.0.0.0/0 2>/dev/null || true
"$AWS_BIN" ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol icmp --port -1 --cidr 0.0.0.0/0 2>/dev/null || true

# 6. Check for existing instance or Launch New
echo -e "${YELLOW}Checking for existing 'prasuti-worker-cloud' instance...${NC}"
# Use a more robust query for existing instance
EXISTING_DATA=$("$AWS_BIN" ec2 describe-instances \
    --filters "Name=tag:Name,Values=prasuti-worker-cloud-medium" "Name=instance-state-name,Values=running,pending" \
    --query "Reservations[*].Instances[*].[InstanceId,PublicIpAddress]" --output text 2>/dev/null | head -n 1)

if [ -n "$EXISTING_DATA" ] && [ "$EXISTING_DATA" != "None" ]; then
    read -r INSTANCE_ID PUBLIC_IP <<< "$EXISTING_DATA"
    echo -e "${GREEN}✓ Found existing instance: $INSTANCE_ID${NC}"
else
    echo -e "${YELLOW}No running instance found. Launching new EC2 instance...${NC}"
    INSTANCE_ID=$("$AWS_BIN" ec2 run-instances \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=PrasutiWorker}]" \
        --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3}" \
        --query "Instances[0].InstanceId" \
        --output text)
    
    echo "Waiting for instance $INSTANCE_ID to reach 'running' state..."
    "$AWS_BIN" ec2 wait instance-running --instance-ids "$INSTANCE_ID"
fi

# Ensure we have a Public IP (Wait if pending)
echo "Retrieving Public IP for $INSTANCE_ID..."
for i in {1..30}; do
    # Corrected query: Reservations[0].Instances[0].PublicIpAddress
    PUBLIC_IP=$("$AWS_BIN" ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    if [ "$PUBLIC_IP" != "None" ] && [ -n "$PUBLIC_IP" ]; then
        break
    fi
    echo "Public IP not yet assigned, retrying in 5s... ($i/30)"
    sleep 5
done

if [ "$PUBLIC_IP" == "None" ] || [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}Error: Public IP was not assigned. Check if your VPC/Subnet allows public IPs.${NC}"
    exit 1
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}AWS EC2 INSTANCE: $PUBLIC_IP ($INSTANCE_ID)${NC}"
echo -e "${GREEN}========================================${NC}"

# 7. Kubernetes Cluster Join
echo -e "\n${CYAN}--- Joining Node to Cluster ---${NC}"
# Only wait if it's a fresh boot (very rough check: if we just created it)
# For simplicity, we always wait a bit to ensure SSH is up
echo "Verifying SSH connectivity (waiting 30s)..."
sleep 30

# Debug Connectivity to Master
echo "Testing connectivity to Master (46.28.44.143)..."
ssh -i "$LOCAL_KEY_PATH" -o StrictHostKeyChecking=no "ubuntu@$PUBLIC_IP" "curl -k -m 5 https://46.28.44.143:6443/livez || echo '6443 blocked'"
ssh -i "$LOCAL_KEY_PATH" -o StrictHostKeyChecking=no "ubuntu@$PUBLIC_IP" "timeout 2 bash -c 'cat < /dev/tcp/46.28.44.143/22' && echo 'Port 22 Open' || echo 'Port 22 Blocked'"


cd "$ROOT_DIR"
if [ -f "./cluster.sh" ]; then
    chmod +x ./cluster.sh
    echo "Executing Provisioning: ./cluster.sh setup-worker cloud $PUBLIC_IP"
    ./cluster.sh setup-worker cloud "$PUBLIC_IP"
else
    echo -e "${RED}Error: cluster.sh not found at $ROOT_DIR${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ Node $PUBLIC_IP setup sequence complete.${NC}"
./cluster.sh status
