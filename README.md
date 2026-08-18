# Cloud Object Storage Drive

Mount **Alibaba Cloud OSS / Amazon S3 / any S3-compatible storage** as a Windows drive letter, with a bilingual (Chinese/English) GUI inspired by Alibaba Cloud OSSBrowser 2.0. No credentials are baked into the installer — every user enters their own **Bucket / AccessKey ID / AccessKey Secret** on first run.

中文说明：把阿里云 OSS / Amazon S3 / S3 兼容存储以盘符形式挂载到 Windows。一份通用安装包分发给所有人，首次使用时在 GUI 里填写三项信息即可，不预置任何人的密钥。支持开机自动挂载、断线自动重连、中英文界面切换。

## 功能特性

- 🖥️ 纯 PowerShell + WinForms，无第三方运行时依赖（Windows 10/11 自带）
- 🌏 多服务商：阿里云 OSS / Amazon S3 / 其他 S3 兼容（MinIO 等）
- 🔤 中英文界面一键切换
- 🔐 密钥由每位用户自己输入，不预置、不分发 AK
- ⏰ 开机自动挂载 + 断线每 5 分钟自动重连（计划任务 + 看门狗）

## 快速开始（使用方）

```
CloudObjectStorageDrive.cmd + CloudObjectStorageDrive.Gui.ps1 + CloudObjectStorageDrive.Core.ps1 + 使用说明.txt
```

1. 双击 `CloudObjectStorageDrive.cmd`（首次会自动安装 WinFsp 和 rclone，弹出授权窗口时点「是」）；
2. 选择服务商与区域，填写 **Bucket 名称 / AccessKey ID / AccessKey Secret**；
3. 点击「连接并挂载」→ 挂载为盘符（优先 Z:）；
4. 之后开机自动挂载、断线自动重连。

> 若账号被限制在某个目录前缀（如 `users/<name>/`），在「目录（可选）」中填写；普通整桶权限留空即可。

## 管理员：创建最小权限 RAM 用户（阿里云）

```powershell
# 需先安装并配置阿里云 CLI
.\CloudObjectStorageDrive.Users.ps1 -Usernames "alice","bob" -CreateAccessKey
```

- 每个用户名对应 RAM 用户 `oss-<name>`，权限被限制在 `users/<name>/` 前缀内；
- AccessKey 只显示一次，导出到 `oss-ram-users-accesskeys.csv`，**用后立即删除该 CSV**；
- 把每人的 AK 单独私发，**不要群发**。

## 分发方式

**4 文件 zip（推荐）**：把 `CloudObjectStorageDrive.cmd`、`CloudObjectStorageDrive.Gui.ps1`、
`CloudObjectStorageDrive.Core.ps1`、`使用说明.txt` 四个文件打成 zip 发给使用方即可。
任何机器可用，包括开启 Windows Smart App Control 的 Win11。

## 工作原理

- 底层使用 [rclone](https://rclone.org/)（S3 兼容端点）+ [WinFsp](https://winfsp.dev/) 挂载；
- `CloudObjectStorageDrive.Gui.ps1`：OSSBrowser 风格 GUI（填 3 项 → 验证 → 挂载）；
- `CloudObjectStorageDrive.Core.ps1`：共享核心——rclone 配置（Alibaba/AWS/Other）、挂载脚本生成、计划任务（开机启动 + 看门狗）、依赖自动安装；
- 凭证明文存于 `%APPDATA%\rclone\rclone.conf`（rclone 机制），工具本身不记录、不传输凭证。

## 安全说明

- 请始终使用**最小权限 RAM/IAM 子账号**，离职时及时禁用对应 AK；
- 凭证保存在本机 rclone 配置中（明文），可选加固：
  ```powershell
  icacls "$env:APPDATA\rclone\rclone.conf" /inheritance:r /grant:r "$env:USERNAME:(R)"
  ```
- 对象存储直挂**没有文件锁**，多人同时编辑同一文件会相互覆盖——适合"个人空间 + 少量共享"，共享文件请约定"下载-修改-传回"；
- 本工具不收集任何数据，无网络回传。

## 排障

- 挂载失败：看 `%LOCALAPPDATA%\rclone\oss-cache\rclone-mount.log`
- AccessDenied：确认 GUI「目录（可选）」是否填了账号对应的前缀
- AWS 访问失败：确认 IAM 用户有 `s3:ListBucket` 与 `s3:GetObject/PutObject` 权限
- 手动验证远端：`rclone lsf ossdrive:<bucket>/<prefix>`

## 许可

[MIT](LICENSE) © 2026 Jitendra
