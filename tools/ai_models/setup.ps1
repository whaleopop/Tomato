<#
.SYNOPSIS
  Idempotent installer for the local text/image -> 3D (GLB) pipeline of ROYALTIM-3.

.DESCRIPTION
  Creates a Python 3.11 venv under -Root, installs CUDA PyTorch + dependencies
  (only prebuilt wheels, no compiler needed), clones TripoSR at a pinned commit,
  applies the PyMCubes patch and pre-downloads all model weights.
  Safe to re-run: finished steps are detected and skipped.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ai_models\setup.ps1
  powershell -ExecutionPolicy Bypass -File tools\ai_models\setup.ps1 -Root E:\ai -SkipText2Image
#>
[CmdletBinding()]
param(
    [string]$Root = "D:\royaltim-ai",
    [string]$TorchVersion = "2.8.0",
    [string]$CudaTag = "cu126",     # cu126 works with any NVIDIA driver >= 560 (this PC: 591.74)
    [switch]$CpuTorch,              # install CPU-only torch (no NVIDIA GPU)
    [switch]$SkipText2Image,        # do not download the text->image model (~4.3 GB), only --image mode
    [switch]$SkipModels             # do not pre-download any weights
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TripoSRUrl = "https://github.com/VAST-AI-Research/TripoSR.git"
$TripoSRCommit = "107cefdc244c39106fa830359024f6a2f1c78871"
$TotalSteps = 7
$started = Get-Date

function Step([int]$n, [string]$msg) { Write-Host ""; Write-Host "[$n/$TotalSteps] $msg" -ForegroundColor Cyan }
function Ok([string]$msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Info([string]$msg) { Write-Host "    $msg" }

# Runs a native command; stderr output (pip/git warnings) must not abort the script,
# only a non-zero exit code does.
function Invoke-Native([string]$Exe, [string[]]$CmdArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $Exe @CmdArgs 2>&1 | ForEach-Object { Write-Host "    $_" } }
    finally { $ErrorActionPreference = $old }
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Exe $($CmdArgs -join ' ')" }
}

# Returns $true if the python snippet exits with code 0.
function Test-Py([string]$Py, [string]$Code) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $Py -c $Code 2>&1 | Out-Null } finally { $ErrorActionPreference = $old }
    return ($LASTEXITCODE -eq 0)
}

Write-Host "ROYALTIM-3 AI model pipeline setup" -ForegroundColor Yellow
Write-Host "Install root: $Root"

# All heavy files and caches go under $Root (never C:\Users\...\.cache).
$env:ROYALTIM_AI_ROOT = $Root
$env:HF_HOME = Join-Path $Root "hf_cache"
$env:PIP_CACHE_DIR = Join-Path $Root "pip_cache"
$env:TORCH_HOME = Join-Path $Root "torch_cache"
$env:U2NET_HOME = Join-Path $Root "u2net"
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"
$env:PYTHONUTF8 = "1"
$env:PIP_DISABLE_PIP_VERSION_CHECK = "1"

# ---------------------------------------------------------------------------
Step 1 "Checking prerequisites"
$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
if (-not $pyLauncher) { throw "Python launcher 'py' not found. Install Python 3.11 from python.org." }
$old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$pyVer = & py -3.11 -c "import sys; print(sys.version.split()[0])" 2>&1
$pyOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $old
if (-not $pyOk) { throw "Python 3.11 not found ('py -3.11'). Install Python 3.11 (64-bit) from python.org." }
Ok "Python $pyVer"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found in PATH." }
Ok "git found"
foreach ($d in @($Root, $env:HF_HOME, $env:PIP_CACHE_DIR, $env:TORCH_HOME, $env:U2NET_HOME, (Join-Path $Root "logs"))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
$drive = (Get-Item $Root).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
Info "Free space on $($drive.Name): $freeGB GB (full install needs ~12 GB)"
if ($freeGB -lt 12) { Write-Warning "Less than 12 GB free on $($drive.Name): - the install may run out of space." }

# ---------------------------------------------------------------------------
Step 2 "Python venv"
$venv = Join-Path $Root "venv"
$py = Join-Path $venv "Scripts\python.exe"
if (Test-Path $py) {
    Ok "venv exists: $venv"
} else {
    Info "Creating venv with Python 3.11 at $venv ..."
    Invoke-Native "py" @("-3.11", "-m", "venv", $venv)
    Ok "venv created"
}
Invoke-Native $py @("-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel", "-q")
Ok "pip upgraded"

# ---------------------------------------------------------------------------
if ($CpuTorch) { $tag = "cpu" } else { $tag = $CudaTag }
$wantTorch = "$TorchVersion+$tag"
Step 3 "PyTorch $wantTorch"
if (Test-Py $py "import torch, sys; sys.exit(0 if torch.__version__ == '$wantTorch' else 1)") {
    Ok "torch $wantTorch already installed"
} else {
    Info "Downloading torch $wantTorch (~2.5 GB for CUDA builds, this takes a while) ..."
    Invoke-Native $py @("-m", "pip", "install", "torch==$TorchVersion", "--index-url", "https://download.pytorch.org/whl/$tag", "--progress-bar", "off")
    Ok "torch installed"
}

# ---------------------------------------------------------------------------
Step 4 "Python dependencies (requirements.txt)"
$req = Join-Path $ScriptDir "requirements.txt"
Invoke-Native $py @("-m", "pip", "install", "-r", $req, "--progress-bar", "off")
# guard: nothing may have replaced the CUDA torch with a CPU build from PyPI
if (-not (Test-Py $py "import torch, sys; sys.exit(0 if torch.__version__ == '$wantTorch' else 1)")) {
    Info "torch was changed by a dependency, reinstalling $wantTorch ..."
    Invoke-Native $py @("-m", "pip", "install", "--force-reinstall", "--no-deps", "torch==$TorchVersion", "--index-url", "https://download.pytorch.org/whl/$tag", "--progress-bar", "off")
}
Ok "dependencies installed"

# ---------------------------------------------------------------------------
Step 5 "TripoSR source (pinned commit $($TripoSRCommit.Substring(0, 8)))"
$repo = Join-Path $Root "TripoSR"
if (-not (Test-Path (Join-Path $repo ".git"))) {
    if (Test-Path $repo) { Remove-Item -Recurse -Force $repo }
    Invoke-Native "git" @("clone", "--quiet", $TripoSRUrl, $repo)
}
$old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$head = (& git -C $repo rev-parse HEAD 2>&1 | Out-String).Trim()
$ErrorActionPreference = $old
if ($head -ne $TripoSRCommit) {
    Info "Checking out $TripoSRCommit (was $head) ..."
    Invoke-Native "git" @("-C", $repo, "fetch", "--quiet", "origin")
    Invoke-Native "git" @("-C", $repo, "checkout", "--quiet", "-f", $TripoSRCommit)
}
Ok "TripoSR at $repo"
# Patch: torchmcubes (needs C++/CUDA compiler) -> PyMCubes. Re-applied on every run.
$patchSrc = Join-Path $ScriptDir "triposr_patch\isosurface.py"
$patchDst = Join-Path $repo "tsr\models\isosurface.py"
Copy-Item -Force $patchSrc $patchDst
Ok "patched tsr/models/isosurface.py (torchmcubes -> PyMCubes)"

# ---------------------------------------------------------------------------
Step 6 "Model weights"
$gen = Join-Path $ScriptDir "generate.py"
if ($SkipModels) {
    Info "skipped (-SkipModels); weights will download on first generation"
} else {
    $dlArgs = @($gen, "--download-models")
    if ($SkipText2Image) { $dlArgs += "--no-text2img" }
    Info "Downloading TripoSR (~1.7 GB), rembg u2net (~170 MB)$(if (-not $SkipText2Image) { ' and LCM Dreamshaper v7 (~4.3 GB)' }) ..."
    Invoke-Native $py $dlArgs
    Ok "weights cached in $($env:HF_HOME) and $($env:U2NET_HOME)"
}

# ---------------------------------------------------------------------------
Step 7 "Self-check"
Invoke-Native $py @($gen, "--self-check")

$mins = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
Write-Host ""
Write-Host "Setup finished in $mins min." -ForegroundColor Green
Write-Host "Try:  tools\ai_models\generate.bat --prompt `"cute cartoon tomato warrior character`" --name tomato_hero"
