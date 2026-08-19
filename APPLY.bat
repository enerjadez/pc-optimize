@echo off
setlocal
title Windows Optimize
cd /d "%~dp0"

net session >nul 2>&1
if %errorLevel% neq 0 (
  echo Requesting Administrator...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo   Windows Optimize
echo   Parks sludge. Leaves Defender, audio, Update, and core Windows alone.
echo.
echo   Reboot after. Undo with RESTORE.bat
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize.ps1" -Action Apply
echo.
pause
endlocal
