#!/usr/bin/env bash
# ============================================================
#  LinkGuard macOS Service Launcher
#  Mirrors win11/start_all.bat (9 services + dual-model config)
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON="${PYTHON:-python3}"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "  LinkGuard macOS Service Launcher"
echo "============================================"
echo ""

# ---------- Dual-model config ----------
cat <<'EOF'
  Dual-Model AI Config
  ─────────────────────────
  [1] Standalone (gemma4:26b only)
  [2] Small model (gemma4:e4b, triage + escalate)
  [3] Large model (gemma4:26b, receive escalations)

EOF
read -r -p "  Select mode [1]: " DUAL_CHOICE
DUAL_CHOICE="${DUAL_CHOICE:-1}"

CONFIG_FILE="$SCRIPT_DIR/dual_config.json"
case "$DUAL_CHOICE" in
  2)
    echo "  Starting as SMALL model (peer auto-discover via UDP :8011)"
    "$PYTHON" - "$CONFIG_FILE" <<'PYEOF'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
c = json.loads(p.read_text("utf-8")) if p.exists() else {}
c.update({"enabled": True, "local_role": "small", "local_model": "gemma4:e4b",
          "peer_host": "auto", "peer_port": 8001, "local_callback_url": ""})
p.write_text(json.dumps(c, ensure_ascii=False, indent=4), "utf-8")
PYEOF
    ;;
  3)
    echo "  Starting as LARGE model (peer auto-discover via UDP :8011)"
    "$PYTHON" - "$CONFIG_FILE" <<'PYEOF'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
c = json.loads(p.read_text("utf-8")) if p.exists() else {}
c.update({"enabled": True, "local_role": "large", "local_model": "gemma4:26b",
          "peer_host": "auto", "peer_port": 8001, "local_callback_url": ""})
p.write_text(json.dumps(c, ensure_ascii=False, indent=4), "utf-8")
PYEOF
    ;;
  *)
    echo "  Starting in standalone mode"
    "$PYTHON" - "$CONFIG_FILE" <<'PYEOF'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
c = json.loads(p.read_text("utf-8")) if p.exists() else {}
c["enabled"] = False
p.write_text(json.dumps(c, ensure_ascii=False, indent=4), "utf-8")
PYEOF
    ;;
esac
echo ""

# ---------- Release busy ports ----------
echo "  Releasing busy ports (8001-8006, 9000-9001, 8011) ..."
for PORT in 8001 8002 8003 8004 8005 8006 9000 9001 8011; do
  PIDS="$(lsof -ti tcp:"$PORT" 2>/dev/null || true)"
  PIDS_UDP="$(lsof -ti udp:"$PORT" 2>/dev/null || true)"
  for PID in $PIDS $PIDS_UDP; do
    [ -n "$PID" ] || continue
    echo "    Port $PORT held by PID $PID - killing"
    kill -9 "$PID" 2>/dev/null || true
  done
done
echo ""

# ---------- Service launcher helper ----------
launch() {
  # $1=label  $2=script  $3=logfile
  local label="$1" script="$2" logname="$3"
  local logfile="$LOG_DIR/${logname}.log"
  local pidfile="$LOG_DIR/${logname}.pid"
  echo "$label"
  nohup "$PYTHON" "$SCRIPT_DIR/$script" >> "$logfile" 2>&1 &
  echo $! > "$pidfile"
}

# ---------- Layer 1: MQTT ----------
launch "[1/9] MQTT Client ..."          mqtt_broker.py     mqtt_broker

# ---------- Layer 2: TCP (:9000) ----------
launch "[2/9] TCP Server :9000 ..."     tcp_server.py      tcp_server
sleep 2

# ---------- Layer 3: AI ----------
launch "[3/9] GEMMA4 AI Server :8001 ..." gemma4_server.py gemma4_server
launch "[4/9] Whisper Server :8002 ..."   whisper_server.py whisper_server
sleep 2

# ---------- Layer 4: App ----------
launch "[5/9] Photo Server :8004 ..."     photo_server.py    photo_server
launch "[6/9] HTTP Server :8003 ..."      http_server.py     http_server
launch "[7/9] Stats Server :8005 ..."     stats_server.py    stats_server
launch "[8/9] Resource Server :8006 ..."  resource_server.py resource_server
sleep 2

launch "[9/9] UDP Server :9001 ..."       udp_server.py      udp_server

echo ""
echo "============================================"
echo "  All services started!"
echo "============================================"
cat <<'EOF'

  MQTT Client        -> localhost:1883
  TCP Server         -> :9000
  GEMMA4 AI Server   -> :8001
  Whisper Server     -> :8002
  HTTP Server        -> :8003
  Photo Server       -> :8004
  Stats Server       -> :8005
  Resource Server    -> :8006
  UDP Server         -> :9001

EOF
case "$DUAL_CHOICE" in
  2) echo "  Dual-model: SMALL (gemma4:e4b) triage + escalate (peer auto-discover :8011)";;
  3) echo "  Dual-model: LARGE (gemma4:26b) deep analysis (peer auto-discover :8011)";;
  *) echo "  Standalone: gemma4:26b";;
esac
echo ""
echo "  Logs:  $LOG_DIR/*.log"
echo "  Tail:  tail -f $LOG_DIR/gemma4_server.log"
echo ""
echo "  Run ./stop_all.sh to stop all services"
echo "============================================"
