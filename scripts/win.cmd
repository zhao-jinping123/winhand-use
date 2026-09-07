@echo off
rem win.cmd - winhand-use entry, delegates to Windows PowerShell 5.1 (STA)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0win.ps1" %*
exit /b %errorlevel%
