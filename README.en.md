# Cloud Object Storage Drive

English | [中文](README.md)

Mount **Alibaba Cloud OSS / Amazon S3 / any S3-compatible storage** as a Windows drive letter, with a bilingual (Chinese/English) GUI inspired by Alibaba Cloud OSSBrowser 2.0. No credentials are baked into the installer - every user enters their own **Bucket / AccessKey ID / AccessKey Secret** on first run.

## Features

- 🖥️ Pure PowerShell + WinForms, no third-party runtime (built into Windows 10/11)
- 🌏 Multi-provider: Alibaba Cloud OSS / Amazon S3 / other S3-compatible storage (MinIO, etc.)
- 🔤 One-click Chinese/English UI switch
- 🔐 Credentials are entered by each user at runtime - nothing is pre-baked or distributed
- ⏰ Auto-mount on sign-in + auto-reconnect every 5 minutes (scheduled tasks + watchdog)
- 🗑️ One-click uninstall (stops the mount and removes auto-mount tasks; keeps config for easy reconnect)

## Quick Start (users)

```
CloudObjectStorageDrive.cmd
CloudObjectStorageDrive.Gui.ps1
CloudObjectStorageDrive.Core.ps1
使用说明.txt   (Chinese quick guide, optional)
```

1. Double-click `CloudObjectStorageDrive.cmd` (WinFsp and rclone are installed automatically on first use - click "Yes" on the system prompt);
2. Pick a provider and region, enter **Bucket / AccessKey ID / AccessKey Secret**;
3. Click **"Connect & Mount"** - the storage is mounted as a drive letter (prefers Z:);
4. From then on it auto-mounts at sign-in and reconnects automatically after disconnects.

> If the account is limited to a folder prefix (e.g. `users/<name>/`), fill it in **"Path (optional)"**; leave empty for full-bucket access.

## Admin: create least-privilege RAM users (Alibaba Cloud)

```powershell
# Requires the Alibaba Cloud CLI to be installed and configured.
.\CloudObjectStorageDrive.Users.ps1 -Usernames "alice","bob" -CreateAccessKey
```

- Each username maps to a RAM user `oss-<name>`, scoped to the `users/<name>/` prefix;
- AccessKeys are shown only once and exported to `oss-ram-users-accesskeys.csv` - **delete the CSV immediately after use**;
- Send each user's AccessKey privately - never in bulk.

## Distribution

**4-file zip (recommended)**: package `CloudObjectStorageDrive.cmd`, `CloudObjectStorageDrive.Gui.ps1`, `CloudObjectStorageDrive.Core.ps1`, `使用说明.txt` into a zip and share it. Works on any machine, including Windows 11 with Smart App Control enabled (no unsigned executables involved).

📄 **Installation guide (with screenshots)**: [English](docs/installation-guide.en.html) | [中文](docs/installation-guide.zh.html)

## How it works

- Built on [rclone](https://rclone.org/) (S3-compatible endpoint) + [WinFsp](https://winfsp.dev/);
- `CloudObjectStorageDrive.Gui.ps1`: OSSBrowser-style GUI (enter 3 fields → verify → mount);
- `CloudObjectStorageDrive.Core.ps1`: shared core - rclone config (Alibaba/AWS/Other), mount script generation, scheduled tasks (sign-in start + watchdog), dependency auto-install;
- The mount is started through a scheduled task so the drive letter survives the app closing, and the watchdog restores it within ~5 minutes after a disconnect;
- Credentials are stored in plaintext at `%APPDATA%\rclone\rclone.conf` (rclone mechanism); the tool itself never records or transmits them.

## Security notes

- Always use least-privilege RAM/IAM sub-accounts; disable AccessKeys when users leave;
- Credentials live in the local rclone config (plaintext); optional hardening:
  ```powershell
  icacls "$env:APPDATA\rclone\rclone.conf" /inheritance:r /grant:r "$env:USERNAME:(R)"
  ```
- Object storage mounts have **no file locking** - concurrent edits to the same file can overwrite each other. Best suited for "personal space + light sharing"; for shared files agree on a "download-edit-upload" workflow;
- The tool collects no data and makes no network callbacks.

## Troubleshooting

- Mount failure: check `%LOCALAPPDATA%\rclone\oss-cache\rclone-mount.log`
- AccessDenied: confirm "Path (optional)" matches the account's folder prefix
- AWS access failure: confirm the IAM user has `s3:ListBucket` and `s3:GetObject/PutObject` permissions
- Manual verification: `rclone lsf ossdrive:<bucket>/<prefix>`

## License

[MIT](LICENSE) © 2026 Jitendra
