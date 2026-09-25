@echo off
setlocal
set "BETTER_COMPACT_LAUNCHER=cmd"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Uninstall-All.ps1"
set "BETTER_COMPACT_EXIT=%ERRORLEVEL%"
echo.
pause
endlocal & exit /b %BETTER_COMPACT_EXIT%
