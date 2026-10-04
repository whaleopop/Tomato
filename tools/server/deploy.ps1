# Build the Linux server and put it on the VPS (from the project root):
#   powershell -ExecutionPolicy Bypass -File tools\server\deploy.ps1 -Server 159.194.255.184
# Default: the backend (accounts, profiles, matchmaking - it starts a game server per match).
# -Standalone: one game server without the backend (royaltim.service, -Port).
# -Arch arm64 for ARM machines (Oracle Ampere); -SkipExport uploads the last build again.
param(
	[Parameter(Mandatory = $true)][string]$Server,
	[string]$Key = "",
	[string]$User = "root",
	[ValidateSet("x86_64", "arm64")][string]$Arch = "x86_64",
	[switch]$Standalone,
	[int]$Port = 7777,
	[switch]$SkipExport
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$build = Join-Path $root "build\Server\royaltim_server.$Arch"
$backend = Join-Path $PSScriptRoot "backend"

if (-not $SkipExport) {
	New-Item -ItemType Directory -Force (Split-Path $build) | Out-Null
	# Godot is a GUI program: without -Wait PowerShell would not wait for it
	Start-Process $godot -ArgumentList "--headless", "--path", "`"$root`"", "-s", "tools/server/export_catalog.gd" -Wait -NoNewWindow
	Remove-Item $build -ErrorAction SilentlyContinue
	Start-Process $godot -ArgumentList "--headless", "--path", "`"$root`"", "--export-release", "`"Linux Server ($Arch)`"", "`"$build`"" -Wait -NoNewWindow
	if (-not (Test-Path $build)) { throw "Export failed: $build is missing" }
}

$sshArgs = @()
if ($Key -ne "") { $sshArgs += @("-i", $Key) }
$target = "$User@$Server"
$sudo = if ($User -eq "root") { "" } else { "sudo " }
& ssh @sshArgs $target "rm -rf ~/royaltim-upload && mkdir -p ~/royaltim-upload"
if ($Standalone) {
	& scp @sshArgs $build "$PSScriptRoot\install.sh" "$PSScriptRoot\royaltim.service" "${target}:~/royaltim-upload/"
	if ($LASTEXITCODE -ne 0) { throw "scp failed" }
	& ssh @sshArgs $target "cd ~/royaltim-upload && chmod +x install.sh && ${sudo}./install.sh $Port"
} else {
	& scp @sshArgs $build "$backend\royaltim_backend.py" "$backend\catalog.json" "$PSScriptRoot\install_backend.sh" "$PSScriptRoot\royaltim-backend.service" "${target}:~/royaltim-upload/"
	if ($LASTEXITCODE -ne 0) { throw "scp failed" }
	& ssh @sshArgs $target "cd ~/royaltim-upload && chmod +x install_backend.sh && ${sudo}./install_backend.sh"
}
