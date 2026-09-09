@echo off
rem install.bat - one-click installer for the direct-boot unlock (final boot order)
rem Optional: run "install_test.bat" to install in TEST MODE first (entry added at the
rem end of the boot order, select it manually from the firmware boot menu once).
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DirectBoot.ps1" %*
echo.
pause
