# CloudObjectStorageDrive.Core.ps1
# Shared helpers for the Alibaba Cloud OSS rclone mount solution (Windows).
# Dot-source this file from installers, e.g.:
#     . (Join-Path $PSScriptRoot "CloudObjectStorageDrive.Core.ps1")
#
# Everything that runs on the colleague machine is written from the templates
# below into %LOCALAPPDATA%\rclone\oss-mount\ so it stays self-contained.

# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RcloneExecutable {
    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:ProgramFiles\rclone\rclone.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\rclone.exe",
        "$env:LOCALAPPDATA\Programs\rclone\rclone.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    # Deep search inside winget package folders: the layout varies
    # (e.g. Packages\Rclone.Rclone_*\rclone-v1.75.0-windows-amd64\rclone.exe),
    # and the WinGet Links entry may be missing on some machines.
    $packageDirs = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Rclone.Rclone_*",
        "$env:ProgramFiles\Microsoft\WinGet\Packages\Rclone.Rclone_*"
    )
    foreach ($dir in $packageDirs) {
        $found = Get-ChildItem -Path $dir -Filter "rclone.exe" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Test-WinFspInstalled {
    # Returns $true if WinFsp is present (its FUSE DLL exists).
    # rclone mount fails with "cannot find winfsp" when it is missing.
    $paths = @(
        "${env:ProgramFiles(x86)}\WinFsp\bin\winfsp-x64.dll",
        "$env:ProgramFiles\WinFsp\bin\winfsp-x64.dll",
        "$env:ProgramFiles\WinFsp\bin\winfsp.dll"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

function Get-FirstFreeDriveLetter {
    param([string]$Preferred = "Z")
    $preferred = $Preferred.Trim().TrimEnd(":").ToUpper()
    if ($preferred -match "^[A-Z]$" -and -not (Get-PSDrive -Name $preferred -ErrorAction SilentlyContinue)) {
        return $preferred
    }
    for ($i = 25; $i -ge 3; $i--) {
        $letter = [char](65 + $i)
        if (-not (Get-PSDrive -Name $letter -ErrorAction SilentlyContinue)) { return $letter }
    }
    return $null
}

function Install-OssDependencies {
    # Installs rclone (user scope - no admin needed) and WinFsp (machine scope - needs elevation).
    # The tool itself stays non-elevated; only the WinFsp installer is relaunched elevated (UAC).
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget was not found. Install WinFsp and rclone manually, then re-run."
    }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # 1) rclone - user scope, works without elevation.
        Write-Host "Installing rclone (user scope)..."
        & winget install --id Rclone.Rclone --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null

        # 2) WinFsp - machine scope; relaunch the installer elevated when needed.
        if (Test-IsAdministrator) {
            Write-Host "Installing WinFsp..."
            & winget install --id WinFsp.WinFsp --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        }
        else {
            Write-Host "Installing WinFsp (a system prompt will appear - click Yes)..."
            $script = Join-Path $env:TEMP "cosd-install-winfsp.ps1"
            @'
winget install --id WinFsp.WinFsp --exact --silent --accept-package-agreements --accept-source-agreements
'@ | Set-Content -LiteralPath $script -Encoding UTF8
            $proc = $null
            try {
                $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -Wait -PassThru -ErrorAction Stop
            }
            catch {
                Remove-Item $script -Force -ErrorAction SilentlyContinue
                throw "WinFsp installation was cancelled (the elevation prompt was declined). Click 'Connect & Mount' again and click Yes on the prompt."
            }
            Remove-Item $script -Force -ErrorAction SilentlyContinue
            if ($null -eq $proc -or $proc.ExitCode -ne 0) {
                throw "WinFsp installation did not complete (the elevation prompt may have been declined). Try again or install WinFsp manually."
            }
        }
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Test-OssRemoteAccess {
    # Returns $true if `rclone lsf <remote>` succeeds.
    param(
        [Parameter(Mandatory = $true)][string]$Rclone,
        [Parameter(Mandatory = $true)][string]$Remote
    )
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Rclone lsf $Remote 2>&1 | Out-Null
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    return ($LASTEXITCODE -eq 0)
}

function Initialize-RcloneRemote {
    # Creates (or replaces) an rclone S3 remote for Alibaba OSS / Amazon S3 / other S3-compatible.
    # Returns $true on success.
    param(
        [Parameter(Mandatory = $true)][string]$Rclone,
        [Parameter(Mandatory = $true)][string]$RemoteName,
        [Parameter(Mandatory = $true)][ValidateSet("Alibaba", "AWS", "Other")][string]$Provider,
        [Parameter(Mandatory = $true)][string]$AccessKeyId,
        [Parameter(Mandatory = $true)][string]$AccessKeySecret,
        [string]$Endpoint = "",
        [string]$Region = "",
        [switch]$ForcePathStyle
    )
    # Run rclone without letting stderr lines become terminating errors:
    # PowerShell 5.1 turns native stderr into ErrorRecords when using 2>&1,
    # and callers (e.g. the GUI) run with $ErrorActionPreference = "Stop".
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Remove an existing remote with the same name first (idempotent re-connect).
        & $Rclone config delete $RemoteName 2>&1 | Out-Null

        $args = @(
            "config", "create", $RemoteName, "s3",
            "provider", $Provider,
            "access_key_id", $AccessKeyId,
            "secret_access_key", $AccessKeySecret,
            "acl", "private"
        )
        if ($Endpoint) { $args += @("endpoint", $Endpoint) }
        if ($Region)   { $args += @("region", $Region) }
        if ($ForcePathStyle) { $args += @("force_path_style", "true") }

        & $Rclone @args 2>&1 | Out-Null
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------------------
# Mount settings + installed scripts
# ---------------------------------------------------------------------------

function Write-OssMountSettings {
    # Writes mount-settings.ps1 consumed by Start/Stop/Watchdog.
    # $Mounts: array of hashtables with keys Drive, Remote, Rclone, CacheDir, Endpoint.
    param(
        [Parameter(Mandatory = $true)][object[]]$Mounts,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# OSS mount settings (generated by setup - do not edit)")
    [void]$sb.AppendLine('$Mounts = @(')
    $mountCount = @($Mounts).Count
    $mountIndex = 0
    foreach ($m in $Mounts) {
        $mountIndex++
        $drive = $m.Drive -replace "'", "''"
        $remote = $m.Remote -replace "'", "''"
        $rclone = $m.Rclone -replace "'", "''"
        $cacheDir = $m.CacheDir -replace "'", "''"
        $endpoint = $m.Endpoint -replace "'", "''"
        # PowerShell array literals reject a trailing comma after the last element.
        $comma = if ($mountIndex -lt $mountCount) { "," } else { "" }
        [void]$sb.AppendLine("    @{")
        [void]$sb.AppendLine("        Drive = '$drive'")
        [void]$sb.AppendLine("        Remote = '$remote'")
        [void]$sb.AppendLine("        Rclone = '$rclone'")
        [void]$sb.AppendLine("        CacheDir = '$cacheDir'")
        [void]$sb.AppendLine("        Endpoint = '$endpoint'")
        [void]$sb.AppendLine("    }$comma")
    }
    [void]$sb.AppendLine(')')

    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
}

# Canonical rclone mount flags. Freshness is controlled by --dir-cache-time
# (s3/OSS does not support --poll-interval). --no-modtime is intentionally
# removed so file modification times are correct.
$StartMountTemplate = @'
# Start-OssMount.ps1 - mounts every drive defined in mount-settings.ps1 (idempotent).
$ErrorActionPreference = "Stop"
$settingsPath = Join-Path $PSScriptRoot "mount-settings.ps1"
if (-not (Test-Path $settingsPath)) { Write-Error "mount-settings.ps1 not found"; exit 1 }
. $settingsPath

function ConvertTo-ArgumentString {
    param([string[]]$Values)
    return (($Values | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
    }) -join " ")
}

$started = @()
foreach ($m in $Mounts) {
    if (-not $m.Drive) { continue }
    if (Get-PSDrive -Name $m.Drive -ErrorAction SilentlyContinue) { continue }
    # Skip if this remote is already mounted on another drive letter (same bucket twice fails).
    $sameRemote = Get-CimInstance Win32_Process -Filter "Name='rclone.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape([string]$m.Remote) } |
        Select-Object -First 1
    if ($sameRemote) { continue }
    New-Item -ItemType Directory -Force -Path $m.CacheDir | Out-Null
    $logFile = Join-Path $m.CacheDir "rclone-mount.log"
    $args = @("mount", $m.Remote, "$($m.Drive):",
        "--network-mode", "--vfs-cache-mode", "full",
        "--dir-cache-time", "30s", "--vfs-cache-max-size", "20G",
        "--cache-dir", $m.CacheDir, "--log-file", $logFile, "--log-level", "INFO")
    $process = Start-Process -FilePath $m.Rclone -ArgumentList (ConvertTo-ArgumentString $args) -WindowStyle Hidden -PassThru
    $started += $process.Id
}
if ($started.Count -gt 0) {
    $pidFile = Join-Path $PSScriptRoot "rclone-mount.pids"
    $started | Set-Content -LiteralPath $pidFile
}
'@

$StopMountTemplate = @'
# Stop-OssMount.ps1 - stops only the OSS mounts started by Start-OssMount.ps1.
$ErrorActionPreference = "SilentlyContinue"
$settingsPath = Join-Path $PSScriptRoot "mount-settings.ps1"
if (Test-Path $settingsPath) { . $settingsPath }

$pidFile = Join-Path $PSScriptRoot "rclone-mount.pids"
if (Test-Path $pidFile) {
    Get-Content $pidFile | ForEach-Object { Stop-Process -Id ([int]$_) -Force -ErrorAction SilentlyContinue }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

# Fallback: kill only rclone processes whose command line references our drive letter or remote.
foreach ($m in $Mounts) {
    $pattern = ([regex]::Escape("$($m.Drive):")) + "|" + ([regex]::Escape([string]$m.Remote))
    Get-CimInstance Win32_Process -Filter "Name='rclone.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $pattern } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
'@

$WatchdogTemplate = @'
# Watchdog-OssMount.ps1 - restarts missing mounts when the network is reachable.
# Run every few minutes by the scheduled task "Mount OSS drive (watchdog)".
$ErrorActionPreference = "SilentlyContinue"
$settingsPath = Join-Path $PSScriptRoot "mount-settings.ps1"
if (-not (Test-Path $settingsPath)) { exit 0 }
. $settingsPath
$logFile = Join-Path $PSScriptRoot "watchdog.log"

foreach ($m in $Mounts) {
    if (-not $m.Drive) { continue }
    if (Get-PSDrive -Name $m.Drive -ErrorAction SilentlyContinue) { continue }
    $dnsOk = $true
    try { [void][System.Net.Dns]::GetHostAddresses($m.Endpoint) } catch { $dnsOk = $false }
    if (-not $dnsOk) { continue }
    Add-Content -LiteralPath $logFile -Value ("{0} restarting missing drive {1}:" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m.Drive)
    & (Join-Path $PSScriptRoot "Start-OssMount.ps1")
}
'@

function Install-OssMountScripts {
    # Writes Start-OssMount.ps1 / Stop-OssMount.ps1 / Watchdog-OssMount.ps1 into $ScriptRoot.
    param([Parameter(Mandatory = $true)][string]$ScriptRoot)
    New-Item -ItemType Directory -Force -Path $ScriptRoot | Out-Null
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText((Join-Path $ScriptRoot "Start-OssMount.ps1"), $StartMountTemplate, $encoding)
    [System.IO.File]::WriteAllText((Join-Path $ScriptRoot "Stop-OssMount.ps1"), $StopMountTemplate, $encoding)
    [System.IO.File]::WriteAllText((Join-Path $ScriptRoot "Watchdog-OssMount.ps1"), $WatchdogTemplate, $encoding)
}

# ---------------------------------------------------------------------------
# Scheduled tasks
# ---------------------------------------------------------------------------

$OssMountTaskNames = @("Mount OSS drive (start)", "Mount OSS drive (watchdog)")

function New-HiddenVbsLauncher {
    # Creates a .vbs that runs the given PowerShell script fully hidden.
    # Scheduled tasks that run powershell.exe directly flash a console window
    # even with -WindowStyle Hidden (the console is created before the switch
    # is applied). wscript.exe never shows a console, so there is no flash.
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$VbsPath
    )
    $vbs = 'CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $ScriptPath + '""", 0, False'
    [System.IO.File]::WriteAllText($VbsPath, $vbs, (New-Object System.Text.ASCIIEncoding))
}

function Register-OssMountTasks {
    # Logon task starts the mount; watchdog task restarts it every 5 minutes.
    # Both tasks run through hidden VBS launchers so no console window flashes.
    param(
        [Parameter(Mandatory = $true)][string]$ScriptRoot,
        [Parameter(Mandatory = $true)][string]$User
    )

    $startScript = Join-Path $ScriptRoot "Start-OssMount.ps1"
    $watchdogScript = Join-Path $ScriptRoot "Watchdog-OssMount.ps1"
    $startVbs = Join-Path $ScriptRoot "Start-OssMount.vbs"
    $watchdogVbs = Join-Path $ScriptRoot "Watchdog-OssMount.vbs"

    foreach ($name in $OssMountTaskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
    $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited

    New-HiddenVbsLauncher -ScriptPath $startScript -VbsPath $startVbs
    New-HiddenVbsLauncher -ScriptPath $watchdogScript -VbsPath $watchdogVbs

    $startAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$startVbs`""
    $startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $User
    Register-ScheduledTask -TaskName $OssMountTaskNames[0] -Action $startAction -Trigger $startTrigger -Principal $principal -Settings $settings | Out-Null

    $watchdogAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$watchdogVbs`""
    $watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName $OssMountTaskNames[1] -Action $watchdogAction -Trigger $watchdogTrigger -Principal $principal -Settings $settings | Out-Null
}

function Remove-OssMountTasks {
    foreach ($name in $OssMountTaskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
}
