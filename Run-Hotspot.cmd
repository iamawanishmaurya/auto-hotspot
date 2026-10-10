@echo off
setlocal EnableExtensions
title Auto Hotspot - Setup and Start

REM ===========================================================================
REM  Run-Hotspot.cmd - one-click launcher for New-AutoHotspot.ps1
REM
REM  Double-click this file. It:
REM    1. asks Windows for Administrator rights (UAC prompt) via RunAs
REM    2. removes the Mark-of-the-Web block from the downloaded script
REM    3. runs New-AutoHotspot.ps1 with -ExecutionPolicy Bypass so the
REM       unsigned script runs, WITHOUT changing the machine-wide policy
REM
REM  -NoReboot is passed deliberately: a bare run of the .ps1 reboots the PC
REM  after 20 seconds. Passing -Reboot to this launcher opts back in -- the
REM  launcher drops -NoReboot in that case, because the script rejects having
REM  both at once.
REM
REM  Arguments are forwarded to the script, e.g.
REM    Run-Hotspot.cmd -Show
REM    Run-Hotspot.cmd -Ssid MyLab -Band 2.4GHz
REM    Run-Hotspot.cmd -Revert
REM ===========================================================================

cd /d "%~dp0"

set "PS1=%~dp0New-AutoHotspot.ps1"
set "SELF=%~f0"
REM Exported for the child PowerShell processes below.
set "HOTSPOT_PS1=%PS1%"
set "HOTSPOT_CMD=%SELF%"

if not exist "%PS1%" (
    echo.
    echo   [ERROR] New-AutoHotspot.ps1 was not found next to this launcher.
    echo           Expected: %PS1%
    echo.
    pause
    exit /b 1
)

REM --- Administrator check -------------------------------------------------
REM cacls on config\system is a service-independent admin test, unlike
REM "net session" which also fails when the Server service is stopped.
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if errorlevel 1 goto :need_admin

REM --- Elevated: strip the internal /elevated marker, then run --------------
REM  SWITCH_REBOOT is set if the caller explicitly asked for -Reboot, in which
REM  case we must NOT also pass -NoReboot (the script throws on that pair).
set "ARGS="
set "SWITCH_REBOOT="
:argloop
if "%~1"=="" goto :argend
if /i "%~1"=="/elevated" (
    shift
    goto :argloop
)
if /i "%~1"=="-Reboot" set "SWITCH_REBOOT=1"
set "ARGS=%ARGS% %1"
shift
goto :argloop
:argend

if defined SWITCH_REBOOT (set "NOREBOOT=") else (set "NOREBOOT=-NoReboot")

echo.
echo   Unblocking script (removing Mark-of-the-Web)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Unblock-File -LiteralPath $env:HOTSPOT_PS1 -ErrorAction SilentlyContinue"

echo   Running New-AutoHotspot.ps1 as Administrator...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %NOREBOOT%%ARGS%

set "RC=%errorlevel%"
echo.
if not "%RC%"=="0" (
    echo   Finished with exit code %RC%. Scroll up for the error.
) else (
    echo   Done.
)
echo.
pause
exit /b %RC%

:need_admin
REM --- Not elevated: re-launch ourselves elevated --------------------------
echo.
echo   Administrator rights are required to write the registry keys,
echo   install the scheduled task, and apply the Settings policy.
echo.
echo   A User Account Control prompt is coming up - click Yes.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process -FilePath $env:HOTSPOT_CMD -ArgumentList '/elevated' -Verb RunAs"
exit /b
