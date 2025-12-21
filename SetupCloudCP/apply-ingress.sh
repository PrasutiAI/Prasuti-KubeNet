#!/bin/bash
set -e

# Optimized Ingress Application Script (Runs on Remote Master)
# Usage: ./apply-ingress.sh <NAMESPACE> <ZONE_NAME> <SERVICES_COMMA_SEP> <ENVIRONMENT> <SERVER_IP>

NAMESPACE=$1
ZONE_NAME=$2
SERVICES_LIST=$3
ENVIRONMENT=$4
SERVER_IP=$5

if [ -z "$NAMESPACE" ] || [ -z "$ZONE_NAME" ] || [ -z "$SERVICES_LIST" ]; then
    echo "Usage: ./apply-ingress.sh <NAMESPACE> <ZONE_NAME> <SERVICES> <ENVIRONMENT> <SERVER_IP>"
    exit 1
fi

echo "--- Applying Optimized Ingress for Environment: $ENVIRONMENT (Namespace: $NAMESPACE) ---"

# 1. Ensure Namespace Exists
echo "Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Process each service
IFS=',' read -ra ADDR <<< "$SERVICES_LIST"
COMBINED_MANIFEST=""
TEMPLATE_FILE="ingress-template.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: $TEMPLATE_FILE not found in $(pwd)"
    exit 1
fi

TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")

for serviceName in "${ADDR[@]}"; do
    serviceName=$(echo "$serviceName" | xargs) # trim
    if [ -n "$serviceName" ]; then
        # Derive domain
        if [ "$ENVIRONMENT" == "prod" ]; then
            domain="$serviceName.$ZONE_NAME"
        else
            domain="$serviceName-$ENVIRONMENT.$ZONE_NAME"
        fi

        echo "Generating manifest for service: $serviceName ($domain)"
        
        manifest="$TEMPLATE_CONTENT"
        manifest="${manifest//\{\{NAME\}\}/prasuti-$serviceName}"
        manifest="${manifest//\{\{NAMESPACE\}\}/$NAMESPACE}"
        manifest="${manifest//\{\{HOST\}\}/$domain}"
        manifest="${manifest//\{\{SERVICE\}\}/prasuti-$serviceName}"
        
        COMBINED_MANIFEST+="$manifest"$'\n---\n'
    fi
done

# Special case for apex domain in production (if 'www' is present)
if [ "$ENVIRONMENT" == "prod" ] && [[ ",$SERVICES_LIST," == *",www,"* ]]; then
    echo "Generating manifest for apex domain: $ZONE_NAME"
    manifest="$TEMPLATE_CONTENT"
    manifest="${manifest//\{\{NAME\}\}/prasuti-apex}"
    manifest="${manifest//\{\{NAMESPACE\}\}/$NAMESPACE}"
    manifest="${manifest//\{\{HOST\}\}/$ZONE_NAME}"
    manifest="${manifest//\{\{SERVICE\}\}/prasuti-www}"
    COMBINED_MANIFEST+="$manifest"$'\n---\n'
fi

# Apply to cluster
echo "$COMBINED_MANIFEST" | kubectl apply -f -

echo "Ingress configurations applied successfully."
