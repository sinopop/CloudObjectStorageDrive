@echo off
:: Cloud Object Storage Drive - full uninstall / cleanup (old version leftovers + current version).
:: Usage: double-click to run interactively; or from a command line:
::   Uninstall-cleanup.cmd        interactive (asks before uninstalling rclone/WinFsp)
::   Uninstall-cleanup.cmd -Full  fully automatic (no prompts)
:: Self-elevates to administrator. A UAC prompt appears on machines with default
:: UAC settings; on machines configured for silent elevation it elevates silently.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-cleanup.ps1" %*
