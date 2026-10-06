# Records the trailer reels with Godot's Movie Maker and converts them to MP4 (H.264).
#   powershell -ExecutionPolicy Bypass -File dev\trailers\record_all.ps1 [-Reels heroes,zone] [-Width 1920 -Height 1080 -Fps 60]
# Output: trailers\<reel>.mp4 (the folder is git-ignored). Needs ffmpeg: imageio-ffmpeg in the AI venv
# (D:\royaltim-ai\venv) or ffmpeg on PATH.
param(
    [string[]]$Reels = @("heroes", "weapons", "loot", "zone", "events"),
    [int]$Width = 1920, [int]$Height = 1080, [int]$Fps = 60, [int]$Crf = 18
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$out = Join-Path $root "trailers"
New-Item -ItemType Directory -Force $out | Out-Null
if (-not (Test-Path "$out\.gdignore")) { New-Item -ItemType File "$out\.gdignore" | Out-Null }

$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) {
    $ffmpeg = & "D:\royaltim-ai\venv\Scripts\python.exe" -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
}

# Movie Maker records at the project's viewport size and writes MJPEG: both come from this
# temporary override (record.gd scales the 1280x720 UI up to it); the MP4 is compressed afterwards
$override = Join-Path $root "override.cfg"
Set-Content $override "[display]`nwindow/size/viewport_width=$Width`nwindow/size/viewport_height=$Height`nwindow/size/mode=0`n`n[editor]`nmovie_writer/mjpeg_quality=0.95`n"
try {
    foreach ($reel in $Reels) {
        $avi = Join-Path $out "$reel.avi"
        Write-Host "== recording $reel"
        $p = Start-Process -FilePath $godot -ArgumentList @("--path", "$root", "--resolution", "${Width}x${Height}",
            "--write-movie", "`"$avi`"", "--fixed-fps", "$Fps", "-s", "res://dev/trailers/record.gd", "--", $reel, "--size=${Width}x${Height}") `
            -NoNewWindow -PassThru -Wait -RedirectStandardOutput (Join-Path $out "$reel.log") -RedirectStandardError (Join-Path $out "$reel.err.log")
        if (-not (Test-Path $avi)) { Write-Host "   no video written, see $reel.err.log"; continue }
        & $ffmpeg -y -loglevel error -i "$avi" -an -vf "scale=in_range=pc:out_range=tv,format=yuv420p" -c:v libx264 -preset slow -crf $Crf -color_range tv -movflags +faststart (Join-Path $out "$reel.mp4")
        Remove-Item $avi
        Write-Host "   -> trailers\$reel.mp4"
    }
} finally {
    Remove-Item $override -ErrorAction SilentlyContinue
}
