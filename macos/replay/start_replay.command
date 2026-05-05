#!/usr/bin/env bash
# ============================================================
#  LinkGuard 回放啟動器（macOS）
#  在 Finder 中雙擊此檔案即可在 Terminal 中啟動回放伺服器
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON="python3"
PORT=5000

echo "============================================"
echo "  LinkGuard 事件回放伺服器"
echo "============================================"
echo ""

# ---------- 確認 Python 3 ----------
if ! command -v "$PYTHON" &>/dev/null; then
    echo "[錯誤] 找不到 python3！"
    echo "  請先安裝 Python 3: https://www.python.org/downloads/"
    read -r -p "按 Enter 關閉..."
    exit 1
fi
PYVER=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Python: $("$PYTHON" --version 2>&1)  ✓"

# ---------- 安裝 flask ----------
if ! "$PYTHON" -c "import flask" &>/dev/null 2>&1; then
    echo ""
    echo "  安裝 flask..."
    "$PYTHON" -m pip install flask --quiet || {
        echo "[錯誤] pip install flask 失敗，請手動執行："
        echo "  python3 -m pip install flask"
        read -r -p "按 Enter 關閉..."
        exit 1
    }
fi
echo "  Flask: $("$PYTHON" -c "import flask; print(flask.__version__)")  ✓"

# ---------- 尋找 linkguard.db ----------
DB_PATH=""

# 1) 命令列帶入
if [[ $# -ge 1 && -f "$1" ]]; then
    DB_PATH="$1"
fi

# 2) 常見相對位置（USB 部署後的目錄結構）
if [[ -z "$DB_PATH" ]]; then
    CANDIDATES=(
        "$SCRIPT_DIR/linkguard.db"
        "$SCRIPT_DIR/../data/linkguard.db"
        "$SCRIPT_DIR/../../data/linkguard.db"
        "$SCRIPT_DIR/../linkguard.db"
        "$SCRIPT_DIR/data/linkguard.db"
    )
    for c in "${CANDIDATES[@]}"; do
        c="$(python3 -c "import os; print(os.path.normpath('$c'))")"
        if [[ -f "$c" ]]; then
            DB_PATH="$c"
            break
        fi
    done
fi

# 3) 讓使用者手動輸入
if [[ -z "$DB_PATH" ]]; then
    echo ""
    echo "  找不到 linkguard.db，請輸入完整路徑："
    echo "  （若要使用最新備份，先執行一次主系統的備份功能）"
    read -r -p "  DB 路徑: " MANUAL_PATH
    if [[ -f "$MANUAL_PATH" ]]; then
        DB_PATH="$MANUAL_PATH"
    else
        echo "[錯誤] 檔案不存在: $MANUAL_PATH"
        read -r -p "按 Enter 關閉..."
        exit 1
    fi
fi

echo ""
echo "  資料庫: $DB_PATH"
echo ""

# ---------- 選擇 Port ----------
read -r -p "  HTTP Port [${PORT}]: " INPUT_PORT
PORT="${INPUT_PORT:-$PORT}"

# ---------- 啟動 ----------
echo ""
echo "  啟動回放伺服器於 http://localhost:${PORT}"
echo "  （按 Ctrl+C 停止）"
echo ""
open "http://localhost:${PORT}" &
"$PYTHON" server.py --db "$DB_PATH" --port "$PORT" --no-browser
