@echo off
setlocal
chcp 65001 >nul
title Cloud Object Storage Drive
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CloudObjectStorageDrive.Gui.ps1"
endlocal
