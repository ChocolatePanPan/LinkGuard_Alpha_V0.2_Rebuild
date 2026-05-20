@echo off
chcp 65001 >nul
title LinkGuard HQ 停止服務

echo ============================================
echo   正在停止所有 LinkGuard HQ 服務...
echo ============================================
echo.

for %%t in (
    "LinkGuard HQ"
    "MQTT Client"
    "TCP Server :9000"
    "Qwen AI :8001"
    "Whisper :8002"
    "Photo Server :8004"
) do (
    taskkill /FI "WINDOWTITLE eq %%~t*" /F >nul 2>&1
)

:: 確保所有相關 python 子程序也被關閉
for %%p in (8001 8002 8004 8005 8080 8930 9000) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%%p " ^| findstr "LISTENING"') do (
        taskkill /PID %%a /F >nul 2>&1
    )
)

echo.
echo   全部 HQ 服務已停止。
echo ============================================
pause
