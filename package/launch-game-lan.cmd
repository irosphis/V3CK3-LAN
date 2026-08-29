@echo off
setlocal
cd /d "%~dp0"
"%~dp0game-lan-launcher.exe"
if errorlevel 1 (
    echo.
    echo Launch failed. See the error above.
    pause
)
