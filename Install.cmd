@echo off
setlocal EnableExtensions
title Auto Hotspot - Install

REM ===========================================================================
REM  Install.cmd - one-click installer for New-AutoHotspot.ps1
REM
REM  Equivalent to the curl one-liner, for people who would rather
REM  double-click a file. It:
REM    1. uses the LOCAL Install-AutoHotspot.ps1 sitting next to this file
REM       (no download needed - you already cloned or downloaded the repo)
REM    2. asks for Administrator rights (UAC prompt)
REM    3. downloads New-AutoHotspot.ps1 to %ProgramData%\AutoHotspot\
REM    4. configures and starts the hotspot
REM    5. counts down and reboots, to prove it comes back on a cold boot
REM
REM  The countdown is 30 seconds. Press Ctrl+C to cancel the reboot.
REM
REM  To install without rebooting, run this instead:
REM      powershell -NoProfile -ExecutionPolicy Bypass -File Install-AutoHotspot.ps1 -NoReboot
REM
REM  Any extra arguments are forwarded, e.g.
REM      Install.cmd -Band 2.4GHz
REM      Install.cmd -Ssid CampusLab -RebootDelaySeconds 60
REM ===========================================================================

cd /d "%~dp0"

set "INSTALLER=%~dp0Install-AutoHotspot.ps1"
set "SELF=%~f0"
set "HOTSPOT_INSTALLER=%INSTALLER%"

if not exist "%INSTALLER%" (
    echo.
    echo   [ERROR] Install-AutoHotspot.ps1 was not found next to this launcher.
    echo           Expected: %INSTALLER%
    echo.
    echo   If you only downloaded Install.cmd, use the curl one-liner from
    echo   the README instead - it fetches both files itself.
    echo.
    pause
    exit /b 1
)

REM --- Administrator check -------------------------------------------------
REM cacls on config\system is a service-independent admin test, unlike
REM "net session" which also fails when the Server service is stopped.
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if errorlevel 1 goto :need_admin

REM --- Elevated: run the installer ------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" %*

set "RC=%errorlevel%"
echo.
if not "%RC%"=="0" (
    echo   Installer exited with code %RC%. Scroll up for the error.
) else (
    echo   Done.
)
echo.
pause
exit /b %RC%

:need_admin
echo.
echo   Administrator rights are required to install the hotspot.
echo.
echo   A User Account Control prompt is coming up - click Yes.
echo.
set "HOTSPOT_CMD=%SELF%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath $env:HOTSPOT_CMD -Verb RunAs"
exit /b
