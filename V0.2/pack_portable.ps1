<#
  LinkGuard Portable Pack Script
  Packs Ollama + linkguard-qwen model + Python backend into a standalone folder
  Usage:  .\pack_portable.ps1 [-OutputDir "D:\LinkGuard_Portable"]
#>
param(
    [string]$OutputDir = "C:\LinkGuard_Portable"
)

$ErrorActionPreference = "Stop"

$OllamaDir   = "C:\Users\Administrator\AppData\Local\Programs\Ollama"
$ModelsDir   = "C:\Users\Administrator\.ollama\models"
$ProjectDir  = $PSScriptRoot
$Win11Dir    = Join-Path $ProjectDir "win11"

$Manifest    = "$ModelsDir\manifests\registry.ollama.ai\library\linkguard-qwen\latest"
$ManifestObj = Get-Content $Manifest -Raw | ConvertFrom-Json
$RequiredBlobs = @($ManifestObj.config.digest)
foreach ($layer in $ManifestObj.layers) {
    $RequiredBlobs += $layer.digest
}
$RequiredBlobs = $RequiredBlobs | Select-Object -Unique

Write-Host "=== LinkGuard Portable Pack ===" -ForegroundColor Cyan
Write-Host "Output: $OutputDir"
Write-Host "Blobs needed: $($RequiredBlobs.Count)"

$dirs = @(
    "$OutputDir\ollama",
    "$OutputDir\ollama\lib\ollama",
    "$OutputDir\models\blobs",
    "$OutputDir\models\manifests\registry.ollama.ai\library\linkguard-qwen",
    "$OutputDir\win11",
    "$OutputDir\data"
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# 1. Copy Ollama executable
Write-Host ""
Write-Host "[1/5] Copy ollama.exe ..." -ForegroundColor Yellow
Copy-Item "$OllamaDir\ollama.exe" "$OutputDir\ollama\ollama.exe" -Force
$sz = [math]::Round((Get-Item "$OutputDir\ollama\ollama.exe").Length / 1048576, 1)
Write-Host "  ollama.exe  $sz MB"

# 2. Copy GPU runners
Write-Host ""
Write-Host "[2/5] Copy GPU runners ..." -ForegroundColor Yellow
$runners = @("cuda_v12", "cuda_v13", "vulkan")
foreach ($runner in $runners) {
    $src = "$OllamaDir\lib\ollama\$runner"
    if (Test-Path $src) {
        $dest = "$OutputDir\ollama\lib\ollama\$runner"
        Write-Host "  Copying $runner ..."
        Copy-Item $src $dest -Recurse -Force
        $s = (Get-ChildItem $dest -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $sMB = [math]::Round($s / 1048576, 0)
        Write-Host "    $sMB MB"
    }
}

# 3. Copy model
Write-Host ""
Write-Host "[3/5] Copy linkguard-qwen model ..." -ForegroundColor Yellow
Copy-Item $Manifest "$OutputDir\models\manifests\registry.ollama.ai\library\linkguard-qwen\latest" -Force
Write-Host "  manifest OK"

$totalModelBytes = 0
foreach ($digest in $RequiredBlobs) {
    $blobName = $digest -replace ":", "-"
    $src  = "$ModelsDir\blobs\$blobName"
    $dest = "$OutputDir\models\blobs\$blobName"
    if (Test-Path $src) {
        $fileSize = (Get-Item $src).Length
        $fileSizeMB = [math]::Round($fileSize / 1048576, 1)
        $totalModelBytes += $fileSize
        if (Test-Path $dest) {
            $existSize = (Get-Item $dest).Length
            if ($existSize -eq $fileSize) {
                Write-Host "  [SKIP] $blobName already exists"
                continue
            }
        }
        Write-Host "  Copying $blobName ($fileSizeMB MB) ..."
        Copy-Item $src $dest -Force
    } else {
        Write-Warning "  Blob not found: $src"
    }
}
$totalGB = [math]::Round($totalModelBytes / 1073741824, 1)
Write-Host "  Model total: $totalGB GB"

# 4. Copy Python backend
Write-Host ""
Write-Host "[4/5] Copy Python backend (win11/) ..." -ForegroundColor Yellow
$pyFiles = Get-ChildItem $Win11Dir -File | Where-Object {
    $_.Extension -in @(".py", ".txt", ".md", ".json", ".cfg", ".ini", ".bat")
}
foreach ($f in $pyFiles) {
    Copy-Item $f.FullName (Join-Path "$OutputDir\win11" $f.Name) -Force
}
$subDirs = @("replay", "tests")
foreach ($sub in $subDirs) {
    $src = Join-Path $Win11Dir $sub
    if (Test-Path $src) {
        Copy-Item $src (Join-Path "$OutputDir\win11" $sub) -Recurse -Force
    }
}
foreach ($rd in @("data", "photos", "photos\thumbs", "reports")) {
    $rp = "$OutputDir\win11\$rd"
    if (-not (Test-Path $rp)) { New-Item -ItemType Directory -Path $rp -Force | Out-Null }
}

$venvPip = "$Win11Dir\.venv\Scripts\pip.exe"
if (Test-Path $venvPip) {
    & $venvPip freeze 2>$null | Out-File -Encoding utf8 "$OutputDir\win11\requirements.txt"
    Write-Host "  requirements.txt generated"
}
Write-Host "  Python files OK"

# 5. Create startup scripts
Write-Host ""
Write-Host "[5/5] Create startup scripts ..." -ForegroundColor Yellow

$startBat = @'
@echo off
chcp 65001 >nul
title LinkGuard AI
echo ============================================
echo   LinkGuard AI Disaster Rescue System
echo   One-Click Start (9 services + Ollama)
echo ============================================
echo.

set "ROOT=%~dp0"
set "OLLAMA_EXE=%ROOT%ollama\ollama.exe"
set "OLLAMA_MODELS=%ROOT%models"
set "OLLAMA_HOST=127.0.0.1:11434"
set "WIN11=%ROOT%win11"

where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found! Install Python 3.10+
    pause
    exit /b 1
)

if not exist "%WIN11%\.venv" (
    echo [SETUP] First run - creating Python venv ...
    python -m venv "%WIN11%\.venv"
    call "%WIN11%\.venv\Scripts\activate.bat"
    pip install -r "%WIN11%\requirements.txt"
) else (
    call "%WIN11%\.venv\Scripts\activate.bat"
)

echo.
echo [ 0/10] Starting Ollama AI engine :11434 ...
start "Ollama" /min cmd /c "set OLLAMA_MODELS=%OLLAMA_MODELS%&& set OLLAMA_HOST=%OLLAMA_HOST%&& "%OLLAMA_EXE%" serve"
timeout /t 3 /nobreak >nul

echo [ 1/10] Starting MQTT Client :1883 ...
start "MQTT Client" /min cmd /c "cd /d "%WIN11%" && python mqtt_broker.py"
timeout /t 1 /nobreak >nul

echo [ 2/10] Starting TCP Server :9000 ...
start "TCP Server :9000" /min cmd /c "cd /d "%WIN11%" && python tcp_server.py"
timeout /t 2 /nobreak >nul

echo [ 3/10] Starting GEMMA4 AI :8001 ...
start "GEMMA4 AI :8001" /min cmd /c "cd /d "%WIN11%" && python gemma4_server.py"
timeout /t 1 /nobreak >nul

echo [ 4/10] Starting Whisper :8002 ...
start "Whisper :8002" /min cmd /c "cd /d "%WIN11%" && python whisper_server.py"
timeout /t 2 /nobreak >nul

echo [ 5/10] Starting HTTP Server :8003 ...
start "HTTP Server :8003" /min cmd /c "cd /d "%WIN11%" && python http_server.py"
timeout /t 1 /nobreak >nul

echo [ 6/10] Starting Photo Server :8004 ...
start "Photo Server :8004" /min cmd /c "cd /d "%WIN11%" && python photo_server.py"
timeout /t 1 /nobreak >nul

echo [ 7/10] Starting Stats Server :8005 ...
start "Stats Server :8005" /min cmd /c "cd /d "%WIN11%" && python stats_server.py"
timeout /t 1 /nobreak >nul

echo [ 8/10] Starting Resource Server :8006 ...
start "Resource Server :8006" /min cmd /c "cd /d "%WIN11%" && python resource_server.py"
timeout /t 1 /nobreak >nul

echo [ 9/10] Starting UDP Server :9001 ...
start "UDP Server :9001" /min cmd /c "cd /d "%WIN11%" && python udp_server.py"
timeout /t 1 /nobreak >nul

echo [10/10] All services launched!
echo.
echo ============================================
echo   All 10 services started!
echo.
echo   Ollama AI          http://127.0.0.1:11434
echo   MQTT Client        :1883
echo   TCP Server         :9000
echo   GEMMA4 AI Server   http://127.0.0.1:8001
echo   Whisper Server     http://127.0.0.1:8002
echo   HTTP Server        http://127.0.0.1:8003
echo   Photo Server       http://127.0.0.1:8004
echo   Stats Server       http://127.0.0.1:8005
echo   Resource Server    http://127.0.0.1:8006
echo   UDP Server         :9001
echo ============================================
echo.
echo Press any key to stop all services ...
pause >nul

echo.
echo Shutting down ...
for %%t in (
    "Ollama"
    "MQTT Client"
    "TCP Server :9000"
    "GEMMA4 AI :8001"
    "Whisper :8002"
    "HTTP Server :8003"
    "Photo Server :8004"
    "Stats Server :8005"
    "Resource Server :8006"
    "UDP Server :9001"
) do (
    taskkill /FI "WINDOWTITLE eq %%~t*" /F >nul 2>&1
)
for %%p in (8001 8002 8003 8004 8005 8006 9000 9001) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%%p " ^| findstr "LISTENING"') do (
        taskkill /PID %%a /F >nul 2>&1
    )
)
echo Done.
timeout /t 2 /nobreak >nul
'@

$stopBat = @'
@echo off
chcp 65001 >nul
echo Shutting down LinkGuard services ...
for %%t in (
    "Ollama"
    "MQTT Client"
    "TCP Server :9000"
    "GEMMA4 AI :8001"
    "Whisper :8002"
    "HTTP Server :8003"
    "Photo Server :8004"
    "Stats Server :8005"
    "Resource Server :8006"
    "UDP Server :9001"
) do (
    taskkill /FI "WINDOWTITLE eq %%~t*" /F >nul 2>&1
)
for %%p in (8001 8002 8003 8004 8005 8006 9000 9001) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%%p " ^| findstr "LISTENING"') do (
        taskkill /PID %%a /F >nul 2>&1
    )
)
echo Done.
pause
'@

[System.IO.File]::WriteAllText("$OutputDir\start_linkguard.bat", $startBat, [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText("$OutputDir\stop_linkguard.bat", $stopBat, [System.Text.Encoding]::ASCII)

Write-Host "  start_linkguard.bat OK"
Write-Host "  stop_linkguard.bat OK"

# Summary
Write-Host ""
$totalSize = (Get-ChildItem $OutputDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalGB2 = [math]::Round($totalSize / 1073741824, 1)
Write-Host "=== Pack Complete! ===" -ForegroundColor Green
Write-Host "Location: $OutputDir"
Write-Host "Total size: $totalGB2 GB"
Write-Host ""
Write-Host "Deploy steps:" -ForegroundColor Cyan
Write-Host "  1. Copy $OutputDir folder to USB or target PC"
Write-Host "  2. Target PC needs: Python 3.10+ and NVIDIA driver"
Write-Host "  3. Double-click start_linkguard.bat to launch"
Write-Host ""
