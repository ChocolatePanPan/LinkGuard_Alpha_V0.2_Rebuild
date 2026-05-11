@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title LinkGuard 停止所有服務

echo ============================================
echo   正在停止所有 LinkGuard 服務...
echo ============================================
echo.

set WORK_DIR=%~dp0

:: --- 第 1 步：依視窗標題關閉（含 cmd /c 包裝視窗）---
for %%t in (
    "MQTT Client"
    "TCP Server :9000"
    "GEMMA4 AI :8001"
    "Qwen AI :8001"
    "Whisper :8002"
    "HTTP Server :8003"
    "Photo Server :8004"
    "Stats Server :8005"
    "Resource Server :8006"
    "UDP Server :9001"
) do (
    taskkill /FI "WINDOWTITLE eq %%~t*" /T /F >nul 2>&1
    taskkill /FI "WINDOWTITLE eq Administrator: %%~t*" /T /F >nul 2>&1
)

:: --- 第 2 步：依 port 強制清除殘留 listener (TCP + UDP) ---
echo   檢查殘留 port ...
for %%p in (8001 8002 8003 8004 8005 8006 9000 9001) do (
    set "FOUND="
    for /f "tokens=5" %%a in ('netstat -ano -p TCP ^| findstr /R /C:":%%p[^0-9].*LISTENING"') do (
        if not defined FOUND (
            echo     TCP %%p 由 PID %%a 佔用 - 強制終止
            taskkill /PID %%a /T /F >nul 2>&1
            set "FOUND=1"
        )
    )
)
:: UDP listener 沒有 LISTENING 狀態，要單獨處理
for %%p in (9001) do (
    set "FOUND="
    for /f "tokens=4" %%a in ('netstat -ano -p UDP ^| findstr /R /C:":%%p[^0-9]"') do (
        if not defined FOUND (
            echo     UDP %%p 由 PID %%a 佔用 - 強制終止
            taskkill /PID %%a /T /F >nul 2>&1
            set "FOUND=1"
        )
    )
)

:: --- 第 3 步：清掉跑在 win11 目錄下的殘留 python 程序 ---
echo   清理殘餘 python 程序 ...
for /f "skip=1 tokens=2" %%a in ('wmic process where "name='python.exe' and commandline like '%%win11%%'" get processid 2^>nul') do (
    if not "%%a"=="" (
        taskkill /PID %%a /F >nul 2>&1
    )
)

echo.
echo ============================================
echo   全部服務已停止。
echo ============================================
echo.
pause
