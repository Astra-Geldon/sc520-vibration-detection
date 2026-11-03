# Program a verified bit; all generated files stay below the supplied build root.
# ASCII source is intentional for Windows PowerShell 5.1.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Bit,
    [string]$TdExe = 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe',
    [string]$ExpectedSha256 = '5F8C6B9BC429B6BADEEBC0CB93C41BBCE051CF8276BB31E3C3C2FA7E1956AAA0',
    [string]$OutputRoot = 'D:\FPGA\codex_zyj\_build\Final_Project\manual-programming',
    [int]$Spd = 7,
    [int]$Cable = 0
)
$ErrorActionPreference = 'Stop'
$staleHwservers = Get-Process -Name hwserver -ErrorAction SilentlyContinue
if ($staleHwservers) {
    $staleHwservers | Stop-Process -Force
    Start-Sleep -Milliseconds 200
}
$bitPath = (Resolve-Path -LiteralPath $Bit).Path
$tdPath = (Resolve-Path -LiteralPath $TdExe).Path
$hash = (Get-FileHash -LiteralPath $bitPath -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $ExpectedSha256 -or $hash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw 'Bit SHA256 does not match. Supply the verified hash of your intended build.'
}
$runDir = Join-Path $OutputRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $runDir -Force)
$runDir = (Resolve-Path -LiteralPath $runDir).Path
$stagedBit = Join-Path $runDir 'image.bit'
Copy-Item -LiteralPath $bitPath -Destination $stagedBit
$bitFwd = $stagedBit.Replace('\', '/')
if ($bitFwd -match '[{}\r\n]' -or $bitFwd -match '[^\x00-\x7F]') {
    throw 'OutputRoot must give an ASCII path without braces or line breaks for TD.'
}
$tcl = Join-Path $runDir 'program.tcl'
$stdout = Join-Path $runDir 'program.log'
$stderr = Join-Path $runDir 'program.err'
@(
    'connect_cable -host_name 127.0.0.1:5555 -usr_args "-f 12 -i 0" -open -auto_start',
    'connect_cable -current',
    ('download -bit {{{0}}} -mode jtag -spd {1} -cable {2}' -f $bitFwd, $Spd, $Cable),
    'connect_cable -close',
    'exit'
) | Set-Content -LiteralPath $tcl -Encoding ascii
$started = [DateTime]::UtcNow
$process = Start-Process -FilePath $tdPath -ArgumentList ('"' + $tcl.Replace('\', '/') + '"') -WorkingDirectory $runDir -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$nativeHandle = $process.Handle
if (-not $process.WaitForExit(180000)) {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    throw "TD programming timed out. Logs: $runDir"
}
$process.WaitForExit()
$process.Refresh()
$text = Get-Content -LiteralPath $stdout -Raw
$success = $process.ExitCode -eq 0 -and
    $text -match 'PRG-2014\s*:\s*Chip validation success:\s*PH1P35MDG324' -and
    $text -match 'RUN-1003\s*:\s*finish command "download -bit'
[ordered]@{
    success = [bool]$success
    bit = $bitPath
    sha256 = $hash
    started_utc = $started.ToString('o')
    finished_utc = [DateTime]::UtcNow.ToString('o')
    exit_code = $process.ExitCode
    method = 'JTAG SRAM; no Flash write or MCU firmware load'
    log_directory = $runDir
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'programming.json') -Encoding utf8
Write-Host "Bit SHA256: $hash"
Write-Host "Logs: $runDir"
if (-not $success) { throw 'Device validation and completed download were not both confirmed.' }
Write-Host 'SUCCESS: PH1P35MDG324 validated and bit download completed.'
