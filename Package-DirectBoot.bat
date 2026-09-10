@echo off
rem Package-DirectBoot.bat - build the distributable zip into dist\
rem No administrator rights needed. Output: dist\NVPermissive-DirectBoot-<timestamp>.zip
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Package-DirectBoot.ps1"
echo.
pause
