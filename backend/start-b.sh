#!/usr/bin/env bash
# =============================================================================
# Start Backend B (Port 3002)
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/backend-b"

PID_FILE="$DIR/backend-b.pid"
LOG_FILE="$DIR/backend-b.log"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Backend B is already running (PID: $(cat "$PID_FILE")) on port 3002."
    exit 0
fi

# Clean up any lingering process on port 3002
OCCUPIED_PID=$(lsof -ti:3002 || true)
if [ -n "$OCCUPIED_PID" ]; then
    echo "Port 3002 is occupied by PID $OCCUPIED_PID. Terminating..."
    kill -9 $OCCUPIED_PID 2>/dev/null || true
    sleep 1
fi

echo "Starting Backend B on port 3002..."
nohup node server.js < /dev/null >> "$LOG_FILE" 2>&1 &
NEW_PID=$!
disown "$NEW_PID" 2>/dev/null || true
echo "$NEW_PID" > "$PID_FILE"

sleep 1
if kill -0 "$NEW_PID" 2>/dev/null; then
    echo "Backend B successfully started (PID: $NEW_PID) on http://0.0.0.0:3002"
else
    echo "Failed to start Backend B. Check log: $LOG_FILE"
    exit 1
fi
