@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title LinkGuard

set PYTHON=%~dp0..\.venv\Scripts\python.exe
set WORK_DIR=%~dp0

echo ============================================
echo   LinkGuard Service Launcher
echo ============================================
echo.

:: === Dual-model config ===
echo   Dual-Model AI Config
echo   ─────────────────────────
echo   [1] Standalone (gemma4:26b only)
echo   [2] Small model (gemma4:e4b, triage + escalate)
echo   [3] Large model (gemma4:26b, receive escalations)
echo.
set /p DUAL_CHOICE="  Select mode [1]: "
if "%DUAL_CHOICE%"=="" set DUAL_CHOICE=1

if "%DUAL_CHOICE%"=="2" goto :mode_small
if "%DUAL_CHOICE%"=="3" goto :mode_large
goto :mode_standalone

:mode_small
echo   Starting as SMALL model (peer auto-discover via UDP :8011)
"%PYTHON%" -c "import json,pathlib;p=pathlib.Path(r'%WORK_DIR%dual_config.json');c=json.loads(p.read_text('utf-8')) if p.exists() else {};c.update({'enabled':True,'local_role':'small','local_model':'gemma4:e4b','peer_host':'auto','peer_port':8001,'local_callback_url':''});p.write_text(json.dumps(c,ensure_ascii=False,indent=4),'utf-8')"
goto :mode_done

:mode_large
echo   Starting as LARGE model (peer auto-discover via UDP :8011)
"%PYTHON%" -c "import json,pathlib;p=pathlib.Path(r'%WORK_DIR%dual_config.json');c=json.loads(p.read_text('utf-8')) if p.exists() else {};c.update({'enabled':True,'local_role':'large','local_model':'gemma4:26b','peer_host':'auto','peer_port':8001,'local_callback_url':''});p.write_text(json.dumps(c,ensure_ascii=False,indent=4),'utf-8')"
goto :mode_done

:mode_standalone
echo   Starting in standalone mode
"%PYTHON%" -c "import json,pathlib;p=pathlib.Path(r'%WORK_DIR%dual_config.json');c=json.loads(p.read_text('utf-8')) if p.exists() else {};c['enabled']=False;p.write_text(json.dumps(c,ensure_ascii=False,indent=4),'utf-8')"

:mode_done
echo.

:: === 準備 logs 目錄 ===
if not exist "%WORK_DIR%logs" mkdir "%WORK_DIR%logs"

:: === 啟動前清掉佔用的 port，避免新實例綁定失敗閃退 ===
echo   Releasing busy ports (8001-8006, 9000-9001) ...
for %%P in (8001 8002 8003 8004 8005 8006 9000 9001) do (
    for /f "tokens=5" %%A in ('netstat -ano ^| findstr /R /C:":%%P  *.*LISTENING"') do (
        echo     Port %%P held by PID %%A - killing
        taskkill /PID %%A /F >nul 2>&1
    )
)
:: UDP 9001 separate (no LISTENING state)
for /f "tokens=4" %%A in ('netstat -ano -p UDP ^| findstr /R /C:":9001[^0-9]"') do (
    echo     UDP 9001 held by PID %%A - killing
    taskkill /PID %%A /F >nul 2>&1
)
:: UDP 8011 (dual-model auto-discovery)
for /f "tokens=4" %%A in ('netstat -ano -p UDP ^| findstr /R /C:":8011[^0-9]"') do (
    echo     UDP 8011 held by PID %%A - killing
    taskkill /PID %%A /F >nul 2>&1
)
echo.

:: --- Layer 1: MQTT ---
echo [1/9] MQTT Client ...
start "MQTT Client" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%mqtt_broker.py" ^>^> "%WORK_DIR%logs\mqtt_broker.log" 2^>^&1"

:: --- Layer 2: TCP (:9000) ---
echo [2/9] TCP Server :9000 ...
start "TCP Server :9000" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%tcp_server.py" ^>^> "%WORK_DIR%logs\tcp_server.log" 2^>^&1"
timeout /t 2 /nobreak >nul

:: --- Layer 3: AI ---
echo [3/9] GEMMA4 AI Server :8001 ...
start "GEMMA4 AI :8001" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%gemma4_server.py" ^>^> "%WORK_DIR%logs\gemma4_server.log" 2^>^&1"

echo [4/9] Whisper Server :8002 ...
start "Whisper :8002" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%whisper_server.py" ^>^> "%WORK_DIR%logs\whisper_server.log" 2^>^&1"
timeout /t 2 /nobreak >nul

:: --- Layer 4: App ---

echo [5/9] Photo Server :8004 ...
start "Photo Server :8004" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%photo_server.py" ^>^> "%WORK_DIR%logs\photo_server.log" 2^>^&1"

echo [6/9] HTTP Server :8003 ...
start "HTTP Server :8003" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%http_server.py" ^>^> "%WORK_DIR%logs\http_server.log" 2^>^&1"

echo [7/9] Stats Server :8005 ...
start "Stats Server :8005" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%stats_server.py" ^>^> "%WORK_DIR%logs\stats_server.log" 2^>^&1"

echo [8/9] Resource Server :8006 ...
start "Resource Server :8006" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%resource_server.py" ^>^> "%WORK_DIR%logs\resource_server.log" 2^>^&1"
timeout /t 2 /nobreak >nul

echo [9/9] UDP Server :9001 ...
start "UDP Server :9001" /D "%WORK_DIR%" cmd /c ""%PYTHON%" "%WORK_DIR%udp_server.py" ^>^> "%WORK_DIR%logs\udp_server.log" 2^>^&1"

echo.
echo ============================================
echo   All services started!
echo ============================================
echo.
echo   MQTT Client        -^> localhost:1883
echo   TCP Server         -^> :9000
echo   GEMMA4 AI Server   -^> :8001
echo   Whisper Server     -^> :8002
echo   HTTP Server        -^> :8003
echo   Photo Server       -^> :8004
echo   Stats Server       -^> :8005
echo   Resource Server    -^> :8006
echo   UDP Server         -^> :9001
echo.
if "%DUAL_CHOICE%"=="2" echo   Dual-model: SMALL (gemma4:e4b) triage + escalate (peer auto-discover :8011)
if "%DUAL_CHOICE%"=="3" echo   Dual-model: LARGE (gemma4:26b) deep analysis (peer auto-discover :8011)
if "%DUAL_CHOICE%"=="1" echo   Standalone: gemma4:26b
echo.
echo   Logs:  %WORK_DIR%logs\*.log
echo   Tail:  Get-Content "%WORK_DIR%logs\gemma4_server.log" -Wait -Tail 30
echo.
echo   Run stop_all.bat to stop all services
echo ============================================
pause
