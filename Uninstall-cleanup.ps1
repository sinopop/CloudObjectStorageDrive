# cleanup.ps1 - Cloud Object Storage Drive 完整卸载 / 清理工具
# 同时支持两种场景：
#   1) 旧版方案（oss-mount-windows 时代）的彻底清理：残留 rclone 进程、旧计划任务、旧配置/脚本
#   2) 最新方案的正式卸载命令：停止挂载 → 删除任务 → 删除配置/缓存 → 卸载 rclone/WinFsp
# 用法：
#   双击 Uninstall-cleanup.cmd                      交互式（询问是否卸载 rclone/WinFsp）
#   powershell -File cleanup.ps1 -Full    全自动（不询问，全部卸载，适合脚本调用）
# 说明：GUI 里的「卸载」= 快速卸载（保留配置，方便重连）；本脚本 = 完整卸载（全部清除）。
[CmdletBinding()]
param([switch]$Full)

$ErrorActionPreference = "Continue"

# 自我提升到管理员
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $extra = if ($Full) { " -Full" } else { "" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"$extra"
    exit
}

$taskNames = @("Mount OSS drive (start)", "Mount OSS drive (watchdog)")
$removed = @()

Write-Host "==== Cloud Object Storage Drive 完整卸载/清理 ====" -ForegroundColor Cyan
if ($Full) { Write-Host "模式：全自动（-Full）" } else { Write-Host "模式：交互式" }
Write-Host ""

# 1) 停止挂载（先优雅停止，再强制兜底）
Write-Host "[1/5] 停止挂载..."
$stopScript = Join-Path $env:LOCALAPPDATA "rclone\oss-mount\Stop-OssMount.ps1"
if (Test-Path $stopScript) {
    try { & $stopScript } catch { }
    Start-Sleep -Seconds 2
}
taskkill /IM rclone.exe /F 2>$null | Out-Null
Start-Sleep -Seconds 2

# 2) 删除计划任务（新旧版本同名，一并处理）
Write-Host "[2/5] 删除计划任务..."
foreach ($n in $taskNames) {
    if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) {
        schtasks /delete /tn $n /f 2>$null | Out-Null
        if (-not (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue)) { $removed += "计划任务: $n" }
    }
}

# 3) 删除配置、缓存、运行脚本与 VBS 启动器
Write-Host "[3/5] 删除配置/缓存/运行脚本..."
foreach ($p in @("$env:APPDATA\rclone", "$env:LOCALAPPDATA\rclone", "$env:LOCALAPPDATA\Microsoft\WinGet\Links\rclone.exe")) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        $removed += "配置: $p"
    }
}

# 4) 卸载 rclone / WinFsp（已卸载则自动跳过；卸载 WinFsp 时系统可能短暂停顿）
$doUninstall = $Full
if (-not $Full) {
    $answer = Read-Host "是否同时卸载 rclone 和 WinFsp？(Y/N，推荐 Y 彻底干净；卸载 WinFsp 时系统可能停顿几秒)"
    $doUninstall = $answer -match "^[Yy]"
}
if ($doUninstall) {
    Write-Host "[4/5] 卸载 rclone / WinFsp..."
    winget uninstall --id Rclone.Rclone --exact --silent --accept-source-agreements 2>$null | Out-Null
    winget uninstall --id WinFsp.WinFsp --exact --silent --accept-source-agreements 2>$null | Out-Null
    $removed += "依赖: rclone / WinFsp"
} else {
    Write-Host "[4/5] 跳过卸载 rclone/WinFsp"
}

# 5) 汇总
Write-Host "[5/5] 完成"
Write-Host ""
Write-Host "==== 清理结果 ====" -ForegroundColor Green
if ($removed.Count -eq 0) {
    Write-Host "未发现需要清理的内容（机器可能已经干净）。"
} else {
    $removed | ForEach-Object { Write-Host ("  ✅ {0}" -f $_) }
}
Write-Host ""
Write-Host "请【重启电脑】；如需重新安装，解压最新安装包并双击 CloudObjectStorageDrive.cmd 即可。" -ForegroundColor Yellow
Write-Host "卸载后如仍有问题，请反馈日志：%LOCALAPPDATA%\rclone\oss-cache\rclone-mount.log" -ForegroundColor Yellow

if (-not $Full) {
    Write-Host ""
    Read-Host "按回车键退出"
}
