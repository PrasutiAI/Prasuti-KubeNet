$ErrorActionPreference = "Continue"
Write-Host "Starting kubelet debug..."
& "C:\Program Files\Kubernetes\bin\kubelet.exe" --config=C:\var\lib\kubelet\config.yaml --bootstrap-kubeconfig=C:\etc\kubernetes\bootstrap-kubelet.conf --kubeconfig=C:\var\lib\kubelet\kubeconfig --cert-dir=C:\var\lib\kubelet\pki --runtime-cgroups=/system.slice/containerd.service --cgroup-driver=cgroupfs --container-runtime-endpoint=npipe:////./pipe/containerd-containerd --pod-infra-container-image=mcr.microsoft.com/oss/kubernetes/pause:3.9 --resolv-conf= --v=4 > kubelet-debug.log 2>&1
