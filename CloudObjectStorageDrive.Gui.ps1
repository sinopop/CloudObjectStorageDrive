# CloudObjectStorageDrive.Gui.ps1
# Universal OSS / S3 drive connection tool (UI style inspired by Alibaba Cloud OSSBrowser 2.0).
# Supports Chinese / English (click the EN/中文 button in the top-right corner).
# First use: pick a provider, enter Bucket / AccessKey ID / AccessKey Secret, click Connect & Mount.
# Providers: Alibaba Cloud OSS / Amazon S3 / other S3-compatible storage.
# Dependencies: Windows PowerShell + .NET WinForms; WinFsp and rclone are auto-installed on first connect.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "CloudObjectStorageDrive.Core.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High-DPI: declare the process DPI-aware (PerMonitorV2, fallback System DPI) so the UI
# renders natively (crisp) instead of being bitmap-stretched on 1080p/2K screens.
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class NativeDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(System.IntPtr value);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    if (-not [NativeDpi]::SetProcessDpiAwarenessContext([System.IntPtr](-4))) {
        [void][NativeDpi]::SetProcessDPIAware()
    }
}
catch {
    [void][NativeDpi]::SetProcessDPIAware()
}

# ---------- Constants ----------
$script:RemoteName = "ossdrive"
$script:ScriptRoot = Join-Path $env:LOCALAPPDATA "rclone\oss-mount"
$script:Lang = "zh"
$script:Building = $true

# ---------- Localization ----------
function Set-LanguageStrings {
    param([string]$Lang)
    $script:Lang = $Lang
    if ($Lang -eq "en") {
        $script:S = @{
            Subtitle      = "Mount cloud object storage locally. Supports Alibaba OSS / AWS S3 / S3-compatible"
            StatusIdle    = "Not connected"
            ConfigTitle   = "Connection settings"
            LblProvider   = "Provider"
            LblRegion     = "Region / Endpoint"
            LblEndpoint   = "Endpoint URL"
            LblBucket     = "Bucket name"
            LblAkId       = "AccessKey ID"
            LblAkSecret   = "AccessKey Secret"
            LblPrefix     = "Path (optional)"
            LblShow       = "Show"
            HintPrefix    = "Note: Path is only needed when the account is limited to a subdirectory (e.g. users/zhangsan); leave empty otherwise."
            ChkAutoMount  = "Auto-mount on sign-in (remember connection, auto-reconnect)"
            AdminMode     = "Admin mode"
            StdUserMode   = "Standard user mode (elevation prompt on first install)"
            BtnConnect    = "Connect & Mount"
            BtnStop       = "Stop"
            BtnOpen       = "Open drive"
            BtnRemove     = "Remove"
            LblLog        = "Activity log"
            ChkPathStyle  = "Path style"
            ProviderAli   = "Alibaba Cloud OSS"
            ProviderAws   = "Amazon S3"
            ProviderOther = "Other S3-compatible"
            LangZh        = "中文"
            LangEn        = "EN"
            StatusConnecting = "Connecting..."
            StatusMounted    = "Mounted {0}:"
            StatusMounting   = "Mount starting..."
            StatusFailed     = "Connection failed"
            StatusStopping   = "Stopping..."
            StatusStopped    = "Stopped"
            StatusNoOpen     = "Cannot open"
            StatusRemoved    = "Not connected"
            LogProvider    = "Provider: {0}"
            LogBucketReg   = "Bucket: {0}  Region: {1}"
            LogNoRclone    = "WinFsp/rclone not found. Installing automatically (a system prompt will appear - click Yes, ~1-2 min)..."
            LogRclonePath  = "rclone path: {0}"
            LogWriteConfig = "Writing rclone config (provider={0})..."
            ErrWriteConfig = "Failed to write rclone config; see the log above."
            LogTest        = "Testing access: {0}"
            LogTestFailed  = "Test failed: {0}"
            ErrTestFailed  = "Cannot access storage. Check Bucket / AccessKey / Region. If AccessDenied, the account may be limited to a subdirectory - fill it in 'Path (optional)' and retry."
            LogAccessOk    = "Access verified."
            ErrNoDrive     = "No free drive letter available."
            LogRegistered  = "Registered: auto-mount on sign-in + auto-reconnect every 5 min"
            LogNotReg      = "No auto-mount registered (temporary mount only; reconnect after reboot)"
            LogStartMount  = "Starting mount: {0}: -> {1}"
            LogMountOk     = "Mounted successfully: {0}:"
            LogMountWait   = "Mount task started; drive not ready yet, will retry automatically. Log: {0}"
            LogErrPrefix   = "ERROR: "
            LogStop        = "Stopping OSS mount..."
            LogNothingStop = "Not mounted; nothing to stop."
            LogNotMounted  = "Not mounted yet."
            LogDriveWait   = "Drive not ready; wait or reconnect."
            LogConfirm     = "Remove? This stops the mount and deletes auto-mount tasks (cloud files are not deleted)."
            RemoveTitle    = "Confirm remove"
            LogRemoving    = "Stopping mount and removing scheduled tasks..."
            LogRemoved     = "Remove complete."
            LogDetected    = "Detected mounted: {0}: -> {1}"
            LogStartup     = "Select a provider, enter Bucket / AccessKey ID / AccessKey Secret, then click 'Connect & Mount'."
            LogFirstRun    = "WinFsp and rclone are installed automatically on first use (a system prompt will appear - click Yes)."
            ErrBucket      = "Please enter the Bucket name."
            ErrAkId        = "Please enter the AccessKey ID."
            ErrAkSecret    = "Please enter the AccessKey Secret."
            ErrEndpoint    = "Please select or enter a Region/Endpoint."
            ErrNoRclone    = "rclone still not found after install. Please close and reopen the tool and retry; if it still fails, install rclone manually (winget install Rclone.Rclone)."
            SuccessTitle   = "Mount successful"
            SuccessMsg     = "Congratulations! Cloud Storage has been mounted successfully.`r`n`r`nDrive {0}: is ready. You can now safely exit."
            BtnExit        = "Exit"
        }
    }
    else {
        $script:S = @{
            Subtitle      = "连接云端对象存储服务，挂载到本地。支持阿里云OSS / AWS S3 / S3兼容存储"
            StatusIdle    = "未连接"
            ConfigTitle   = "连接设置"
            LblProvider   = "服务商"
            LblRegion     = "区域 / Endpoint"
            LblEndpoint   = "Endpoint 地址"
            LblBucket     = "Bucket 名称"
            LblAkId       = "AccessKey ID"
            LblAkSecret   = "AccessKey Secret"
            LblPrefix     = "目录（可选）"
            LblShow       = "显示"
            HintPrefix    = "提示：目录仅当账号被限制在子目录时需要填写（如 users/zhangsan）；普通账号留空即可。"
            ChkAutoMount  = "开机自动挂载（记住本次连接，断线自动重连）"
            AdminMode     = "管理员模式"
            StdUserMode   = "普通用户模式（首次安装会弹出授权）"
            BtnConnect    = "连接并挂载"
            BtnStop       = "停止"
            BtnOpen       = "打开盘符"
            BtnRemove     = "卸载"
            LblLog        = "活动日志"
            ChkPathStyle  = "路径风格"
            ProviderAli   = "阿里云 OSS"
            ProviderAws   = "Amazon S3"
            ProviderOther = "其他 S3 兼容"
            LangZh        = "中文"
            LangEn        = "EN"
            StatusConnecting = "连接中..."
            StatusMounted    = "已挂载 {0}:"
            StatusMounting   = "挂载启动中..."
            StatusFailed     = "连接失败"
            StatusStopping   = "停止中..."
            StatusStopped    = "已停止"
            StatusNoOpen     = "无法打开"
            StatusRemoved    = "未连接"
            LogProvider    = "服务商：{0}"
            LogBucketReg   = "Bucket：{0}  区域：{1}"
            LogNoRclone    = "未检测到 WinFsp/rclone，正在自动安装（将弹出系统授权窗口，请点击「是」，约 1-2 分钟）..."
            LogRclonePath  = "rclone 路径：{0}"
            LogWriteConfig = "写入 rclone 配置（provider={0}）..."
            ErrWriteConfig = "rclone 配置写入失败，请查看上方日志。"
            LogTest        = "测试访问：{0}"
            LogTestFailed  = "测试失败：{0}"
            ErrTestFailed  = "无法访问存储。请检查 Bucket / AccessKey / 区域是否正确；若提示 AccessDenied，可能是账号被限制在某个目录，请在「目录（可选）」中填写该目录后重试。"
            LogAccessOk    = "访问验证通过。"
            ErrNoDrive     = "没有可用盘符，请先释放一个盘符。"
            LogRegistered  = "已注册：开机自动挂载 + 断线每 5 分钟自动重连"
            LogNotReg      = "未注册开机任务（本次仅临时挂载，重启后需重新连接）"
            LogStartMount  = "启动挂载：{0}: -> {1}"
            LogMountOk     = "挂载成功：{0}:"
            LogMountWait   = "挂载任务已启动，盘符暂未就绪，将自动重试。日志：{0}"
            LogErrPrefix   = "ERROR："
            LogStop        = "停止 OSS 挂载..."
            LogNothingStop = "尚未挂载，无需停止。"
            LogNotMounted  = "尚未挂载。"
            LogDriveWait   = "盘符尚未就绪，请稍候或重新连接。"
            LogConfirm     = "确定卸载吗？将停止挂载并删除开机任务（不会删除云端文件）。"
            RemoveTitle    = "卸载确认"
            LogRemoving    = "停止挂载并删除计划任务..."
            LogRemoved     = "卸载完成。"
            LogDetected    = "检测到已挂载：{0}: -> {1}"
            LogStartup     = "请选择服务商，填写 Bucket、AccessKey ID、AccessKey Secret 后点击「连接并挂载」。"
            LogFirstRun    = "首次使用会自动安装 WinFsp 和 rclone（会弹出系统授权窗口，点「是」即可）。"
            ErrBucket      = "请填写 Bucket 名称。"
            ErrAkId        = "请填写 AccessKey ID。"
            ErrAkSecret    = "请填写 AccessKey Secret。"
            ErrEndpoint    = "请选择或填写区域/Endpoint。"
            ErrNoRclone    = "安装后仍未找到 rclone。请关闭本工具后重新打开再试；若仍失败，请手动安装 rclone（winget install Rclone.Rclone）。"
            SuccessTitle   = "挂载成功"
            SuccessMsg     = "恭喜，你已经成功挂载 Cloud Storage 到本机！`r`n`r`n盘符 {0}: 已就绪，现在可以安全退出。"
            BtnExit        = "退出"
        }
    }
}

Set-LanguageStrings "zh"

# ---------- Region tables (bilingual) ----------
$script:AlibabaRegions = @(
    @{ Endpoint = "oss-ap-southeast-1.aliyuncs.com";  NameZh = "新加坡";                  NameEn = "Singapore" }
    @{ Endpoint = "oss-cn-hangzhou.aliyuncs.com";     NameZh = "华东1（杭州）";           NameEn = "East China 1 (Hangzhou)" }
    @{ Endpoint = "oss-cn-shanghai.aliyuncs.com";     NameZh = "华东2（上海）";           NameEn = "East China 2 (Shanghai)" }
    @{ Endpoint = "oss-cn-qingdao.aliyuncs.com";      NameZh = "华北1（青岛）";           NameEn = "North China 1 (Qingdao)" }
    @{ Endpoint = "oss-cn-beijing.aliyuncs.com";      NameZh = "华北2（北京）";           NameEn = "North China 2 (Beijing)" }
    @{ Endpoint = "oss-cn-zhangjiakou.aliyuncs.com";  NameZh = "华北3（张家口）";         NameEn = "North China 3 (Zhangjiakou)" }
    @{ Endpoint = "oss-cn-huhehaote.aliyuncs.com";    NameZh = "华北5（呼和浩特）";       NameEn = "North China 5 (Hohhot)" }
    @{ Endpoint = "oss-cn-shenzhen.aliyuncs.com";     NameZh = "华南1（深圳）";           NameEn = "South China 1 (Shenzhen)" }
    @{ Endpoint = "oss-cn-chengdu.aliyuncs.com";      NameZh = "西南1（成都）";           NameEn = "Southwest China 1 (Chengdu)" }
    @{ Endpoint = "oss-cn-hongkong.aliyuncs.com";     NameZh = "中国香港";                NameEn = "Hong Kong" }
    @{ Endpoint = "oss-us-west-1.aliyuncs.com";       NameZh = "美国西部1（硅谷）";       NameEn = "US West 1 (Silicon Valley)" }
    @{ Endpoint = "oss-us-east-1.aliyuncs.com";       NameZh = "美国东部1（弗吉尼亚）";   NameEn = "US East 1 (Virginia)" }
    @{ Endpoint = "oss-ap-northeast-1.aliyuncs.com";  NameZh = "日本（东京）";            NameEn = "Japan (Tokyo)" }
    @{ Endpoint = "oss-ap-northeast-2.aliyuncs.com";  NameZh = "韩国（首尔）";            NameEn = "Korea (Seoul)" }
    @{ Endpoint = "oss-ap-south-1.aliyuncs.com";      NameZh = "印度（孟买）";            NameEn = "India (Mumbai)" }
    @{ Endpoint = "oss-eu-central-1.aliyuncs.com";    NameZh = "德国（法兰克福）";        NameEn = "Germany (Frankfurt)" }
    @{ Endpoint = "oss-eu-west-1.aliyuncs.com";       NameZh = "英国（伦敦）";            NameEn = "UK (London)" }
    @{ Endpoint = "oss-me-east-1.aliyuncs.com";       NameZh = "阿联酋（迪拜）";          NameEn = "UAE (Dubai)" }
    @{ Endpoint = "oss-ap-southeast-2.aliyuncs.com";  NameZh = "澳大利亚（悉尼）";        NameEn = "Australia (Sydney)" }
    @{ Endpoint = "oss-ap-southeast-3.aliyuncs.com";  NameZh = "马来西亚（吉隆坡）";      NameEn = "Malaysia (Kuala Lumpur)" }
    @{ Endpoint = "oss-ap-southeast-5.aliyuncs.com";  NameZh = "印尼（雅加达）";          NameEn = "Indonesia (Jakarta)" }
    @{ Endpoint = "oss-ap-southeast-6.aliyuncs.com";  NameZh = "菲律宾（马尼拉）";        NameEn = "Philippines (Manila)" }
    @{ Endpoint = "oss-ap-southeast-7.aliyuncs.com";  NameZh = "泰国（曼谷）";            NameEn = "Thailand (Bangkok)" }
)

$script:AwsRegions = @(
    @{ Endpoint = "s3.us-east-1.amazonaws.com";       NameZh = "美东1（弗吉尼亚北部）";   NameEn = "US East 1 (N. Virginia)" }
    @{ Endpoint = "s3.us-east-2.amazonaws.com";       NameZh = "美东2（俄亥俄）";         NameEn = "US East 2 (Ohio)" }
    @{ Endpoint = "s3.us-west-1.amazonaws.com";       NameZh = "美西1（北加州）";         NameEn = "US West 1 (N. California)" }
    @{ Endpoint = "s3.us-west-2.amazonaws.com";       NameZh = "美西2（俄勒冈）";         NameEn = "US West 2 (Oregon)" }
    @{ Endpoint = "s3.ap-southeast-1.amazonaws.com";  NameZh = "亚太（新加坡）";          NameEn = "Asia Pacific (Singapore)" }
    @{ Endpoint = "s3.ap-southeast-2.amazonaws.com";  NameZh = "亚太（悉尼）";            NameEn = "Asia Pacific (Sydney)" }
    @{ Endpoint = "s3.ap-northeast-1.amazonaws.com";  NameZh = "亚太（东京）";            NameEn = "Asia Pacific (Tokyo)" }
    @{ Endpoint = "s3.ap-northeast-2.amazonaws.com";  NameZh = "亚太（首尔）";            NameEn = "Asia Pacific (Seoul)" }
    @{ Endpoint = "s3.ap-south-1.amazonaws.com";      NameZh = "亚太（孟买）";            NameEn = "Asia Pacific (Mumbai)" }
    @{ Endpoint = "s3.eu-west-1.amazonaws.com";       NameZh = "欧洲（爱尔兰）";          NameEn = "Europe (Ireland)" }
    @{ Endpoint = "s3.eu-central-1.amazonaws.com";    NameZh = "欧洲（法兰克福）";        NameEn = "Europe (Frankfurt)" }
    @{ Endpoint = "s3.eu-north-1.amazonaws.com";      NameZh = "欧洲（斯德哥尔摩）";      NameEn = "Europe (Stockholm)" }
    @{ Endpoint = "s3.sa-east-1.amazonaws.com";       NameZh = "南美（圣保罗）";          NameEn = "South America (Sao Paulo)" }
    @{ Endpoint = "s3.ca-central-1.amazonaws.com";    NameZh = "加拿大（中部）";          NameEn = "Canada (Central)" }
    @{ Endpoint = "s3.cn-north-1.amazonaws.com.cn";   NameZh = "中国（北京）";            NameEn = "China (Beijing)" }
)

# ---------- Control helpers ----------
function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 120, [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(55, 65, 81))
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 26)
    $label.ForeColor = $Color
    $label.TextAlign = "MiddleLeft"
    return $label
}

function New-TextBox {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [bool]$Password = $false)
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Text = $Text
    $textBox.Location = New-Object System.Drawing.Point($X, $Y)
    $textBox.Size = New-Object System.Drawing.Size($Width, 26)
    $textBox.BorderStyle = "FixedSingle"
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
    if ($Password) { $textBox.UseSystemPasswordChar = $true }
    return $textBox
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [System.Drawing.Color]$BackColor, [System.Drawing.Color]$ForeColor)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 38)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $BackColor
    $button.ForeColor = $ForeColor
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function Set-Status {
    param([string]$Text, [System.Drawing.Color]$Color)
    $script:StatusLabel.Text = $Text
    $script:StatusLabel.ForeColor = $Color
}

function Add-Log {
    param([string]$Text)
    $time = Get-Date -Format "HH:mm:ss"
    $script:LogBox.AppendText("[$time] $Text`r`n")
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Run-ProcessText {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    function Quote-ProcessArgument {
        param([Parameter(Mandatory = $true)][string]$Value)
        if ($Value -notmatch '[\s"]') { return $Value }
        $escaped = $Value -replace '"', '\"'
        return '"' + $escaped + '"'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
    }
}

function Set-RegionItems {
    param([System.Windows.Forms.ComboBox]$Combo, [object[]]$Regions, [string]$Default = "", [string]$Lang = "zh")
    $Combo.Items.Clear()
    foreach ($r in $Regions) {
        $name = if ($Lang -eq "en") { $r.NameEn } else { $r.NameZh }
        [void]$Combo.Items.Add([pscustomobject]@{ Endpoint = $r.Endpoint; Name = $name })
    }
    $Combo.DisplayMember = "Name"
    $Combo.ValueMember = "Endpoint"
    if ($Default) { $Combo.SelectedValue = $Default }
    if ($null -eq $Combo.SelectedValue -and $Combo.Items.Count -gt 0) { $Combo.SelectedIndex = 0 }
}

function Get-ComboEndpoint {
    param([System.Windows.Forms.ComboBox]$Combo)
    $sel = $Combo.SelectedItem
    if ($null -ne $sel -and $sel -is [pscustomobject] -and $sel.Endpoint) {
        return [string]$sel.Endpoint
    }
    return $Combo.Text.Trim()
}

function Derive-AwsRegion {
    param([string]$Endpoint)
    $m = [regex]::Match($Endpoint, '^s3\.([a-z0-9-]+)\.amazonaws\.com(\.cn)?$')
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Show-MountSuccessDialog {
    param([string]$DriveLetter)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Cloud Object Storage Drive"
    $dlg.ClientSize = New-Object System.Drawing.Size(480, 190)
    $dlg.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ControlBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.BackColor = [System.Drawing.Color]::White
    $dlg.TopMost = $true

    $msg = New-Object System.Windows.Forms.Label
    $msg.Text = (($script:S.SuccessMsg) -f $DriveLetter)
    $msg.Location = New-Object System.Drawing.Point(30, 26)
    $msg.Size = New-Object System.Drawing.Size(420, 84)
    $msg.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $msg.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55)
    $dlg.Controls.Add($msg)

    $exitBtn = New-Object System.Windows.Forms.Button
    $exitBtn.Text = $script:S.BtnExit
    $exitBtn.Location = New-Object System.Drawing.Point(356, 128)
    $exitBtn.Size = New-Object System.Drawing.Size(100, 40)
    $exitBtn.FlatStyle = "Flat"
    $exitBtn.BackColor = [System.Drawing.Color]::FromArgb(18, 104, 165)
    $exitBtn.ForeColor = [System.Drawing.Color]::White
    $exitBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $exitBtn.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($exitBtn)

    if ($script:formScale -ne 1.0) { $dlg.Scale((New-Object System.Drawing.SizeF($script:formScale, $script:formScale))) }
    $dlg.AcceptButton = $exitBtn
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

function Update-ProviderRegionUI {
    # Rebuild provider/region controls according to the current language.
    $idx = $script:ProviderBox.SelectedIndex
    if ($idx -lt 0) { $idx = 0 }
    $curEndpoint = Get-ComboEndpoint $script:RegionBox

    $script:ProviderBox.Items.Clear()
    [void]$script:ProviderBox.Items.Add($script:S.ProviderAli)
    [void]$script:ProviderBox.Items.Add($script:S.ProviderAws)
    [void]$script:ProviderBox.Items.Add($script:S.ProviderOther)
    $script:ProviderBox.SelectedIndex = $idx

    if ($idx -eq 0) {
        Set-RegionItems -Combo $script:RegionBox -Regions $script:AlibabaRegions -Default $curEndpoint -Lang $script:Lang
        $script:RegionLabel.Text = $script:S.LblRegion
        $script:PathStyleCheck.Visible = $false
    }
    elseif ($idx -eq 1) {
        Set-RegionItems -Combo $script:RegionBox -Regions $script:AwsRegions -Default $curEndpoint -Lang $script:Lang
        $script:RegionLabel.Text = $script:S.LblRegion
        $script:PathStyleCheck.Visible = $false
    }
    else {
        $script:RegionBox.Items.Clear()
        if ($curEndpoint) { $script:RegionBox.Text = $curEndpoint } else { $script:RegionBox.Text = "https://" }
        $script:RegionLabel.Text = $script:S.LblEndpoint
        $script:PathStyleCheck.Visible = $true
    }
}

function Update-UILanguage {
    # Apply the current language to every static control.
    $script:subtitleLabel.Text = $script:S.Subtitle
    $script:configTitle.Text = $script:S.ConfigTitle
    $script:providerLabel.Text = $script:S.LblProvider
    $script:bucketLabel.Text = $script:S.LblBucket
    $script:akIdLabel.Text = $script:S.LblAkId
    $script:akSecretLabel.Text = $script:S.LblAkSecret
    $script:prefixLabel.Text = $script:S.LblPrefix
    $script:showSecretCheck.Text = $script:S.LblShow
    $script:hintLabel.Text = $script:S.HintPrefix
    $script:autoMountCheck.Text = $script:S.ChkAutoMount
    $script:pathStyleCheck.Text = $script:S.ChkPathStyle
    $script:connectButton.Text = $script:S.BtnConnect
    $script:stopButton.Text = $script:S.BtnStop
    $script:openButton.Text = $script:S.BtnOpen
    $script:removeButton.Text = $script:S.BtnRemove
    $script:logLabel.Text = $script:S.LblLog
    $script:langButton.Text = if ($script:Lang -eq "en") { $script:S.LangZh } else { $script:S.LangEn }
    if (Test-IsAdministrator) {
        $script:adminLabel.Text = $script:S.AdminMode
        $script:adminLabel.ForeColor = [System.Drawing.Color]::FromArgb(22, 130, 85)
    }
    else {
        $script:adminLabel.Text = $script:S.StdUserMode
        $script:adminLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 100, 20)
    }
    if ($script:StatusLabel.Text -eq "" -or $script:statusIdle) {
        $script:StatusLabel.Text = $script:S.StatusIdle
        $script:statusIdle = $false
    }
    Update-ProviderRegionUI
}

# ---------- Main form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Cloud Object Storage Drive"
$form.ClientSize = New-Object System.Drawing.Size(880, 700)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
# Manual DPI scaling is applied once before ShowDialog (see bottom of script) so the
# form and ALL child controls scale together - no blank space on high-DPI screens.
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Header
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(880, 88)
$header.BackColor = [System.Drawing.Color]::FromArgb(20, 32, 48)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Cloud Object Storage Drive"
$titleLabel.Location = New-Object System.Drawing.Point(28, 14)
$titleLabel.Size = New-Object System.Drawing.Size(430, 36)
$titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 19)
$titleLabel.ForeColor = [System.Drawing.Color]::White

$script:subtitleLabel = New-Object System.Windows.Forms.Label
$script:subtitleLabel.Location = New-Object System.Drawing.Point(31, 54)
$script:subtitleLabel.Size = New-Object System.Drawing.Size(700, 24)
$script:subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(188, 199, 211)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.TextAlign = "MiddleRight"
$script:StatusLabel.Location = New-Object System.Drawing.Point(600, 24)
$script:StatusLabel.Size = New-Object System.Drawing.Size(180, 28)
$script:StatusLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$script:statusIdle = $true

$script:langButton = New-Button "" 806 26 50 ([System.Drawing.Color]::FromArgb(52, 68, 90)) ([System.Drawing.Color]::White)
$script:langButton.FlatAppearance.BorderSize = 1
$script:langButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(90, 108, 132)

$header.Controls.Add($titleLabel)
$header.Controls.Add($script:subtitleLabel)
$header.Controls.Add($script:StatusLabel)
$header.Controls.Add($script:langButton)
$form.Controls.Add($header)

# Connection panel
$configPanel = New-Object System.Windows.Forms.Panel
$configPanel.Location = New-Object System.Drawing.Point(24, 104)
$configPanel.Size = New-Object System.Drawing.Size(832, 320)
$configPanel.BackColor = [System.Drawing.Color]::White
$configPanel.BorderStyle = "FixedSingle"

$script:configTitle = New-Object System.Windows.Forms.Label
$script:configTitle.Location = New-Object System.Drawing.Point(24, 16)
$script:configTitle.Size = New-Object System.Drawing.Size(260, 26)
$script:configTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11)
$script:configTitle.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
$configPanel.Controls.Add($script:configTitle)

# Provider
$script:providerLabel = New-Label "" 24 44 240
$configPanel.Controls.Add($script:providerLabel)
$script:ProviderBox = New-Object System.Windows.Forms.ComboBox
$script:ProviderBox.Location = New-Object System.Drawing.Point(24, 70)
$script:ProviderBox.Size = New-Object System.Drawing.Size(280, 26)
$script:ProviderBox.DropDownStyle = "DropDownList"
$configPanel.Controls.Add($script:ProviderBox)

# Region / Endpoint
$script:RegionLabel = New-Label "" 380 44 280
$script:RegionBox = New-Object System.Windows.Forms.ComboBox
$script:RegionBox.Location = New-Object System.Drawing.Point(380, 70)
$script:RegionBox.Size = New-Object System.Drawing.Size(280, 26)
$script:RegionBox.DropDownStyle = "DropDown"
$configPanel.Controls.Add($script:RegionLabel)
$configPanel.Controls.Add($script:RegionBox)

$script:pathStyleCheck = New-Object System.Windows.Forms.CheckBox
$script:pathStyleCheck.Location = New-Object System.Drawing.Point(676, 72)
$script:pathStyleCheck.Size = New-Object System.Drawing.Size(100, 24)
$script:pathStyleCheck.Checked = $true
$script:pathStyleCheck.Visible = $false
$configPanel.Controls.Add($script:pathStyleCheck)

# Bucket / AccessKey ID
$script:bucketLabel = New-Label "" 24 128 290
$script:BucketBox = New-TextBox "" 24 154 280
$configPanel.Controls.Add($script:bucketLabel)
$configPanel.Controls.Add($script:BucketBox)

$script:akIdLabel = New-Label "" 380 128 290
$script:AkIdBox = New-TextBox "" 380 154 290
$configPanel.Controls.Add($script:akIdLabel)
$configPanel.Controls.Add($script:AkIdBox)

# AccessKey Secret / Path (optional)
$script:akSecretLabel = New-Label "" 24 212 290
$script:AkSecretBox = New-TextBox "" 24 238 280 $true
$configPanel.Controls.Add($script:akSecretLabel)
$configPanel.Controls.Add($script:AkSecretBox)

$script:showSecretCheck = New-Object System.Windows.Forms.CheckBox
$script:showSecretCheck.Location = New-Object System.Drawing.Point(308, 240)
$script:showSecretCheck.Size = New-Object System.Drawing.Size(68, 24)
$script:showSecretCheck.AutoSize = $false
$script:showSecretCheck.BringToFront()
$script:showSecretCheck.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$configPanel.Controls.Add($script:showSecretCheck)

$script:prefixLabel = New-Label "" 380 212 290
$script:PrefixBox = New-TextBox "" 380 238 290
$configPanel.Controls.Add($script:prefixLabel)
$configPanel.Controls.Add($script:PrefixBox)

# Hint
$script:hintLabel = New-Label "" 24 292 780 ([System.Drawing.Color]::FromArgb(120, 130, 145))
$script:hintLabel.Size = New-Object System.Drawing.Size(780, 24)
$script:hintLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$configPanel.Controls.Add($script:hintLabel)

$form.Controls.Add($configPanel)

# Auto mount
$script:autoMountCheck = New-Object System.Windows.Forms.CheckBox
$script:autoMountCheck.Location = New-Object System.Drawing.Point(28, 440)
$script:autoMountCheck.Size = New-Object System.Drawing.Size(470, 26)
$script:autoMountCheck.Checked = $true
$form.Controls.Add($script:autoMountCheck)

$script:adminLabel = New-Object System.Windows.Forms.Label
$script:adminLabel.Location = New-Object System.Drawing.Point(520, 440)
$script:adminLabel.Size = New-Object System.Drawing.Size(350, 26)
$script:adminLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$script:adminLabel.TextAlign = "MiddleRight"
$form.Controls.Add($script:adminLabel)

# Buttons
$primary = [System.Drawing.Color]::FromArgb(18, 104, 165)
$neutral = [System.Drawing.Color]::FromArgb(226, 232, 240)
$neutralText = [System.Drawing.Color]::FromArgb(31, 41, 55)
$danger = [System.Drawing.Color]::FromArgb(190, 55, 55)

$script:connectButton = New-Button "" 24 480 190 $primary ([System.Drawing.Color]::White)
$script:stopButton = New-Button "" 226 480 100 $neutral $neutralText
$script:openButton = New-Button "" 338 480 110 $neutral $neutralText
$script:removeButton = New-Button "" 460 480 100 $danger ([System.Drawing.Color]::White)

$form.Controls.Add($script:connectButton)
$form.Controls.Add($script:stopButton)
$form.Controls.Add($script:openButton)
$form.Controls.Add($script:removeButton)

# Log
$script:logLabel = New-Object System.Windows.Forms.Label
$script:logLabel.Location = New-Object System.Drawing.Point(24, 534)
$script:logLabel.Size = New-Object System.Drawing.Size(180, 22)
$script:logLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$script:logLabel.ForeColor = [System.Drawing.Color]::FromArgb(31, 41, 55)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(24, 560)
$script:LogBox.Size = New-Object System.Drawing.Size(832, 116)
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(24, 31, 42)
$script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(210, 220, 230)
$script:LogBox.BorderStyle = "FixedSingle"
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)

$form.Controls.Add($script:logLabel)
$form.Controls.Add($script:LogBox)

# Footer
$footerLabel = New-Object System.Windows.Forms.Label
$footerLabel.Text = "by Jitendra with DSH"
$footerLabel.Location = New-Object System.Drawing.Point(24, 682)
$footerLabel.Size = New-Object System.Drawing.Size(300, 16)
$footerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$footerLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 158, 168)
$form.Controls.Add($footerLabel)

# ---------- Events ----------
$script:ProviderBox.Add_SelectedIndexChanged({
    if ($script:Building) { return }
    $idx = $script:ProviderBox.SelectedIndex
    $curEndpoint = Get-ComboEndpoint $script:RegionBox
    if ($idx -eq 0) {
        Set-RegionItems -Combo $script:RegionBox -Regions $script:AlibabaRegions -Default $curEndpoint -Lang $script:Lang
        $script:RegionLabel.Text = $script:S.LblRegion
        $script:pathStyleCheck.Visible = $false
    }
    elseif ($idx -eq 1) {
        Set-RegionItems -Combo $script:RegionBox -Regions $script:AwsRegions -Default $curEndpoint -Lang $script:Lang
        $script:RegionLabel.Text = $script:S.LblRegion
        $script:pathStyleCheck.Visible = $false
    }
    else {
        $script:RegionBox.Items.Clear()
        if ($curEndpoint) { $script:RegionBox.Text = $curEndpoint } else { $script:RegionBox.Text = "https://" }
        $script:RegionLabel.Text = $script:S.LblEndpoint
        $script:pathStyleCheck.Visible = $true
    }
})

$script:showSecretCheck.Add_CheckedChanged({
    $script:AkSecretBox.UseSystemPasswordChar = -not $script:showSecretCheck.Checked
})

$script:langButton.Add_Click({
    if ($script:Lang -eq "zh") { Set-LanguageStrings "en" } else { Set-LanguageStrings "zh" }
    Update-UILanguage
})

$script:connectButton.Add_Click({
    try {
        Set-Status $script:S.StatusConnecting ([System.Drawing.Color]::FromArgb(235, 170, 65))

        $provIdx = $script:ProviderBox.SelectedIndex
        $providerName = [string]$script:ProviderBox.SelectedItem
        $bucket = $script:BucketBox.Text.Trim()
        $akId = $script:AkIdBox.Text.Trim()
        $akSecret = $script:AkSecretBox.Text
        $prefix = $script:PrefixBox.Text.Trim().Trim("/")
        $endpoint = Get-ComboEndpoint $script:RegionBox

        if (-not $bucket)   { throw $script:S.ErrBucket }
        if (-not $akId)     { throw $script:S.ErrAkId }
        if (-not $akSecret) { throw $script:S.ErrAkSecret }
        if (-not $endpoint) { throw $script:S.ErrEndpoint }

        Add-Log (($script:S.LogProvider) -f $providerName)
        Add-Log (($script:S.LogBucketReg) -f $bucket, $endpoint)

        # 1) Dependencies
        $rclone = Get-RcloneExecutable
        if (-not $rclone) {
            Add-Log $script:S.LogNoRclone
            Install-OssDependencies
            $rclone = Get-RcloneExecutable
            if (-not $rclone) { throw $script:S.ErrNoRclone }
        }
        Add-Log (($script:S.LogRclonePath) -f $rclone)

        # 2) Write config
        $provArg = switch ($provIdx) {
            0 { "Alibaba" }
            1 { "AWS" }
            default { "Other" }
        }
        $region = ""
        if ($provArg -eq "AWS") { $region = Derive-AwsRegion -Endpoint $endpoint }
        $forcePath = ($provArg -eq "Other") -and $script:pathStyleCheck.Checked

        Add-Log (($script:S.LogWriteConfig) -f $provArg)
        $ok = Initialize-RcloneRemote -Rclone $rclone -RemoteName $script:RemoteName -Provider $provArg `
            -AccessKeyId $akId -AccessKeySecret $akSecret -Endpoint $endpoint -Region $region -ForcePathStyle:$forcePath
        if (-not $ok) { throw $script:S.ErrWriteConfig }

        # 3) Test access
        $pathBase = "$($script:RemoteName):$bucket"
        $target = if ($prefix) { "$pathBase/$prefix" } else { $pathBase }
        Add-Log (($script:S.LogTest) -f $target)
        $result = Run-ProcessText $rclone @("lsf", $target)
        if ($result.ExitCode -ne 0) {
            Add-Log (($script:S.LogTestFailed) -f $result.Stderr)
            throw $script:S.ErrTestFailed
        }
        Add-Log $script:S.LogAccessOk

        # 4) Mount - stop any previous OSS mounts first for a clean single mount
        $oldStop = Join-Path $script:ScriptRoot "Stop-OssMount.ps1"
        if (Test-Path $oldStop) {
            Add-Log $script:S.LogStop
            & $oldStop
            Start-Sleep -Seconds 2
        }
        $drive = Get-FirstFreeDriveLetter -Preferred "Z"
        if (-not $drive) { throw $script:S.ErrNoDrive }
        $cacheDir = Join-Path $env:LOCALAPPDATA "rclone\oss-cache"

        $mounts = @(
            @{
                Drive    = $drive
                Remote   = $target
                Rclone   = $rclone
                CacheDir = $cacheDir
                Endpoint = $endpoint
            }
        )
        New-Item -ItemType Directory -Force -Path $script:ScriptRoot | Out-Null
        Write-OssMountSettings -Mounts $mounts -Path (Join-Path $script:ScriptRoot "mount-settings.ps1")
        Install-OssMountScripts -ScriptRoot $script:ScriptRoot

        # Remember the last successful connection (never the secret) to prefill next launch.
        try {
            $lastConn = [ordered]@{ Provider = $provIdx; Endpoint = $endpoint; Bucket = $bucket; Prefix = $prefix }
            [System.IO.File]::WriteAllText((Join-Path $script:ScriptRoot "last-connection.json"), ($lastConn | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        }
        catch { }

        if ($script:autoMountCheck.Checked) {
            $currentUser = "$env:USERDOMAIN\$env:USERNAME"
            Register-OssMountTasks -ScriptRoot $script:ScriptRoot -User $currentUser
            Add-Log $script:S.LogRegistered
        }
        else {
            Remove-OssMountTasks
            Add-Log $script:S.LogNotReg
        }

        Add-Log (($script:S.LogStartMount) -f $drive, $target)
        # Start the mount through the scheduled task: a mount launched directly from the GUI
        # loses its drive letter when the app closes (WinFsp network-drive behavior), while
        # the task-based mount (same path the logon/watchdog tasks use) survives.
        $startTask = Get-ScheduledTask -TaskName "Mount OSS drive (start)" -ErrorAction SilentlyContinue
        if ($startTask) {
            Start-ScheduledTask -TaskName "Mount OSS drive (start)"
        }
        else {
            & (Join-Path $script:ScriptRoot "Start-OssMount.ps1")
        }
        Start-Sleep -Seconds 5

        if (Get-PSDrive -Name $drive -ErrorAction SilentlyContinue) {
            Add-Log (($script:S.LogMountOk) -f $drive)
            Set-Status (($script:S.StatusMounted) -f $drive) ([System.Drawing.Color]::FromArgb(120, 220, 170))
            Show-MountSuccessDialog -DriveLetter $drive
            # "Exit" means close the whole application (the drive stays mounted).
            $form.Close()
        }
        else {
            Add-Log (($script:S.LogMountWait) -f $cacheDir)
            Set-Status $script:S.StatusMounting ([System.Drawing.Color]::FromArgb(235, 170, 65))
        }
    }
    catch {
        Add-Log ($script:S.LogErrPrefix + $_.Exception.Message)
        Set-Status $script:S.StatusFailed ([System.Drawing.Color]::FromArgb(240, 115, 115))
    }
})

$script:stopButton.Add_Click({
    try {
        Set-Status $script:S.StatusStopping ([System.Drawing.Color]::FromArgb(235, 170, 65))
        $stopScript = Join-Path $script:ScriptRoot "Stop-OssMount.ps1"
        if (Test-Path $stopScript) {
            Add-Log $script:S.LogStop
            & $stopScript
            Set-Status $script:S.StatusStopped ([System.Drawing.Color]::FromArgb(188, 199, 211))
        }
        else {
            Add-Log $script:S.LogNothingStop
            Set-Status $script:S.StatusIdle ([System.Drawing.Color]::FromArgb(235, 170, 65))
        }
    }
    catch {
        Add-Log ($script:S.LogErrPrefix + $_.Exception.Message)
        Set-Status $script:S.StatusFailed ([System.Drawing.Color]::FromArgb(240, 115, 115))
    }
})

$script:openButton.Add_Click({
    try {
        $settingsPath = Join-Path $script:ScriptRoot "mount-settings.ps1"
        if (-not (Test-Path $settingsPath)) { throw $script:S.LogNotMounted }
        . $settingsPath
        $mounted = $Mounts | Where-Object { Get-PSDrive -Name $_.Drive -ErrorAction SilentlyContinue } | Select-Object -First 1
        if (-not $mounted) { throw $script:S.LogDriveWait }
        Start-Process "explorer.exe" "$($mounted.Drive):"
    }
    catch {
        Add-Log ($script:S.LogErrPrefix + $_.Exception.Message)
        Set-Status $script:S.StatusNoOpen ([System.Drawing.Color]::FromArgb(240, 115, 115))
    }
})

$script:removeButton.Add_Click({
    try {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $form,
            $script:S.LogConfirm,
            $script:S.RemoveTitle,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Add-Log $script:S.LogRemoving
        $stopScript = Join-Path $script:ScriptRoot "Stop-OssMount.ps1"
        if (Test-Path $stopScript) { & $stopScript }
        Remove-OssMountTasks
        Add-Log $script:S.LogRemoved
        Set-Status $script:S.StatusRemoved ([System.Drawing.Color]::FromArgb(235, 170, 65))
    }
    catch {
        Add-Log ($script:S.LogErrPrefix + $_.Exception.Message)
        Set-Status $script:S.StatusFailed ([System.Drawing.Color]::FromArgb(240, 115, 115))
    }
})

# ---------- Init ----------
# Prefill the last successful connection (provider/endpoint/bucket only, never the secret).
$prefill = $null
$lastConnPath = Join-Path $script:ScriptRoot "last-connection.json"
if (Test-Path $lastConnPath) {
    try {
        $prefill = Get-Content -LiteralPath $lastConnPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { $prefill = $null }
}

Update-ProviderRegionUI
Update-UILanguage

if ($prefill) {
    if ($prefill.Provider -ge 0 -and $prefill.Provider -le 2) { $script:ProviderBox.SelectedIndex = [int]$prefill.Provider }
    if ($prefill.Endpoint) { $script:RegionBox.Text = [string]$prefill.Endpoint }
    if ($prefill.Bucket)   { $script:BucketBox.Text = [string]$prefill.Bucket }
    if ($prefill.Prefix)   { $script:PrefixBox.Text = [string]$prefill.Prefix }
    Update-ProviderRegionUI
}

$script:Building = $false

# Detect existing mount
$settingsPath = Join-Path $script:ScriptRoot "mount-settings.ps1"
if (Test-Path $settingsPath) {
    try {
        . $settingsPath
        foreach ($m in $Mounts) {
            if (Get-PSDrive -Name $m.Drive -ErrorAction SilentlyContinue) {
                Add-Log (($script:S.LogDetected) -f $m.Drive, $m.Remote)
                Set-Status (($script:S.StatusMounted) -f $m.Drive) ([System.Drawing.Color]::FromArgb(120, 220, 170))
            }
        }
    }
    catch { }
}

Add-Log $script:S.LogStartup
Add-Log $script:S.LogFirstRun

# Uniform DPI scaling: scale the form and ALL child controls by dpi/96 so the
# layout fills the window at any display scaling (1080p/2K/4K, no blank space).
$script:formScale = 1.0
$appliedDpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue).AppliedDPI
if ($appliedDpi -and $appliedDpi -gt 0) { $script:formScale = $appliedDpi / 96.0 }
if ($script:formScale -ne 1.0) {
    $form.Scale((New-Object System.Drawing.SizeF($script:formScale, $script:formScale)))
}

[void]$form.ShowDialog()
