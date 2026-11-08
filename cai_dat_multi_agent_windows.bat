@echo off
chcp 65001 >nul
title Cai dat Herdr chinh thuc + Nauagency Config

echo ==========================================================
echo   CAI DAT HERDR CHINH THUC + NAUAGENCY CONFIG CHO WINDOWS
echo   Phat trien boi Nauagency
echo ==========================================================
echo.
echo Dang khoi chay qua trinh cai dat 1-click...
echo.

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Install-MultiAgent.ps1"

echo.
echo ==========================================================
echo Nhan phim bat ky de thoat cua so nay...
echo ==========================================================
pause >nul
