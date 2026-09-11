@echo off
rem Rollback-Compat.bat - restores {bootmgr} path and removes the backup entry
rem Add -Full to also remove all tool files from the ESP:
rem   Rollback-Compat.bat -Full
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Rollback-Compat.ps1" %1
echo.
pause
