# Prasuti-KubeNet Deployment Scripts

Generic deployment scripts for all Prasuti services to Kubernetes infrastructure.

## Quick Start

### Deploy a Service

**Windows (PowerShell):**
```powershell
.\deploy-service.ps1 -ServiceName services -Environment dev
```

**Linux/macOS (Bash):**
```bash
./deploy-service.sh -s services -e dev
```

## Available Services

- `services` - Core API services
- `accounts` - Authentication & user management
- `mail` - Email service
- `profiles` - User profiles
- `www` - Main website

## Available Environments

- `dev` - Development
- `stg` - Staging
- `prod` - Production

## What Gets Deployed

The script automatically:
1. ✓ Builds Docker image: `ghcr.io/prasutiai/prasuti-<service>:latest`
2. ✓ Pushes to GitHub Container Registry
3. ✓ Applies Kubernetes manifests using Kustomize
4. ✓ Verifies deployment status

## More Information

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for:
- Detailed usage instructions
- Prerequisites and setup
- Troubleshooting guide
- CI/CD integration examples
- Best practices

## Examples

```powershell
# Deploy services to dev
.\deploy-service.ps1 -ServiceName services

# Deploy accounts to staging
.\deploy-service.ps1 -ServiceName accounts -Environment stg

# Deploy all services to dev
@("services", "accounts", "mail", "profiles", "www") | ForEach-Object {
  .\deploy-service.ps1 -ServiceName $_
}
```

## Infrastructure Setup

This directory also contains infrastructure-as-code for:
- Kubernetes cluster setup (`SetupCloudCP/`)
- Multi-node worker support (`AddLaptopAsNode/`)
- DNS configuration (`cloudflare/`)
- Environment secrets (`application_secrets.*.env`)

Run `.\setup-infrastructure.ps1 -Environment dev` to setup complete infrastructure.
