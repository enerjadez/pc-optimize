@echo off
setlocal
title Windows Optimize - Restore
cd /d "%~dp0"

net session >nul 2>&1
if %errorLevel% neq 0 (
  echo Requesting Administrator...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo   Restores the last backup this script made on THIS PC.
echo   Location: %ProgramData%\WinOptimize
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1" -Action Restore
echo.
pause
endlocal
