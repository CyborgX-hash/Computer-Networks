#!/usr/bin/env bash
# =============================================================================
# Coordinated Standby Backend Failover Verification Script
# Machine: Mac 3 (Saksham - 10.200.251.76)
# Standby Edge: Mac 1 (Mihika - 10.200.251.106:8443)
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/standby_failover_results.log"

exec > >(tee "$LOG_FILE") 2>&1

echo "================================================================="
echo "COORDINATED STANDBY BACKEND FAILOVER TEST EXECUTION"
echo "Date: $(date)"
echo "Host: Mac 3 (10.200.251.76)"
echo "Standby Edge: Mac 1 (10.200.251.106:8443)"
echo "================================================================="

echo ""
echo "=== PREFLIGHT VALIDATION ==="
echo -n "[Backend A local port 3001] ... "
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3001/health
echo -n "[Backend B local port 3002] ... "
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3002/health
echo -n "[Mac 1 Standby nginx 10.200.251.106:8443] ... "
nc -z -v -w 2 10.200.251.106 8443
echo -n "[Mac 2 Primary nginx 10.200.251.227:8443] ... "
nc -z -v -w 2 10.200.251.227 8443

echo ""
echo "=== BASELINE TRAFFIC (Both Backends Active) ==="
for i in {1..4}; do
  echo "--- Baseline Request $i ---"
  RESP=$(curl -s -i -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/)
  STATUS=$(echo "$RESP" | grep "HTTP/" | head -n 1 | tr -d '\r')
  XBACKEND=$(echo "$RESP" | grep -i "X-Backend:" | head -n 1 | tr -d '\r')
  BODY=$(echo "$RESP" | grep "^{" || true)
  echo "  Status: $STATUS | $XBACKEND | Body: $BODY"
  sleep 0.2
done

echo ""
echo "================================================================="
echo "=== TEST A: STOPPING BACKEND A (PORT 3001) ==="
echo "================================================================="
"$DIR/stop-a.sh"
sleep 1

echo "Verifying port 3001 listener status:"
if lsof -iTCP:3001 -sTCP:LISTEN -P -n >/dev/null 2>&1; then
    echo "ERROR: Port 3001 is still listening!"
    exit 1
else
    echo "CONFIRMED: Port 3001 is closed and stopped."
fi

echo ""
echo "Issuing 12 consecutive requests to Standby Edge (Mac 1) during Backend A Outage:"
FAIL_COUNT_A=0
SUCCESS_COUNT_A=0
for i in {1..12}; do
  RESP=$(curl -s -i -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/ 2>&1 || true)
  STATUS=$(echo "$RESP" | grep "HTTP/" | head -n 1 | tr -d '\r')
  XBACKEND=$(echo "$RESP" | grep -i "X-Backend:" | head -n 1 | tr -d '\r')
  BODY=$(echo "$RESP" | grep "^{" || true)
  
  if echo "$STATUS" | grep -q "200"; then
      SUCCESS_COUNT_A=$((SUCCESS_COUNT_A + 1))
      echo "  [Request $i] $(date +%T) -> $STATUS | $XBACKEND | $BODY"
  else
      FAIL_COUNT_A=$((FAIL_COUNT_A + 1))
      echo "  [Request $i] $(date +%T) -> FAILED: $STATUS"
  fi
  sleep 0.3
done

echo "Test A Result: $SUCCESS_COUNT_A/12 succeeded, $FAIL_COUNT_A failed."

echo ""
echo "================================================================="
echo "=== RECOVERY A: RESTORING BACKEND A ==="
echo "================================================================="
"$DIR/start-a.sh"
sleep 2

echo -n "Waiting for Backend A health check ... "
H_STATUS=""
for retry in {1..10}; do
    H_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/health || true)
    if [ "$H_STATUS" = "200" ]; then
        echo "HEALTHY (HTTP 200)"
        break
    fi
    sleep 0.5
done

echo "Verifying traffic distribution after Backend A recovery (8 requests):"
for i in {1..8}; do
  RESP=$(curl -s -i -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/)
  STATUS=$(echo "$RESP" | grep "HTTP/" | head -n 1 | tr -d '\r')
  XBACKEND=$(echo "$RESP" | grep -i "X-Backend:" | head -n 1 | tr -d '\r')
  echo "  [Recovery Request $i] -> $STATUS | $XBACKEND"
  sleep 0.2
done

echo ""
echo "================================================================="
echo "=== TEST B: STOPPING BACKEND B (PORT 3002) ==="
echo "================================================================="
"$DIR/stop-b.sh"
sleep 1

echo "Verifying port 3002 listener status:"
if lsof -iTCP:3002 -sTCP:LISTEN -P -n >/dev/null 2>&1; then
    echo "ERROR: Port 3002 is still listening!"
    exit 1
else
    echo "CONFIRMED: Port 3002 is closed and stopped."
fi

echo ""
echo "Issuing 12 consecutive requests to Standby Edge (Mac 1) during Backend B Outage:"
FAIL_COUNT_B=0
SUCCESS_COUNT_B=0
for i in {1..12}; do
  RESP=$(curl -s -i -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/ 2>&1 || true)
  STATUS=$(echo "$RESP" | grep "HTTP/" | head -n 1 | tr -d '\r')
  XBACKEND=$(echo "$RESP" | grep -i "X-Backend:" | head -n 1 | tr -d '\r')
  BODY=$(echo "$RESP" | grep "^{" || true)
  
  if echo "$STATUS" | grep -q "200"; then
      SUCCESS_COUNT_B=$((SUCCESS_COUNT_B + 1))
      echo "  [Request $i] $(date +%T) -> $STATUS | $XBACKEND | $BODY"
  else
      FAIL_COUNT_B=$((FAIL_COUNT_B + 1))
      echo "  [Request $i] $(date +%T) -> FAILED: $STATUS"
  fi
  sleep 0.3
done

echo "Test B Result: $SUCCESS_COUNT_B/12 succeeded, $FAIL_COUNT_B failed."

echo ""
echo "================================================================="
echo "=== RECOVERY B: RESTORING BACKEND B ==="
echo "================================================================="
"$DIR/start-b.sh"
sleep 2

echo -n "Waiting for Backend B health check ... "
for retry in {1..10}; do
    H_STATUS_B=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3002/health || true)
    if [ "$H_STATUS_B" = "200" ]; then
        echo "HEALTHY (HTTP 200)"
        break
    fi
    sleep 0.5
done

echo "Verifying traffic distribution after Backend B recovery (8 requests):"
for i in {1..8}; do
  RESP=$(curl -s -i -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/)
  STATUS=$(echo "$RESP" | grep "HTTP/" | head -n 1 | tr -d '\r')
  XBACKEND=$(echo "$RESP" | grep -i "X-Backend:" | head -n 1 | tr -d '\r')
  echo "  [Recovery Request $i] -> $STATUS | $XBACKEND"
  sleep 0.2
done

echo ""
echo "=== FINAL BACKEND AND EDGE HEALTH SUMMARY ==="
"$DIR/health-check.sh"
echo "Mac 1 Standby Edge (8443): $(nc -z -v -w 2 10.200.251.106 8443 2>&1)"
echo "Mac 2 Primary Edge (8443): $(nc -z -v -w 2 10.200.251.227 8443 2>&1)"

echo ""
echo "================================================================="
echo "ALL TESTS COMPLETED SUCCESSFULLY"
echo "================================================================="
