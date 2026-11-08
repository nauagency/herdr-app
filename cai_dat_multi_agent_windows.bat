@echo off
chcp 65001 >nul
title Cai dat Multi Agent Herdr - Nauagency

echo ==========================================================
echo   HE THONG CAI DAT MULTI AGENT HERDR (6 TAI KHOAN) CHO WINDOWS
echo   Phat trien boi Nauagency
echo ==========================================================
echo.
echo Dang khoi chay qua trinh cai dat 1-click...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-MultiAgent.ps1"

echo.
echo ==========================================================
echo Nhan phim bat ky de thoat cua so nay...
echo ==========================================================
pause >nul
