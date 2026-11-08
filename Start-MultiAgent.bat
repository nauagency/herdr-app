@echo off
chcp 65001 >nul
title Khoi dong Multi Agent - Nauagency

set "HERDR_EXE=%LOCALAPPDATA%\Programs\herdr-app\herdr-app.exe"
if exist "%HERDR_EXE%" (
    start "" "%HERDR_EXE%"
    exit
)

set "HERDR_ALT=%LOCALAPPDATA%\Programs\herdr-app\Herdr.exe"
if exist "%HERDR_ALT%" (
    start "" "%HERDR_ALT%"
    exit
)

where herdr-app >nul 2>&1
if %ERRORLEVEL% equ 0 (
    start "" herdr-app
    exit
)

where herdr >nul 2>&1
if %ERRORLEVEL% equ 0 (
    start "" herdr
    exit
)

echo [CANH BAO] Khong tim thay ung dung Herdr tren may tinh cua ban!
echo Dang khoi dong trinh cai dat tu dong 'cai_dat_multi_agent_windows.bat'...
echo.
pause
call "%~dp0cai_dat_multi_agent_windows.bat"
