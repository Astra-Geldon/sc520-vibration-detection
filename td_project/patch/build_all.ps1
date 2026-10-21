# build_all.ps1 -- 一条命令跑完 Anlogic TD 的三段式构建（含加密核数据库补丁）
#
# 为什么是三段：
#   HDMI 发射核是 IEEE-1735 加密核，内部「计数器 sel 用 valid_2d、像素数据在第 3 拍」
#   的错拍只能改**逻辑数据库**，不能改 RTL。三段必须在**独立进程**里跑：
#     A  综合到 optimize_rtl -> export_db baseline_rtl.db
#     B  import_db -> 改 12 个 mux6_syn_[2345].sel 的连接 -> export_db patched_rtl.db
#     C  import_db patched_rtl.db -> optimize_gate/place/route/bitgen
#   任何 RTL 改动（哪怕改一个 parameter）都必须重跑 A->B->C，否则补丁会丢。
#
# 用法：
#   cd <repo root>
#   .\td_project\patch\build_all.ps1
#   .\td_project\patch\build_all.ps1 -SkipA        # 只改了 C 阶段能接受的东西时（一般别用）
#
# 退出码：0 = 三段全过；非 0 = 某一段失败（日志在 td_project\pA.log / pB.log / pC.log）
# 注意：ASCII only —— Windows PowerShell 5.1 按 ANSI 读 .ps1。

[CmdletBinding()]
param(
    [string]$TdExe = 'F:\Anlogic\bin\td_commands_prompt.exe',
    [switch]$SkipA,
    [switch]$SkipB
)

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

$proj = Join-Path $PSScriptRoot '..\..'
$proj = (Resolve-Path $proj).Path
$td   = Join-Path $proj 'td_project'
if (-not (Test-Path $td)) { throw "td_project not found under $proj" }

Push-Location $td
try {
    $phases = @()
    if (-not $SkipA) { $phases += @{ tcl = 'patch/phaseA_export_rtl.tcl';         log = 'pA.log'; mark = 'PHASE_A_DONE' } }
    if (-not $SkipB) { $phases += @{ tcl = 'patch/phaseB_patch_db.tcl';           log = 'pB.log'; mark = 'PATCH_FINISHED' } }
    $phases += @{ tcl = 'patch/phaseC_build_from_patched.tcl'; log = 'pC.log'; mark = 'PHASE_C_DONE' }

    foreach ($ph in $phases) {
        Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force
        # B/C 依赖前一段导出的数据库，缺了就别傻跑
        if ($ph.log -eq 'pB.log' -and -not (Test-Path 'baseline_rtl.db')) { throw "baseline_rtl.db missing - run phase A first" }
        if ($ph.log -eq 'pC.log' -and -not (Test-Path 'patched_rtl.db')) { throw "patched_rtl.db missing - run phase B first" }

        Say ("[build] ---- {0} ----" -f $ph.tcl)
        ('source ' + $ph.tcl) | Out-File -Encoding ascii 'stdin_tmp.txt'
        $p = Start-Process -FilePath $TdExe -RedirectStandardInput 'stdin_tmp.txt' `
             -RedirectStandardOutput $ph.log -RedirectStandardError 'tmp.err' -NoNewWindow -PassThru
        $null = $p.WaitForExit(1800000)

        $txt = ''
        if (Test-Path $ph.log) { $txt = Get-Content $ph.log -Raw }
        if ($txt -notmatch [regex]::Escape($ph.mark)) {
            Say ("[build] FAILED at {0} (see td_project\{1})" -f $ph.tcl, $ph.log)
            ($txt -split "`r?`n" | Select-Object -Last 12) | ForEach-Object { Say ("    " + $_) }
            exit 1
        }
        Say ("[build] ok: {0}" -f $ph.mark)
    }

    $ts = 'camera_to_dsi_display_phy.ts'
    if (Test-Path $ts) { Say ("[build] timing: " + ((Get-Content $ts) -join ' ')) }
    $bit = 'camera_to_dsi_display.bit'
    if (Test-Path $bit) {
        $f = Get-Item $bit
        Say ("[build] bit: {0}  {1:N0} bytes  {2}" -f $f.Name, $f.Length, $f.LastWriteTime)
    }
    # 校验补丁真的在
    if (Test-Path 'pB.log') {
        (Get-Content 'pB.log' | Select-String -Pattern 'BEFORE:|AFTER :|VERIFIED' | ForEach-Object { Say ("[build] patch " + $_.Line.Trim()) })
    }
    exit 0
}
finally { Pop-Location }
