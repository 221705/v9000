@echo off
rem install_test.bat - TEST MODE installer: adds the direct-boot entry at the END
rem of the boot order without changing the current default. Select it manually from
rem the firmware boot menu (F8/F11/F12) once to verify, then run install.bat.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DirectBoot.ps1" -TestMode
echo.
pause
