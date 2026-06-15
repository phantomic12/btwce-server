#!/usr/bin/env bash
# stop.sh — stop a running BTWCE server gracefully.
# 1. Tries "stop" via RCON (uses settings from server.properties)
# 2. Falls back to SIGTERM with 30s grace
# 3. SIGKILL after that
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# --- RCON (if enabled + mcrcon present) ---
ENABLE_RCON=$(grep -E '^enable-rcon=' server.properties 2>/dev/null | cut -d= -f2 || echo "false")
RCON_PORT=$(grep -E '^rcon\.port=' server.properties 2>/dev/null | cut -d= -f2 || true)
RCON_PASS=$(grep -E '^rcon\.password=' server.properties 2>/dev/null | cut -d= -f2 || true)

if [[ "$ENABLE_RCON" == "true" && -n "$RCON_PORT" && -n "$RCON_PASS" ]]; then
  if command -v mcrcon >/dev/null 2>&1; then
    echo "Sending 'stop' via RCON (127.0.0.1:$RCON_PORT)..."
    mcrcon -H 127.0.0.1 -P "$RCON_PORT" -p "$RCON_PASS" "stop" 2>/dev/null || true
  else
    echo "(mcrcon not installed; skipping RCON. Falling back to signals.)"
  fi
fi

# --- Signal the java process ---
JAVA_PID=$(pgrep -f "fabric-server-launch\.jar" || true)
if [[ -z "$JAVA_PID" ]]; then
  echo "No BTWCE server process found."
  exit 0
fi

echo "Sending SIGTERM to PID $JAVA_PID..."
kill -TERM "$JAVA_PID"

for i in $(seq 1 30); do
  if ! kill -0 "$JAVA_PID" 2>/dev/null; then
    echo "Server stopped cleanly after ${i}s."
    exit 0
  fi
  sleep 1
done

echo "Server didn't stop gracefully, sending SIGKILL..."
kill -9 "$JAVA_PID" 2>/dev/null || true
sleep 1
if kill -0 "$JAVA_PID" 2>/dev/null; then
  echo "Failed to kill $JAVA_PID" >&2
  exit 1
fi
echo "Server killed."
