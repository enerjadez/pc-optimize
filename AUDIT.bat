@echo off
setlocal
title Windows Optimize - Audit
cd /d "%~dp0"
echo.
echo   Inventory only - nothing will be written.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1" -Action Audit
echo.
pause
endlocal
