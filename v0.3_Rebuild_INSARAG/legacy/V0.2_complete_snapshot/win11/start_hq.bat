@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title LinkGuard HQ

set PYTHON=%~dp0..\.venv\Scripts\python.exe
set WORK_DIR=%~dp0

echo ============================================
echo   LinkGuard Windows HQ Launcher
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
set PEER_IP=192.168.100.20
set /p PEER_IP="  Peer (large model) IP [192.168.100.20]: "
echo   Starting as SMALL model, peer: !PEER_IP!:8001
"%PYTHON%" -c "import json,pathlib;p=pathlib.Path(r'%WORK_DIR%dual_config.json');c=json.loads(p.read_text('utf-8')) if p.exists() else {};c.update({'enabled':True,'local_role':'small','local_model':'gemma4:e4b','peer_host':'!PEER_IP!','peer_port':8001});p.write_text(json.dumps(c,ensure_ascii=False,indent=4),'utf-8')"
goto :mode_done

:mode_large
set PEER_IP=192.168.100.10
set /p PEER_IP="  Peer (small model) IP [192.168.100.10]: "
echo   Starting as LARGE model, peer: !PEER_IP!:8001
"%PYTHON%" -c "import json,pathlib;p=pathlib.Path(r'%WORK_DIR%dual_config.json');c=json.loads(p.read_text('utf-8')) if p.exists() else {};c.update({'enabled':True,'local_role':'large','local_model':'gemma4:26b','peer_host':'!PEER_IP!','peer_port':8001});p.write_text(json.dumps(c,ensure_ascii=False,indent=4),'utf-8')"
goto :mode_done

:mode_standalone
echo   Starting in standalone mode
"%PYTHON%" -c "import json,pathlib;p=pathlib.Path(r'%WORK_DIR%dual_config.json');c=json.loads(p.read_text('utf-8')) if p.exists() else {};c['enabled']=False;p.write_text(json.dumps(c,ensure_ascii=False,indent=4),'utf-8')"

:mode_done
echo.

:: --- Layer 1: Base services ---
echo [1/6] MQTT Client ...
start "MQTT Client" /D "%WORK_DIR%" "%PYTHON%" "%WORK_DIR%mqtt_broker.py"

echo [2/6] TCP Server :9000 ...
start "TCP Server :9000" /D "%WORK_DIR%" "%PYTHON%" "%WORK_DIR%tcp_server.py"
timeout /t 2 /nobreak >nul

:: --- Layer 2: AI ---
echo [3/6] GEMMA4 AI Server :8001 ...
start "GEMMA4 AI :8001" /D "%WORK_DIR%" "%PYTHON%" "%WORK_DIR%gemma4_server.py"

echo [4/6] Whisper Server :8002 ...
start "Whisper :8002" /D "%WORK_DIR%" "%PYTHON%" "%WORK_DIR%whisper_server.py"
timeout /t 2 /nobreak >nul

:: --- Layer 3: Media ---
echo [5/6] Photo Server :8004 ...
start "Photo Server :8004" /D "%WORK_DIR%" "%PYTHON%" "%WORK_DIR%photo_server.py"
timeout /t 1 /nobreak >nul

:: --- Layer 4: HQ ---
echo [6/6] HQ Server :8080 + :8930 + :8005 ...
start "LinkGuard HQ" /D "%WORK_DIR%" "%PYTHON%" "%WORK_DIR%hq_server.py"

echo.
echo ============================================
echo   LinkGuard Windows HQ Ready!
echo ============================================
echo.
echo   Backend:
echo     MQTT Client        -^> localhost:1883
echo     TCP Server         -^> :9000
echo     GEMMA4 AI Server   -^> :8001
echo     Whisper Server     -^> :8002
echo     Photo Server       -^> :8004
echo.
echo   HQ Command Center:
echo     Web Dashboard      -^> http://localhost:8080
echo     Field TCP Command  -^> :8930
echo     LGAP Audio         -^> :8005
echo     Bonjour            -^> _linkguard-hq._tcp.local.
echo.
if "%DUAL_CHOICE%"=="2" echo   Dual-model: SMALL (gemma4:e4b) triage + escalate
if "%DUAL_CHOICE%"=="3" echo   Dual-model: LARGE (gemma4:26b) deep analysis
if "%DUAL_CHOICE%"=="1" echo   Standalone: gemma4:26b
echo.
echo   Open http://localhost:8080 in browser to use HQ
echo   Run stop_hq.bat to stop all services
echo.
pause
