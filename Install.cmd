@echo off
setlocal
set "BETTER_COMPACT_LAUNCHER=cmd"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Install.ps1"
set "BETTER_COMPACT_EXIT=%ERRORLEVEL%"
echo.
pause
endlocal & exit /b %BETTER_COMPACT_EXIT%
