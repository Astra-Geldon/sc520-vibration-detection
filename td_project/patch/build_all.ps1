# Full A -> B -> C TD build, including the encrypted HDMI core DB repair.
# ASCII only for Windows PowerShell 5.1. This script does not program the board.
[CmdletBinding()]
param(
    [string]$TdExe = '',
    [ValidateRange(1, 86400)][int]$PhaseTimeoutSeconds = 1800,
    [switch]$SkipA,
    [switch]$SkipB
)

$ErrorActionPreference = 'Stop'
$failed = $false
$priorTdArch = [Environment]::GetEnvironmentVariable('SC520_TD_ARCH', 'Process')
$pushed = $false

try {
    if ([string]::IsNullOrWhiteSpace($TdExe)) {
        $candidates = @(
            $env:SC520_TD_EXE,
            'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe',
            'F:\Anlogic\bin\td_commands_prompt.exe'
        )
        $foundCommand = Get-Command td_commands_prompt.exe -ErrorAction SilentlyContinue
        if ($foundCommand) { $candidates += $foundCommand.Source }
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $TdExe = $candidate
                break
            }
        }
    }
    if (-not $TdExe -or -not (Test-Path -LiteralPath $TdExe -PathType Leaf)) {
        throw 'TD executable not found. Supply -TdExe <installation>\bin\td_commands_prompt.exe.'
    }
    $TdExe = (Resolve-Path -LiteralPath $TdExe).Path
    $tdInstall = Split-Path -Parent (Split-Path -Parent $TdExe)
    $env:SC520_TD_ARCH = Join-Path $tdInstall 'arch'
    if (-not (Test-Path -LiteralPath (Join-Path $env:SC520_TD_ARCH 'ph1_35p.db') -PathType Leaf)) {
        throw "Device database missing under $env:SC520_TD_ARCH"
    }

    $proj = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $td = Join-Path $proj 'td_project'
    if (-not (Test-Path -LiteralPath (Join-Path $td 'camera_to_dsi_display.al'))) {
        throw "Project file not found under $td"
    }
    Push-Location -LiteralPath $td
    $pushed = $true
    $archive = Join-Path $td ('build_history\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    New-Item -ItemType Directory -Path $archive -Force | Out-Null
    Write-Host "[build] TD: $TdExe"
    Write-Host "[build] previous outputs: $archive"
    if ($SkipA -or $SkipB) {
        Write-Warning 'Skipped phases reuse existing databases. Any RTL change requires the default full A -> B -> C build.'
    }

    $phases = @()
    if (-not $SkipA) {
        $phases += @{
            tcl='patch/phaseA_export_rtl.tcl'; log='pA.log';
            required=@('PHASE_A_DONE ERR=0'); input=$null;
            outputs=@('baseline_rtl.db')
        }
    }
    if (-not $SkipB) {
        $phases += @{
            tcl='patch/phaseB_patch_db.tcl'; log='pB.log';
            required=@('PATCH_FINISHED','VERIFIED_COUNTER_SELECTORS12'); input='baseline_rtl.db';
            outputs=@('patched_rtl.db')
        }
    }
    $phases += @{
        tcl='patch/phaseC_build_from_patched.tcl'; log='pC.log';
        required=@('PHASE_C_DONE ERR=0','CHECK valid_2d=2 valid_3d=14'); input='patched_rtl.db';
        outputs=@('camera_to_dsi_display.bit','camera_to_dsi_display_phy.ts',
                  'patched_final_timing.rpt','camera_to_dsi_display_phy.area',
                  'camera_to_dsi_display_gate.area')
    }

    foreach ($phase in $phases) {
        if ($phase.input -and -not (Test-Path -LiteralPath $phase.input -PathType Leaf)) {
            throw "Missing $($phase.input); run the full A -> B -> C build."
        }
        # Archive old outputs before starting, so stale files can never pass validation.
        $phaseError = $phase.log + '.err'
        foreach ($name in @($phase.log, $phaseError) + $phase.outputs) {
            if (Test-Path -LiteralPath $name -PathType Leaf) {
                Move-Item -LiteralPath $name -Destination (Join-Path $archive $name)
            }
        }
        Write-Host "[build] ---- $($phase.tcl) ----"
        ('source ' + $phase.tcl) | Out-File -Encoding ascii -LiteralPath 'stdin_tmp.txt'
        $startedUtc = [DateTime]::UtcNow
        $process = Start-Process -FilePath $TdExe -WorkingDirectory $td -WindowStyle Hidden `
            -RedirectStandardInput 'stdin_tmp.txt' -RedirectStandardOutput $phase.log `
            -RedirectStandardError $phaseError -PassThru
        # Cache the native handle before waiting (PowerShell 5.1 exit-code behavior).
        $processHandle = $process.Handle
        if (-not $process.WaitForExit($PhaseTimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "Timeout after $PhaseTimeoutSeconds seconds in $($phase.tcl)."
        }
        [void]$process.WaitForExit()
        $process.Refresh()
        if ($process.ExitCode -ne 0) {
            throw "TD exited with code $($process.ExitCode) in $($phase.tcl). See $($phase.log) and $phaseError."
        }
        $logText = Get-Content -LiteralPath $phase.log -Raw
        if ($logText -match '########## FAIL:|PATCH_ERROR|PHASE_[AC]_DONE ERR=[1-9]') {
            throw "Phase error in $($phase.log)."
        }
        foreach ($marker in $phase.required) {
            if ($logText -notmatch [regex]::Escape($marker)) {
                throw "Missing success marker '$marker' in $($phase.log)."
            }
        }
        foreach ($name in $phase.outputs) {
            if (-not (Test-Path -LiteralPath $name -PathType Leaf)) {
                throw "Phase did not produce $name."
            }
            $outputFile = Get-Item -LiteralPath $name
            if ($outputFile.Length -eq 0 -or $outputFile.LastWriteTimeUtc -lt $startedUtc.AddSeconds(-2)) {
                throw "Empty or stale output: $name"
            }
        }
        Write-Host "[build] ok: $($phase.tcl)"
    }

    Get-Content -LiteralPath 'camera_to_dsi_display_phy.ts' | ForEach-Object { Write-Host "[build] timing: $_" }
    if (Test-Path -LiteralPath 'pB.log') {
        Get-Content -LiteralPath 'pB.log' | Select-String -Pattern 'BEFORE:|AFTER :|VERIFIED' |
            ForEach-Object { Write-Host ('[build] patch ' + $_.Line.Trim()) }
    }
    Get-Item -LiteralPath 'camera_to_dsi_display.bit' | Select-Object Name, Length, LastWriteTime | Format-Table | Out-Host
    $bitStream = [System.IO.File]::OpenRead((Join-Path $td 'camera_to_dsi_display.bit'))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bitHash = [BitConverter]::ToString($sha256.ComputeHash($bitStream)).Replace('-', '')
        Write-Host "[build] BIT_SHA256=$bitHash"
    } finally {
        $bitStream.Dispose()
        $sha256.Dispose()
    }
    Write-Host '[build] A -> B -> C completed. Review setup/hold timing and resources before programming.'
} catch {
    Write-Host ('[build] FAILED: ' + $_.Exception.Message)
    $failed = $true
} finally {
    [Environment]::SetEnvironmentVariable('SC520_TD_ARCH', $priorTdArch, 'Process')
    if ($pushed) { Pop-Location }
}

if ($failed) { exit 1 }
exit 0
