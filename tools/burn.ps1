# burn.ps1 -- one-shot programmer for Anlogic PH1P35 (HX1P35A board)
#
# Usage:
#   .\tools\burn.ps1 -Bit "td_project\camera_to_dsi_display.bit"
#   .\tools\burn.ps1 -Bit "docs\artifacts\bitstreams\vibon_mode2.bit" -Spd 7 -Cable 0
#
# Why it is written this way (see the "burn method" markdown under docs/):
#   1. the bit must be copied to a pure-ASCII path and referenced with forward slashes
#      (TD's Tcl eats Chinese paths and treats backslashes as escapes)
#   2. connect_cable MUST carry -host_name 127.0.0.1:5555 -usr_args "-f 12 -i 0"
#      (let the local hwserver open the USB device; plain -open fails usb_open())
#   3. the tcl file must be passed as an argument, never through a stdin pipe
#   4. always kill a leftover hwserver first (it owns port 5555 and the cable)
#
# Exit code: 0 = success (PRG-2014 seen), 1 = failure
#
# NOTE: ASCII only on purpose -- Windows PowerShell 5.1 reads .ps1 as ANSI and
#       Chinese comments can corrupt parsing.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Bit,
    [int]$Spd = 7,
    [int]$Cable = 0,
    [string]$TdExe = 'F:\Anlogic\bin\td_commands_prompt.exe'
)

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host $m }

# ---------- 0. sanity ----------
if (-not (Test-Path $TdExe)) { throw "TD not found: $TdExe" }
if (-not (Test-Path $Bit))   { throw "bit file not found: $Bit" }
$bitAbs = (Resolve-Path $Bit).Path
Say ("[1/5] bit = {0}  ({1:N2} MB)" -f $bitAbs, ((Get-Item $bitAbs).Length / 1MB))

# ---------- 1. copy bit to an ASCII path ----------
$tmpDir = $env:TEMP
$bitTmp = Join-Path $tmpDir 'anlogic_burn.bit'
$tclTmp = Join-Path $tmpDir 'anlogic_burn.tcl'
Copy-Item $bitAbs $bitTmp -Force
$bitFwd = $bitTmp -replace '\\', '/'
$tclFwd = $tclTmp -replace '\\', '/'
Say "[2/5] staged -> $bitFwd"

# ---------- 2. kill stale hwserver ----------
$stale = @(Get-Process hwserver -ErrorAction SilentlyContinue)
if ($stale.Count -gt 0) {
    $stale | Stop-Process -Force
    Start-Sleep -Milliseconds 600
    Say ("[3/5] killed {0} stale hwserver" -f $stale.Count)
} else {
    Say "[3/5] no stale hwserver"
}

# ---------- 3. generate the tcl script ----------
$lines = @(
    'connect_cable -host_name 127.0.0.1:5555 -usr_args "-f 12 -i 0" -open -auto_start',
    'connect_cable -current',
    ('download -bit {0} -mode jtag -spd {1} -cable {2}' -f $bitFwd, $Spd, $Cable),
    'connect_cable -close',
    'exit'
)
$lines | Out-File -Encoding ascii $tclTmp
Say "[4/5] tcl -> $tclTmp"

# ---------- 4. run TD with the script as an argument ----------
$outLog = Join-Path $tmpDir 'anlogic_burn.log'
$errLog = Join-Path $tmpDir 'anlogic_burn.err'
$p = Start-Process -FilePath $TdExe -ArgumentList ('"' + $tclFwd + '"') `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
    -NoNewWindow -PassThru
$null = $p.WaitForExit(180000)

$out = ''
if (Test-Path $outLog) { $out = Get-Content $outLog -Raw }

Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force

# ---------- 5. verdict ----------
Say "[5/5] result:"
($out -split "`r?`n" | Where-Object { $_ -match 'PRG-|RUN-1003|host:|USB device' }) |
    ForEach-Object { Say ("      " + $_) }

if ($out -match 'PRG-2014\s*:\s*Chip validation success') {
    Say ""
    Say "OK: PRG-2014 Chip validation success"
    exit 0
}

Say ""
Say "FAILED: PRG-2014 not found. See the burn-method markdown under docs/ (section 5)."
Say "  full log: $outLog"
exit 1
