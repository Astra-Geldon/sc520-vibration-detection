# build_all.ps1 -- run the full 3-phase Anlogic TD build (incl. the encrypted-core DB patch)
#
# Why three phases:
#   The HDMI transmitter core is IEEE-1735 encrypted, so the "counter uses valid_2d
#   while pixel data is at stage 3" bug can only be fixed in the LOGIC DATABASE,
#   not in RTL. The phases must run in SEPARATE processes:
#     A  synthesize to optimize_rtl -> export_db baseline_rtl.db
#     B  import_db -> reconnect 12 x mux6_syn_[2345].sel from valid_2d to valid_3d
#        -> export_db patched_rtl.db
#     C  import_db patched_rtl.db -> optimize_gate / place / route / bitgen
#   Any RTL change (even one parameter) must re-run A->B->C, otherwise the patch
#   is lost and the capture card goes black again.
#
# Usage:
#   cd <repo root>
#   .\td_project\patch\build_all.ps1
#   .\td_project\patch\build_all.ps1 -SkipA     (normally do NOT use)
#
# Exit code: 0 = all phases passed, 1 = a phase failed
#   logs: td_project\pA.log / pB.log / pC.log
#
# ASCII only on purpose (PowerShell parses .ps1 with the ANSI code page on 5.1,
# and non-ASCII bytes have broken parsing here before).

[CmdletBinding()]
param(
    [string]$TdExe = 'F:\Anlogic\bin\td_commands_prompt.exe',
    [switch]$SkipA,
    [switch]$SkipB
)

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

$proj = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$td = Join-Path $proj 'td_project'
if (-not (Test-Path $td)) { throw "td_project not found under $proj" }

Push-Location $td

$phases = @()
if (-not $SkipA) { $phases += @{ tcl = 'patch/phaseA_export_rtl.tcl'; log = 'pA.log'; mark = 'PHASE_A_DONE' } }
if (-not $SkipB) { $phases += @{ tcl = 'patch/phaseB_patch_db.tcl'; log = 'pB.log'; mark = 'PATCH_FINISHED' } }
$phases += @{ tcl = 'patch/phaseC_build_from_patched.tcl'; log = 'pC.log'; mark = 'PHASE_C_DONE' }

$failed = $false

foreach ($ph in $phases) {
    Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force

    if (($ph.log -eq 'pB.log') -and (-not (Test-Path 'baseline_rtl.db'))) {
        Say "[build] FAILED: baseline_rtl.db missing - run phase A first"
        $failed = $true
        break
    }
    if (($ph.log -eq 'pC.log') -and (-not (Test-Path 'patched_rtl.db'))) {
        Say "[build] FAILED: patched_rtl.db missing - run phase B first"
        $failed = $true
        break
    }

    Say ("[build] ---- " + $ph.tcl + " ----")
    ('source ' + $ph.tcl) | Out-File -Encoding ascii 'stdin_tmp.txt'
    $p = Start-Process -FilePath $TdExe -RedirectStandardInput 'stdin_tmp.txt' -RedirectStandardOutput $ph.log -RedirectStandardError 'tmp.err' -NoNewWindow -PassThru
    $null = $p.WaitForExit(1800000)

    $txt = ''
    if (Test-Path $ph.log) { $txt = Get-Content $ph.log -Raw }
    if ($txt -notmatch [regex]::Escape($ph.mark)) {
        Say ("[build] FAILED at " + $ph.tcl + "  (see td_project\" + $ph.log + ")")
        ($txt -split "`r?`n" | Select-Object -Last 12) | ForEach-Object { Say ("    " + $_) }
        $failed = $true
        break
    }
    Say ("[build] ok: " + $ph.mark)
}

if (-not $failed) {
    if (Test-Path 'camera_to_dsi_display_phy.ts') {
        Say ("[build] timing: " + ((Get-Content 'camera_to_dsi_display_phy.ts') -join ' '))
    }
    if (Test-Path 'camera_to_dsi_display.bit') {
        $f = Get-Item 'camera_to_dsi_display.bit'
        Say ("[build] bit: " + $f.Name + "  " + $f.Length + " bytes  " + $f.LastWriteTime)
    }
    if (Test-Path 'pB.log') {
        (Get-Content 'pB.log' | Select-String -Pattern 'BEFORE:|AFTER :|VERIFIED') | ForEach-Object {
            Say ("[build] patch " + $_.Line.Trim())
        }
    }
}

Pop-Location
if ($failed) { exit 1 } else { exit 0 }
