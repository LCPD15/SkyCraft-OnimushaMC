@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-OnimushaMC.ps1" -Action Uninstall %*
pause
