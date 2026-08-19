@echo off
setlocal
title Windows Optimize - Preview
cd /d "%~dp0"
echo.
echo   Preview only - nothing will be written.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1" -Action Preview
echo.
pause
endlocal
