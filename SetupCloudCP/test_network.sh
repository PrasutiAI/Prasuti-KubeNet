#!/bin/bash
# Network Testing Script
# Usage: ./test_network.sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/server_config.env"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "\033[0;31mError: server_config.env not found!\033[0m"
    exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# Validate required variables
if [[ "$SERVER_HOST" == "your-server"* ]] || [ -z "$SERVER_HOST" ]; then
    echo -e "\033[0;31mError: SERVER_HOST is not set in server_config.env\033[0m"
    exit 1
fi

if [ -z "$SERVER_USER" ]; then
    SERVER_USER=ubuntu
fi

if [ -z "$SERVER_PORT" ]; then
    SERVER_PORT=22
fi

# Build SSH key path
SSH_KEY="$SCRIPT_DIR/$SSH_KEY_PATH"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "\033[0;31mError: SSH key not found at $SSH_KEY\033[0m"
    exit 1
fi

# Set correct permissions
chmod 600 "$SSH_KEY"

echo "=========================================="
echo "    Network Connectivity Tests"
echo "=========================================="
echo ""

# Test 1: Ping test
echo -e "\033[1;34m[Test 1]\033[0m Ping test to $SERVER_HOST"
if ping -c 4 "$SERVER_HOST" > /dev/null 2>&1; then
    echo -e "\033[0;32m  ✓ Ping successful\033[0m"
else
    echo -e "\033[0;33m  ✗ Ping failed (may be blocked by firewall)\033[0m"
fi
echo ""

# Test 2: Port connectivity
echo -e "\033[1;34m[Test 2]\033[0m Testing SSH port $SERVER_PORT connectivity"
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$SERVER_HOST/$SERVER_PORT" 2>/dev/null; then
    echo -e "\033[0;32m  ✓ Port $SERVER_PORT is open\033[0m"
else
    echo -e "\033[0;31m  ✗ Port $SERVER_PORT is closed or filtered\033[0m"
fi
echo ""

# Test 3: SSH connection test
echo -e "\033[1;34m[Test 3]\033[0m Testing SSH authentication"
if ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o BatchMode=yes -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
    echo -e "\033[0;32m  ✓ SSH authentication successful\033[0m"
else
    echo -e "\033[0;31m  ✗ SSH authentication failed\033[0m"
    echo -e "\033[0;33m    Check your SSH key and user credentials\033[0m"
fi
echo ""

# Test 4: Remote system information
echo -e "\033[1;34m[Test 4]\033[0m Gathering remote system information"
if ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o BatchMode=yes -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "echo '  OS: ' && cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2; echo '  Hostname: ' && hostname; echo '  Uptime: ' && uptime" 2>/dev/null; then
    echo ""
else
    echo -e "\033[0;31m  ✗ Failed to retrieve system information\033[0m"
fi
echo ""

# Test 5: Network interfaces on remote server
echo -e "\033[1;34m[Test 5]\033[0m Checking remote network interfaces"
ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o BatchMode=yes -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" 2>/dev/null | while read ip; do
    echo -e "\033[0;36m  IP Address: $ip\033[0m"
done
echo ""

# Test 6: Internet connectivity from remote server
echo -e "\033[1;34m[Test 6]\033[0m Testing internet connectivity from remote server"
if ssh -i "$SSH_KEY" -p "$SERVER_PORT" -o BatchMode=yes -o ConnectTimeout=10 "$SERVER_USER@$SERVER_HOST" "ping -c 2 8.8.8.8 > /dev/null 2>&1" 2>/dev/null; then
    echo -e "\033[0;32m  ✓ Remote server has internet connectivity\033[0m"
else
    echo -e "\033[0;31m  ✗ Remote server has no internet connectivity\033[0m"
fi
echo ""

echo "=========================================="
echo "    Test Summary Complete"
echo "=========================================="
