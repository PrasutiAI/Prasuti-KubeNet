#!/bin/bash
set -e

# Script Information
echo ""
echo "=== Prasuti Service Deployment Script ==="

# Parse arguments
SERVICE_NAME=""
ENVIRONMENT="dev"

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 -s|--service <service-name> [-e|--environment <env>]"
      echo "  Services: services, accounts, mail, profiles, www"
      echo "  Environments: dev, stg, prod (default: dev)"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name is required"
  echo "Usage: $0 -s|--service <service-name> [-e|--environment <env>]"
  echo "  Services: services, accounts, mail, profiles, www"
  echo "  Environments: dev, stg, prod (default: dev)"
  exit 1
fi

# Validate service name
case $SERVICE_NAME in
  services|accounts|mail|profiles|www)
    ;;
  *)
    echo "Error: Invalid service name: $SERVICE_NAME"
    echo "Valid services: services, accounts, mail, profiles, www"
    exit 1
    ;;
esac

# Validate environment
case $ENVIRONMENT in
  dev|stg|uat|prod)
    ;;
  *)
    echo "Error: Invalid environment: $ENVIRONMENT"
    echo "Valid environments: dev, stg, uat, prod"
    exit 1
    ;;
esac

echo "Service: $SERVICE_NAME"
echo "Environment: $ENVIRONMENT"
echo "========================================="
echo ""

# Configuration
KUBE_NAMESPACE="$ENVIRONMENT"
SERVICE_NAME_LOWER=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
IMAGE_NAME="ghcr.io/prasutiai/prasuti-$SERVICE_NAME_LOWER:latest"

# Map service name to project directory name (PascalCase)
case $SERVICE_NAME in
  services)
    PROJECT_DIR="Prasuti-Services"
    ;;
  accounts)
    PROJECT_DIR="Prasuti-Accounts"
    ;;
  mail)
    PROJECT_DIR="Prasuti-Mail"
    ;;
  profiles)
    PROJECT_DIR="Prasuti-Profiles"
    ;;
  www)
    PROJECT_DIR="Prasuti-Mainsite"
    ;;
esac

# Resolve project path (assuming script is in Prasuti-KubeNet, services are siblings)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_PATH="$WORKSPACE_ROOT/$PROJECT_DIR"

# Verify project exists
if [ ! -d "$PROJECT_PATH" ]; then
  echo "Error: Project directory not found: $PROJECT_PATH"
  exit 1
fi

echo "Project Path: $PROJECT_PATH"

# Verify k8s directory exists
K8S_PATH="$PROJECT_PATH/k8s"
if [ ! -d "$K8S_PATH" ]; then
  echo "Error: Kubernetes manifests not found at: $K8S_PATH"
  echo "Please ensure the project has been configured for Kubernetes deployment."
  exit 1
fi

# Determine Kustomize overlay path
KUSTOMIZE_PATH="$K8S_PATH/overlays/$ENVIRONMENT"
if [ ! -d "$KUSTOMIZE_PATH" ]; then
  # Check for direct environment folder (e.g. k8s/dev)
  if [ -d "$K8S_PATH/$ENVIRONMENT" ]; then
    KUSTOMIZE_PATH="$K8S_PATH/$ENVIRONMENT"
  else
    echo "Warning: Kustomize overlay not found at: $KUSTOMIZE_PATH or $K8S_PATH/$ENVIRONMENT"
    echo "Falling back to base k8s path..."
    KUSTOMIZE_PATH="$K8S_PATH"
  fi
fi

echo "Kustomize Path: $KUSTOMIZE_PATH"

# Determine kubeconfig path
if [ -n "$KUBECONFIG_PATH" ]; then
  KUBE_CONFIG="$KUBECONFIG_PATH"
elif [ -f "$SCRIPT_DIR/SetupCloudCP/kubeconfig" ]; then
  KUBE_CONFIG="$SCRIPT_DIR/SetupCloudCP/kubeconfig"
elif [ -f "$HOME/.kube/config" ]; then
  KUBE_CONFIG="$HOME/.kube/config"
else
  echo "Error: KUBECONFIG_PATH not set and default kubeconfig not found"
  echo "Please set KUBECONFIG_PATH environment variable or ensure kubeconfig exists at:"
  echo "  - $SCRIPT_DIR/SetupCloudCP/kubeconfig"
  echo "  - $HOME/.kube/config"
  exit 1
fi

echo "Kubeconfig: $KUBE_CONFIG"
echo ""

# Verify Dockerfile exists
DOCKERFILE_PATH="$PROJECT_PATH/Dockerfile"
if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "Error: Dockerfile not found at: $DOCKERFILE_PATH"
  exit 1
fi

# --- Step 0: Config Sync ---
echo "--- Step 0: Syncing Configurations ---"
SYNC_SCRIPT="$SCRIPT_DIR/scripts/sync-configs.js"
if [ -f "$SYNC_SCRIPT" ]; then
  if node "$SYNC_SCRIPT" --service "prasuti-$SERVICE_NAME_LOWER" --project-path "$PROJECT_PATH"; then
    echo "✓ Configurations synced successfully"
  else
    echo "Warning: Configuration sync encountered an issue. Proceeding..."
  fi
else
  echo "Warning: Sync script not found at $SYNC_SCRIPT"
fi
echo ""

# --- Step 1: Image Verification & Build (Build Once) ---
echo "--- Step 1: Image Verification & Build ---"
cd "$PROJECT_PATH" || exit 1

# Get Commit SHA
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d-%H%M)
IMAGE_BASE="${IMAGE_NAME%%:*}"
IMAGE_TAG="sha-$GIT_COMMIT"
TARGET_IMAGE="$IMAGE_BASE:$IMAGE_TAG"
LATEST_IMAGE="$IMAGE_BASE:latest"

echo "Target Version: $IMAGE_TAG"
echo "Checking registry for: $TARGET_IMAGE"

if docker manifest inspect "$TARGET_IMAGE" > /dev/null 2>&1; then
  echo "✓ Image already exists. Skipping build & push."
  echo "  Using: $TARGET_IMAGE"
else
  echo "Image not found. Building new version..."
  
  if ! docker build -t "$TARGET_IMAGE" -t "$LATEST_IMAGE" .; then
    echo "Error: Docker build failed"
    exit 1
  fi
  echo "✓ Docker image built successfully"
  
  echo ""
  echo "--- Step 2: Pushing Docker Image ---"
  
  if ! docker push "$TARGET_IMAGE"; then
    echo "Error: Docker push failed for $IMAGE_TAG"
    exit 1
  fi
  
  # Push latest as well (best effort)
  docker push "$LATEST_IMAGE" || echo "Warning: Failed to push 'latest' tag"
  
  echo "✓ Docker image pushed successfully"
fi
echo ""

# --- Step 3: Deployment (Deploy Anywhere) ---
echo "--- Step 3: Deployment ---"
echo "Namespace: $KUBE_NAMESPACE"
echo "Deploying version: $IMAGE_TAG"

# Generate manifest using kubectl kustomize, replace image tag, and apply
if ! kubectl kustomize "$KUSTOMIZE_PATH" | \
     sed "s|$IMAGE_BASE:latest|$TARGET_IMAGE|g" | \
     sed "s|$IMAGE_BASE@sha256:[a-f0-9]*|$TARGET_IMAGE|g" | \
     kubectl --kubeconfig "$KUBE_CONFIG" apply -f -; then
  echo "Error: Deployment failed"
  exit 1
fi

echo "✓ Kubernetes manifests applied successfully"
echo ""

# Success!
echo "========================================="
echo "✓ Deployment Complete!"
echo "========================================="
echo ""
echo "Check deployment status with:"
echo "  kubectl --kubeconfig $KUBE_CONFIG get pods -n $KUBE_NAMESPACE"
echo ""
echo "View logs with:"
echo "  kubectl --kubeconfig $KUBE_CONFIG logs -n $KUBE_NAMESPACE -l app=prasuti-$SERVICE_NAME_LOWER --tail=50 -f"
echo ""
