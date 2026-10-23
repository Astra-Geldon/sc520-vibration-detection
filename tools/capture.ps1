# capture.ps1 -- grab real frames from the HDMI capture card, warm-up aware
#
# USAGE
#   .\tools\capture.ps1                                  # 1 frame, default device
#   .\tools\capture.ps1 -Count 3 -OutDir docs\captures\x
#   .\tools\capture.ps1 -Warmup 150                      # wait longer for lock
#
# WHY THIS SCRIPT EXISTS  (two traps, both verified on this machine)
#   Trap 1 -- device exclusivity
#       OBS / Camera / Teams hold the UVC device. ffmpeg then either errors with
#       "Could not run graph ... already in use", or silently returns black frames.
#   Trap 2 -- the card needs ~3 s to lock AFTER each open  (UGREEN 25854)
#       Measured timeline of one open (30 fps, 1280x720, MJPEG):
#           frames   1..20   pure black       (mean 7,    uniq 1)
#           frames  21..58   "UGREEN" splash  (mean 14,   uniq 2451)
#           frames  59..93   pure black again
#           frames  94..     REAL PICTURE     (mean 110.81, uniq 78 for the colour bars)
#       So `-frames:v 1..3` ALWAYS lands in the black warm-up and looks exactly
#       like "no signal". This script buffered-grabs Warmup frames, finds the
#       first frame with real content, and keeps the LAST $Count such frames.
#
# ASCII only on purpose: PowerShell 5.1 parses .ps1 with the ANSI code page and
# non-ASCII bytes have broken parsing on this machine before.

[CmdletBinding()]
param(
    [string]$Device = 'UGREEN 25854',
    [int]$Count = 1,
    [int]$Warmup = 120,             # frames buffered; the lock happens inside this window
    [int]$Fps = 30,
    [int]$Width = 1280,
    [int]$Height = 720,
    [int]$MinUniq = 20,             # a frame with more colours than this counts as "real"
    [string]$OutDir = 'docs\captures',
    [string]$Ffmpeg = 'ffmpeg',
    [switch]$KeepAll
)

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$stamp = Get-Date -Format 'HHmmss'
$tmp = Join-Path $OutDir ("_warm_" + $stamp)
New-Item -ItemType Directory -Force $tmp | Out-Null
$total = $Warmup + $Count

$args = @(
    '-hide_banner', '-loglevel', 'warning',
    '-f', 'dshow',
    '-vcodec', 'mjpeg',
    '-video_size', ("{0}x{1}" -f $Width, $Height),
    '-framerate', "$Fps",
    '-rtbufsize', '300M',
    '-i', ("video={0}" -f $Device),
    '-frames:v', "$total",
    '-y', (Join-Path $tmp 'w_%04d.png')
)

Say ("[capture] device='{0}'  {1}x{2}@{3}fps  buffering {4} frames (~{5:N1}s)" -f $Device, $Width, $Height, $Fps, $total, ($total / $Fps))
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$log = & $Ffmpeg @args 2>&1 | Out-String
$ErrorActionPreference = $prevEap

if ($log -match 'already in use|I/O error|Could not run graph|Error opening') {
    Say "[capture] FAILED: device busy or unopenable"
    Say "          close OBS / other capture apps and retry"
    Say $log.Trim()
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 2
}

$frames = Get-ChildItem $tmp -Filter 'w_*.png' | Sort-Object Name
if (-not $frames) {
    Say "[capture] FAILED: no frames written"
    if ($log.Trim()) { Say $log.Trim() }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 3
}

# ---- python reports the timeline and which frames are real ----
$env:PYTHONIOENCODING = 'utf-8'
$py = @"
import numpy as np, glob, os, json
from PIL import Image
d = r'$tmp'
fs = sorted(glob.glob(os.path.join(d, 'w_*.png')))
info = []
for f in fs:
    a = np.asarray(Image.open(f).convert('RGB')).astype(np.int32)
    info.append((os.path.basename(f), float(a.mean()), int(len(np.unique(a.reshape(-1,3),axis=0)))))
good = [i for i, (_, _, u) in enumerate(info) if u >= $MinUniq]
prev = None
for i, (n, m, u) in enumerate(info):
    sig = (round(m, 1), u)
    if sig != prev or i == 0:
        print('  %-10s mean=%7.2f uniq=%5d %s' % (n, m, u, 'REAL' if u >= $MinUniq else 'blank'))
        prev = sig
res = {'total': len(info), 'good_idx': good, 'names': [n for n, _, _ in info],
       'first_good': (good[0] if good else -1), 'n_good': len(good)}
open(os.path.join(d, 'timeline.json'), 'w').write(json.dumps(res))
print('TIMELINE ' + json.dumps(res))
"@
$pyPath = Join-Path $env:TEMP 'capture_timeline.py'
$py | Out-File -Encoding utf8 $pyPath
$tl = & python $pyPath 2>&1
$tl | Where-Object { $_ -notmatch '^TIMELINE' } | ForEach-Object { Say $_ }

$json = $null
$line = $tl | Where-Object { $_ -match '^TIMELINE' } | Select-Object -Last 1
if ($line) { $json = ($line -replace '^TIMELINE\s*', '') | ConvertFrom-Json }

if (-not $json -or $json.n_good -eq 0) {
    Say ("[capture] FAILED: buffered {0} frames, none had content (> {1} colours)" -f $total, $MinUniq)
    Say "          -> no valid TMDS from the board, or the card never locked"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 4
}

# ---- keep the LAST $Count good frames ----
$goodIdx = @($json.good_idx)
$pick = $goodIdx | Select-Object -Last $Count
$names = @($json.names)
$n = 0
foreach ($i in $pick) {
    $n++
    $src = Join-Path $tmp $names[$i]
    $dst = Join-Path $OutDir ("grab_{0}_{1:D2}.png" -f $stamp, $n)
    Copy-Item $src $dst -Force
}
if ($KeepAll) { Say ("[capture] warm-up frames kept in " + $tmp) } else { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Say ("[capture] locked at frame {0}/{1}; kept {2} frame(s) -> {3}" -f ($json.first_good + 1), $json.total, $n, $OutDir)
Get-ChildItem $OutDir -Filter ("grab_{0}_*.png" -f $stamp) | ForEach-Object { Say ("           " + $_.Name) }
