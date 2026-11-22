#!/usr/bin/env bash
# =============================================================================
# Stop Backend B (Port 3002)
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$DIR/backend-b.pid"

STOPPED=0

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping Backend B (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 1
        kill -9 "$PID" 2>/dev/null || true
        STOPPED=1
    fi
    rm -f "$PID_FILE"
fi

# Also ensure port 3002 is freed
PORT_PID=$(lsof -ti:3002 || true)
if [ -n "$PORT_PID" ]; then
    echo "Freeing port 3002 (PID: $PORT_PID)..."
    kill -9 $PORT_PID 2>/dev/null || true
    STOPPED=1
fi

if [ $STOPPED -eq 1 ]; then
    echo "Backend B stopped successfully."
else
    echo "Backend B is not currently running."
fi
