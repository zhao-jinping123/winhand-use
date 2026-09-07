@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0probe.ps1" %*
exit /b %errorlevel%
