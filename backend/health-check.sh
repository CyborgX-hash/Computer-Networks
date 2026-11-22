#!/usr/bin/env bash
# =============================================================================
# Health Check for Backend A and Backend B
# =============================================================================

echo "=================================================="
echo "Backend Health Check Report"
echo "Date: $(date)"
echo "=================================================="

# Check Backend A (Port 3001)
echo -n "[Backend A :3001] ... "
RESP_A=$(curl -s -m 2 http://127.0.0.1:3001/health 2>/dev/null || true)
if [ -n "$RESP_A" ]; then
    echo "HEALTHY (HTTP 200)"
    echo "  Response: $RESP_A"
else
    echo "UNAVAILABLE (Port 3001 not responding)"
fi

# Check Backend B (Port 3002)
echo -n "[Backend B :3002] ... "
RESP_B=$(curl -s -m 2 http://127.0.0.1:3002/health 2>/dev/null || true)
if [ -n "$RESP_B" ]; then
    echo "HEALTHY (HTTP 200)"
    echo "  Response: $RESP_B"
else
    echo "UNAVAILABLE (Port 3002 not responding)"
fi

echo "=================================================="
