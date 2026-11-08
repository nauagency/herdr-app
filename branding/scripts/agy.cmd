@echo off
setlocal
if "%~1"=="-a" (
    set "ACC=%~2"
    shift
    shift
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_agy_auto.ps1" -Account "%ACC%" %1 %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if "%~1"=="--account" (
    set "ACC=%~2"
    shift
    shift
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_agy_auto.ps1" -Account "%ACC%" %1 %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_agy_auto.ps1" %*
exit /b %ERRORLEVEL%
