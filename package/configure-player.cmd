@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure-interactive.ps1"
if errorlevel 1 (
    echo.
    echo Configuration failed. See the error above.
)
pause
