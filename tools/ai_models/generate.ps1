# Thin wrapper: sets cache env vars, activates the venv and forwards all args to generate.py.
# Usage: powershell -ExecutionPolicy Bypass -File tools\ai_models\generate.ps1 --prompt "cute broccoli warrior"
if (-not $env:ROYALTIM_AI_ROOT) { $env:ROYALTIM_AI_ROOT = "D:\royaltim-ai" }
$root = $env:ROYALTIM_AI_ROOT
$env:HF_HOME = Join-Path $root "hf_cache"
$env:PIP_CACHE_DIR = Join-Path $root "pip_cache"
$env:TORCH_HOME = Join-Path $root "torch_cache"
$env:U2NET_HOME = Join-Path $root "u2net"
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"
$env:PYTHONIOENCODING = "utf-8"
$activate = Join-Path $root "venv\Scripts\Activate.ps1"
if (-not (Test-Path $activate)) {
    Write-Output "ERROR: venv not found in $root\venv - run tools\ai_models\setup.ps1 first"
    exit 2
}
. $activate
& python (Join-Path $PSScriptRoot "generate.py") @args
exit $LASTEXITCODE
