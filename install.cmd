@echo off
rem Double-click to install everything (see install.ps1). Extra arguments are passed on, e.g. install.cmd -Smoke
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
