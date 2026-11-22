#!/usr/bin/env bash
# =============================================================================
# Automated Backend Failover and Recovery Test
# Demonstrates Requirement D:
# 1. Both backends running & responding.
# 2. Backend A stopped -> Backend B remains healthy and serves traffic.
# 3. Backend A restarted -> Both backends healthy.
# 4. Backend B stopped -> Backend A remains healthy and serves traffic.
# 5. Full recovery with both backends healthy.
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================="
echo "PHASE 2: BACKEND FAILOVER AND RECOVERY VERIFICATION TEST"
echo "Date: $(date)"
echo "================================================================="

echo ""
echo ">>> STEP 1: Ensuring both backends are running..."
"$DIR/start-all.sh"

echo ""
echo ">>> STEP 2: Verifying baseline endpoints and response headers..."
echo "--- Testing Backend A (Port 3001) ---"
curl -s -i http://127.0.0.1:3001/ | head -n 12
curl -s -i http://127.0.0.1:3001/api/status | head -n 12
curl -s -i http://127.0.0.1:3001/health | head -n 12

echo ""
echo "--- Testing Backend B (Port 3002) ---"
curl -s -i http://127.0.0.1:3002/ | head -n 12
curl -s -i http://127.0.0.1:3002/api/status | head -n 12
curl -s -i http://127.0.0.1:3002/health | head -n 12

echo ""
echo ">>> STEP 3: Simulating Backend A Failure (Stopping Backend A)..."
"$DIR/stop-a.sh"

echo "Checking health of both instances during Backend A outage:"
"$DIR/health-check.sh"

echo "Verifying Backend B continues to handle traffic:"
STATUS_B=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3002/health)
if [ "$STATUS_B" = "200" ]; then
    echo "CONFIRMED: Backend B is operational (HTTP $STATUS_B) while Backend A is down."
else
    echo "ERROR: Backend B failed during Backend A outage!"
    exit 1
fi

echo ""
echo ">>> STEP 4: Restoring Backend A..."
"$DIR/start-a.sh"

echo "Checking health after Backend A recovery:"
"$DIR/health-check.sh"

echo ""
echo ">>> STEP 5: Simulating Backend B Failure (Stopping Backend B)..."
"$DIR/stop-b.sh"

echo "Checking health of both instances during Backend B outage:"
"$DIR/health-check.sh"

echo "Verifying Backend A continues to handle traffic:"
STATUS_A=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/health)
if [ "$STATUS_A" = "200" ]; then
    echo "CONFIRMED: Backend A is operational (HTTP $STATUS_A) while Backend B is down."
else
    echo "ERROR: Backend A failed during Backend B outage!"
    exit 1
fi

echo ""
echo ">>> STEP 6: Full Recovery (Restarting Backend B)..."
"$DIR/start-b.sh"

echo "Final health check for both instances:"
"$DIR/health-check.sh"

echo ""
echo "================================================================="
echo "SUCCESS: Backend failover and recovery test completed cleanly!"
echo "================================================================="
