#!/bin/bash
# Bash Script to Connect to Server
# Usage: ./connect.sh

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
    echo -e "\033[0;33mPlease edit server_config.env with your actual server details\033[0m"
    exit 1
fi

if [ -z "$SERVER_USER" ]; then
    echo -e "\033[0;31mError: SERVER_USER is not set\033[0m"
    exit 1
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

# Set correct permissions for SSH key
chmod 600 "$SSH_KEY"

# Display connection info
echo -e "\033[0;32mConnecting to server...\033[0m"
echo -e "\033[0;36m  Host: $SERVER_HOST\033[0m"
echo -e "\033[0;36m  User: $SERVER_USER\033[0m"
echo -e "\033[0;36m  Port: $SERVER_PORT\033[0m"
echo -e "\033[0;36m  Key:  $SSH_KEY\033[0m"
echo ""

# Connect using SSH
ssh -i "$SSH_KEY" -p "$SERVER_PORT" "$SERVER_USER@$SERVER_HOST"
