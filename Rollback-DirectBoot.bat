@echo off
rem Rollback-DirectBoot.bat - remove the direct-boot entry (and patched file)
rem Usage:   Rollback-DirectBoot.bat          -> remove direct entry only
rem          Rollback-DirectBoot.bat -Full    -> remove everything (full uninstall)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%*'"
    exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Rollback-DirectBoot.ps1" %*
echo.
pause
