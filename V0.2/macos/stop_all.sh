#!/usr/bin/env bash
# ============================================================
#  LinkGuard macOS Service Stopper
#  Mirrors win11/stop_all.bat — but PID-based to avoid killing
#  unrelated python3 processes on the developer's Mac.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

echo "============================================"
echo "  Stopping LinkGuard services"
echo "============================================"

SERVICES=(mqtt_broker tcp_server gemma4_server whisper_server
          photo_server http_server stats_server resource_server udp_server)

# 1) Kill via PID files written by start_all.sh
for svc in "${SERVICES[@]}"; do
  pidfile="$LOG_DIR/${svc}.pid"
  if [ -f "$pidfile" ]; then
    PID="$(cat "$pidfile" 2>/dev/null || true)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      echo "  killing $svc (PID $PID)"
      kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f "$pidfile"
  fi
done

# 2) Fallback: pkill anything that still matches our scripts (in this dir only)
for svc in "${SERVICES[@]}"; do
  pkill -f "$SCRIPT_DIR/${svc}.py" 2>/dev/null || true
done

# 3) Free the well-known ports just in case
for PORT in 8001 8002 8003 8004 8005 8006 9000 9001 8011; do
  PIDS="$(lsof -ti tcp:"$PORT" 2>/dev/null || true)"
  PIDS_UDP="$(lsof -ti udp:"$PORT" 2>/dev/null || true)"
  for PID in $PIDS $PIDS_UDP; do
    [ -n "$PID" ] || continue
    echo "  port $PORT still held by PID $PID - killing"
    kill -9 "$PID" 2>/dev/null || true
  done
done

sleep 1
echo ""
echo "  All LinkGuard services stopped."
echo "============================================"
