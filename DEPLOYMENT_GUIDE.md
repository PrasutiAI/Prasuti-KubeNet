# Prasuti Service Deployment Guide

This guide explains how to use the generic deployment scripts in Prasuti-KubeNet to deploy any Prasuti service to Kubernetes.

## Overview

The deployment scripts (`deploy-service.ps1` and `deploy-service.sh`) provide a standardized way to deploy any Prasuti service to Kubernetes environments using the infrastructure-as-code approach.

### Supported Services

- **services** - Prasuti-Services (Core API services)
- **accounts** - Prasuti-Accounts (Authentication & user management)
- **mail** - Prasuti-Mail (Email service)
- **profiles** - Prasuti-Profiles (User profiles)
- **www** - Prasuti-Mainsite (Main website)

### Supported Environments

- **dev** - Development environment
- **stg** - Staging environment
- **prod** - Production environment

## Prerequisites

### Required Tools

1. **Docker** - For building and pushing container images
   ```bash
   docker --version
   ```

2. **kubectl** - For deploying to Kubernetes
   ```bash
   kubectl version --client
   ```

3. **Kubeconfig** - Valid Kubernetes configuration file

### Authentication

1. **GitHub Container Registry (GHCR)**
   ```bash
   # Login to GHCR
   echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
   ```

2. **Kubernetes Cluster** - Ensure your kubeconfig is properly configured

## Usage

### PowerShell (Windows)

```powershell
# Deploy to development (default)
.\deploy-service.ps1 -ServiceName services

# Deploy to staging
.\deploy-service.ps1 -ServiceName accounts -Environment stg

# Deploy to production
.\deploy-service.ps1 -ServiceName mail -Environment prod
```

### Bash (Linux/macOS)

```bash
# Make script executable (first time only)
chmod +x deploy-service.sh

# Deploy to development (default)
./deploy-service.sh -s services

# Deploy to staging
./deploy-service.sh -s accounts -e stg

# Deploy to production
./deploy-service.sh -s mail -e prod
```

## How It Works

The deployment script performs the following steps:

### 1. Validation
- Validates service name and environment
- Resolves project path based on service name
- Verifies k8s manifests exist
- Locates kubeconfig file

### 2. Docker Build
- Builds Docker image with standardized naming: `ghcr.io/prasutiai/prasuti-<service>:latest`
- Tags image appropriately

### 3. Docker Push
- Pushes image to GitHub Container Registry (GHCR)

### 4. Kubernetes Deployment
- Applies Kubernetes manifests using Kustomize
- Uses environment-specific overlays if available
- Falls back to base manifests if overlay doesn't exist

## Configuration

### Kubeconfig Location

The script searches for kubeconfig in the following order:

1. `$KUBECONFIG_PATH` environment variable
2. `./SetupCloudCP/kubeconfig` (relative to script)
3. `~/.kube/config` (default kubectl location)

To set a custom kubeconfig path:

**PowerShell:**
```powershell
$env:KUBECONFIG_PATH = "C:\path\to\kubeconfig"
```

**Bash:**
```bash
export KUBECONFIG_PATH="/path/to/kubeconfig"
```

### Project Structure

The script expects the following structure:

```
Prasuti/
├── Prasuti-KubeNet/
│   ├── deploy-service.ps1
│   ├── deploy-service.sh
│   └── SetupCloudCP/
│       └── kubeconfig
├── Prasuti-Services/
│   ├── Dockerfile
│   └── k8s/
│       ├── base/
│       └── overlays/
│           ├── dev/
│           ├── stg/
│           └── prod/
├── Prasuti-Accounts/
├── Prasuti-Mail/
├── Prasuti-Profiles/
└── Prasuti-Mainsite/
```

### Naming Conventions

The script uses the following standardized naming:

- **Docker Images**: `ghcr.io/prasutiai/prasuti-<service>:latest`
- **K8s Resources**: `prasuti-<service>`
- **K8s Namespace**: `<environment>` (dev, stg, prod)

## Examples

### Deploy Services to Development

```powershell
# Windows
.\deploy-service.ps1 -ServiceName services

# Linux/macOS
./deploy-service.sh -s services
```

### Deploy Accounts to Staging

```powershell
# Windows
.\deploy-service.ps1 -ServiceName accounts -Environment stg

# Linux/macOS
./deploy-service.sh -s accounts -e stg
```

### Deploy Mail to Production

```powershell
# Windows
.\deploy-service.ps1 -ServiceName mail -Environment prod

# Linux/macOS
./deploy-service.sh -s mail -e prod
```

### Deploy All Services to Dev

**PowerShell:**
```powershell
@("services", "accounts", "mail", "profiles", "www") | ForEach-Object {
  Write-Host "`nDeploying $_..." -ForegroundColor Cyan
  .\deploy-service.ps1 -ServiceName $_ -Environment dev
}
```

**Bash:**
```bash
for service in services accounts mail profiles www; do
  echo -e "\nDeploying $service..."
  ./deploy-service.sh -s $service -e dev
done
```

## Verification

After deployment, verify the status:

```bash
# Check pods
kubectl get pods -n dev

# Check specific service
kubectl get pods -n dev -l app=prasuti-services

# View logs
kubectl logs -n dev -l app=prasuti-services --tail=50 -f

# Check ingress
kubectl get ingress -n dev

# Check all resources
kubectl get all -n dev
```

## Troubleshooting

### Docker Build Fails

**Issue**: Docker build fails with errors

**Solutions**:
- Ensure you're in the correct project directory
- Check Dockerfile syntax
- Verify all dependencies are available
- Check Docker daemon is running: `docker ps`

### Docker Push Fails

**Issue**: `unauthorized: authentication required`

**Solution**: Login to GHCR
```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

### Kubectl Apply Fails

**Issue**: `error: couldn't get resource list for...`

**Solutions**:
- Verify kubeconfig is correct: `kubectl cluster-info`
- Check you have permissions: `kubectl auth can-i create deployments -n dev`
- Ensure namespace exists: `kubectl get namespace dev`

### Service Not Accessible

**Issue**: Deployed but can't access the service

**Solutions**:
- Check pod status: `kubectl get pods -n dev`
- Check pod logs: `kubectl logs -n dev <pod-name>`
- Verify ingress: `kubectl get ingress -n dev`
- Check service: `kubectl get svc -n dev`

### Project Not Found

**Issue**: `Error: Project directory not found`

**Solution**: Ensure you're running the script from the Prasuti-KubeNet directory and all service projects are at the same level:
```
Prasuti/
├── Prasuti-KubeNet/     <- Run script from here
├── Prasuti-Services/
├── Prasuti-Accounts/
etc.
```

## Best Practices

1. **Always test in dev first** before deploying to staging or production
2. **Use version tags** for production deployments (future enhancement)
3. **Monitor logs** after deployment to ensure services start correctly
4. **Keep kubeconfig secure** and never commit to version control
5. **Use environment-specific overlays** for different configurations

## Integration with CI/CD

These scripts can be integrated into CI/CD pipelines:

### GitHub Actions Example

```yaml
name: Deploy Service
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Login to GHCR
        run: echo ${{ secrets.GITHUB_TOKEN }} | docker login ghcr.io -u ${{ github.actor }} --password-stdin
      
      - name: Deploy to Dev
        run: |
          cd ../Prasuti-KubeNet
          ./deploy-service.sh -s services -e dev
```

## Future Enhancements

- [ ] Support for image versioning/tagging
- [ ] Automated rollback on deployment failure
- [ ] Health check verification after deployment
- [ ] Multi-region deployment support
- [ ] Secrets management integration
- [ ] Blue-green deployment strategy
