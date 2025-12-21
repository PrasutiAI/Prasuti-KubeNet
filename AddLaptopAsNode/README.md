# Kubernetes Worker Node Setup Scripts

This repository contains PowerShell scripts to set up a Windows machine as a Kubernetes worker node and join it to an existing cluster.

## Prerequisites

- Windows Server 2019 or later / Windows 10/11 Pro/Enterprise
- Administrator access
- Internet connectivity
- An existing Kubernetes cluster (e.g., The Ace Cloud managed cluster)
- Cluster kubeconfig file (`c-m-l9bg25vk.yaml`)

## Scripts Overview

| Script | Description |
|--------|-------------|
| `1-check-prerequisites.ps1` | Validates system requirements (OS version, Hyper-V, containers feature) |
| `2-install-containerd.ps1` | Installs and configures containerd container runtime |
| `3-install-kubernetes.ps1` | Downloads and installs Kubernetes components (kubelet, kubeadm, kubectl) |
| `4-join-cluster.ps1` | **Joins the node to the Kubernetes cluster** |
| `5-verify-node.ps1` | Verifies the node is properly joined and running |

## Quick Start

Run these scripts **in order** as Administrator:

```powershell
# 1. Check prerequisites
.\1-check-prerequisites.ps1

# 2. Install containerd
.\2-install-containerd.ps1

# 3. Install Kubernetes components
.\3-install-kubernetes.ps1

# 4. Join the cluster
.\4-join-cluster.ps1

# 5. Verify the setup
.\5-verify-node.ps1
```

## Detailed Step-by-Step Guide

### Step 1: Check Prerequisites

```powershell
.\1-check-prerequisites.ps1
```

This script checks:
- ✅ Windows version compatibility
- ✅ Hyper-V feature availability
- ✅ Containers feature
- ✅ Available disk space and memory

### Step 2: Install containerd

```powershell
.\2-install-containerd.ps1
```

This script:
- Downloads and installs containerd
- Configures containerd for Windows
- Creates and starts the containerd Windows service
- Verifies the installation

### Step 3: Install Kubernetes

```powershell
.\3-install-kubernetes.ps1
```

This script:
- Downloads kubelet, kubeadm, and kubectl
- Installs CNI plugins
- Creates necessary directories
- Installs NSSM (service wrapper)
- Creates kubelet startup script

### Step 4: Join the Cluster ⭐

```powershell
.\4-join-cluster.ps1
```

**This is the main script for joining your cluster!**

The script will:
1. **Attempt automatic token generation** using your kubeconfig
2. **Extract CA certificate hash** from the kubeconfig
3. **Generate the join command** automatically if possible
4. **Prompt for manual join command** if automatic generation fails

#### Join Methods:

**Option A: Automatic (if you have cluster-admin access)**
- The script will try to create a join token using kubectl
- If successful, it will display the complete join command
- Follow the prompts to execute the join

**Option B: Manual (recommended for managed clusters)**
1. Get the join command from The Ace Cloud dashboard:
   - Log into [The Ace Cloud Dashboard](https://dashboard.theacecloud.com)
   - Navigate to your cluster: `prasuti-fqdn`
   - Look for "Add Worker Node" or "Get Join Command"
   - Copy the join command

2. Run the script and paste the command when prompted

**Option C: Using kubectl on control plane**
If you have access to a control plane node:
```bash
kubeadm token create --print-join-command
```

### Step 5: Verify Node

```powershell
.\5-verify-node.ps1
```

This script checks:
- Containerd service status
- Kubelet service status
- Node registration in cluster
- Pod scheduling capability
- Windows features configuration

## Cluster Information

- **Cluster Name**: prasuti-fqdn
- **API Server**: `https://e6cb868d-ac12-47af-a171-67420418f77f-ap-south-noi-1.kaas.theacecloud.com:6443`
- **Provider**: The Ace Cloud (Managed Kubernetes)
- **Kubeconfig**: `c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml`

## Troubleshooting

### Node not appearing in cluster
```powershell
# Check kubelet service
Get-Service kubelet

# Check kubelet logs
Get-EventLog -LogName Application -Source kubelet -Newest 50

# Check NSSM service status
& 'C:\Program Files\Kubernetes\bin\nssm.exe' status kubelet
```

### Containerd not running
```powershell
# Check service status
Get-Service containerd

# Start the service
Start-Service containerd

# Check containerd configuration
& 'C:\Program Files\containerd\bin\ctr.exe' version
```

### Join command fails
- Ensure containerd is running: `Get-Service containerd`
- Check network connectivity to API server
- Verify firewall allows outbound HTTPS (443) to the cluster
- Confirm the token is still valid (tokens expire after 24 hours by default)

### Permission errors
- Ensure you're running PowerShell as Administrator
- Check that scripts can execute: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`

## Network Requirements

The worker node needs outbound access to:
- **Cluster API Server**: `e6cb868d-ac12-47af-a171-67420418f77f-ap-south-noi-1.kaas.theacecloud.com:6443`
- **Container Registry**: For pulling container images (e.g., mcr.microsoft.com)
- **Kubernetes Downloads**: `dl.k8s.io`
- **GitHub**: For CNI plugins and NSSM downloads

## File Locations

| Component | Location |
|-----------|----------|
| Kubernetes binaries | `C:\Program Files\Kubernetes\bin\` |
| Containerd | `C:\Program Files\containerd\` |
| Kubelet config | `C:\var\lib\kubelet\` |
| CNI config | `C:\etc\cni\net.d\` |
| CNI binaries | `C:\opt\cni\bin\` |
| Kubeconfig | `c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml` |

## Next Steps After Joining

1. **Verify node status**:
   ```powershell
   kubectl --kubeconfig=c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml get nodes
   ```

2. **Check node details**:
   ```powershell
   kubectl --kubeconfig=c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml describe node $env:COMPUTERNAME.ToLower()
   ```

3. **Watch for pods**:
   ```powershell
   kubectl --kubeconfig=c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml get pods --all-namespaces -w
   ```

## Important Notes

- ⚠️ All scripts must be run as **Administrator**
- ⚠️ The node name will be your computer's hostname in lowercase
- ⚠️ Join tokens typically expire after 24 hours
- ⚠️ Windows containers can only run Windows workloads (not Linux containers)
- ⚠️ A system restart may be required after installing prerequisites

## Support

For issues specific to:
- **The Ace Cloud**: Contact The Ace Cloud support or check their documentation
- **Windows Kubernetes**: See [Kubernetes documentation for Windows](https://kubernetes.io/docs/setup/production-environment/windows/)
- **These scripts**: Check the troubleshooting section above

## Version Information

- **Kubernetes Version**: 1.29.0
- **CNI Plugins Version**: 1.4.0
- **Containerd**: Latest stable from main repository
- **NSSM Version**: 2.24
