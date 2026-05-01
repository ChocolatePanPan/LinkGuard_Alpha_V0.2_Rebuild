#!/usr/bin/env bash
# ============================================================
#  LinkGuard macOS HQ Launcher
#  Mirrors win11/start_hq.bat — base services + hq_server.py.
#
#  NOTE: For the typical macOS deployment we recommend running
#  the native SwiftUI LinkGuardHQ app instead of this Python HQ
#  server. This script exists for headless / dev parity with
#  the Windows version.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PYTHON="${PYTHON:-python3}"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "  LinkGuard macOS HQ Launcher"
echo "============================================"
echo ""

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
    read -r -p "  Peer (large model) IP [192.168.100.20]: " PEER_IP
    PEER_IP="${PEER_IP:-192.168.100.20}"
    echo "  Starting as SMALL model, peer: $PEER_IP:8001"
    "$PYTHON" - "$CONFIG_FILE" "$PEER_IP" <<'PYEOF'
import json, pathlib, sys
p, peer = pathlib.Path(sys.argv[1]), sys.argv[2]
c = json.loads(p.read_text("utf-8")) if p.exists() else {}
c.update({"enabled": True, "local_role": "small", "local_model": "gemma4:e4b",
          "peer_host": peer, "peer_port": 8001})
p.write_text(json.dumps(c, ensure_ascii=False, indent=4), "utf-8")
PYEOF
    ;;
  3)
    read -r -p "  Peer (small model) IP [192.168.100.10]: " PEER_IP
    PEER_IP="${PEER_IP:-192.168.100.10}"
    echo "  Starting as LARGE model, peer: $PEER_IP:8001"
    "$PYTHON" - "$CONFIG_FILE" "$PEER_IP" <<'PYEOF'
import json, pathlib, sys
p, peer = pathlib.Path(sys.argv[1]), sys.argv[2]
c = json.loads(p.read_text("utf-8")) if p.exists() else {}
c.update({"enabled": True, "local_role": "large", "local_model": "gemma4:26b",
          "peer_host": peer, "peer_port": 8001})
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

launch() {
  local label="$1" script="$2" logname="$3"
  local logfile="$LOG_DIR/${logname}.log"
  local pidfile="$LOG_DIR/${logname}.pid"
  echo "$label"
  nohup "$PYTHON" "$SCRIPT_DIR/$script" >> "$logfile" 2>&1 &
  echo $! > "$pidfile"
}

launch "[1/6] MQTT Client ..."             mqtt_broker.py     mqtt_broker
launch "[2/6] TCP Server :9000 ..."        tcp_server.py      tcp_server
sleep 2
launch "[3/6] GEMMA4 AI Server :8001 ..."  gemma4_server.py   gemma4_server
launch "[4/6] Whisper Server :8002 ..."    whisper_server.py  whisper_server
sleep 2
launch "[5/6] Photo Server :8004 ..."      photo_server.py    photo_server
sleep 1
launch "[6/6] HQ Server :8080 + :8930 + :8005 ..." hq_server.py hq_server

echo ""
echo "============================================"
echo "  LinkGuard macOS HQ Ready!"
echo "============================================"
cat <<'EOF'

  Backend:
    MQTT Client        -> localhost:1883
    TCP Server         -> :9000
    GEMMA4 AI Server   -> :8001
    Whisper Server     -> :8002
    Photo Server       -> :8004

  HQ Command Center:
    Web Dashboard      -> http://localhost:8080
    Field TCP Command  -> :8930
    LGAP Audio         -> :8005
    Bonjour            -> _linkguard-hq._tcp.local.

EOF
case "$DUAL_CHOICE" in
  2) echo "  Dual-model: SMALL (gemma4:e4b) triage + escalate";;
  3) echo "  Dual-model: LARGE (gemma4:26b) deep analysis";;
  *) echo "  Standalone: gemma4:26b";;
esac
echo ""
echo "  Open http://localhost:8080 in browser to use HQ"
echo "  Run ./stop_all.sh to stop all services"
