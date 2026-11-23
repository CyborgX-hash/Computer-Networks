#!/usr/bin/env bash
# =============================================================================
# Start Backend A (Port 3001)
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/backend-a"

PID_FILE="$DIR/backend-a.pid"
LOG_FILE="$DIR/backend-a.log"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Backend A is already running (PID: $(cat "$PID_FILE")) on port 3001."
    exit 0
fi

# Clean up any lingering process on port 3001
OCCUPIED_PID=$(lsof -ti:3001 || true)
if [ -n "$OCCUPIED_PID" ]; then
    echo "Port 3001 is occupied by PID $OCCUPIED_PID. Terminating..."
    kill -9 $OCCUPIED_PID 2>/dev/null || true
    sleep 1
fi

echo "Starting Backend A on port 3001..."
nohup node server.js < /dev/null >> "$LOG_FILE" 2>&1 &
NEW_PID=$!
disown "$NEW_PID" 2>/dev/null || true
echo "$NEW_PID" > "$PID_FILE"

sleep 1
if kill -0 "$NEW_PID" 2>/dev/null; then
    echo "Backend A successfully started (PID: $NEW_PID) on http://0.0.0.0:3001"
else
    echo "Failed to start Backend A. Check log: $LOG_FILE"
    exit 1
fi
