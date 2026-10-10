@echo off
setlocal EnableExtensions
title Auto Hotspot - Revert to Windows Defaults

REM ===========================================================================
REM  Revert-Hotspot.cmd - undo everything New-AutoHotspot.ps1 changed.
REM
REM  Removes the registry locks, un-hides the Settings page, deletes the
REM  scheduled task, resets the SSID/password to Windows defaults, and leaves
REM  the hotspot OFF. Administrator rights are required.
REM ===========================================================================

cd /d "%~dp0"

set "PS1=%~dp0New-AutoHotspot.ps1"
set "SELF=%~f0"
set "HOTSPOT_PS1=%PS1%"
set "HOTSPOT_CMD=%SELF%"

if not exist "%PS1%" (
    echo.
    echo   [ERROR] New-AutoHotspot.ps1 was not found next to this launcher.
    echo.
    pause
    exit /b 1
)

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if errorlevel 1 goto :need_admin

echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Unblock-File -LiteralPath $env:HOTSPOT_PS1 -ErrorAction SilentlyContinue"

echo   Reverting to Windows defaults as Administrator...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Revert -NoReboot

set "RC=%errorlevel%"
echo.
pause
exit /b %RC%

:need_admin
echo.
echo   Administrator rights are required to revert these changes.
echo.
echo   A User Account Control prompt is coming up - click Yes.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath $env:HOTSPOT_CMD -ArgumentList '/elevated' -Verb RunAs"
exit /b
