$crictlVersion = "v1.28.0"
$url = "https://github.com/kubernetes-sigs/cri-tools/releases/download/$crictlVersion/crictl-$crictlVersion-windows-amd64.tar.gz"
$dest = "$env:TEMP\crictl.tar.gz"
$bin = "C:\Program Files\containerd\bin"

Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
tar -xzf $dest -C $bin
Remove-Item $dest

$env:Path = "$env:Path;$bin"
[Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")

# Configure crictl
$config = @"
runtime-endpoint: npipe:////./pipe/containerd-containerd
image-endpoint: npipe:////./pipe/containerd-containerd
timeout: 10
debug: false
pull-image-on-create: false
disable-pull-on-run: false
"@
Set-Content -Path "$bin\crictl.yaml" -Value $config
