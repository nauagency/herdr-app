@echo off
setlocal enabledelayedexpansion

for /f "usebackq tokens=*" %%i in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0find_slot.ps1" %*`) do set "SLOT=%%i"
if "%SLOT%"=="" set "SLOT=1"

set "USERPROFILE=C:\Users\damna\.antigravity-accounts\acc%SLOT%"
set "HOME=C:\Users\damna\.antigravity-accounts\acc%SLOT%"
set "APPDATA=C:\Users\damna\.antigravity-accounts\acc%SLOT%\AppData\Roaming"

title Antigravity %SLOT% (acc%SLOT%)
echo ==========================================================
echo    MULTI AGENT HERDR - ANTIGRAVITY (TAI KHOAN %SLOT%)
echo    Moi truong cach ly: acc%SLOT%
echo ==========================================================
echo.

"C:\Users\damna\AppData\Local\agy\bin\agy.exe" %*
