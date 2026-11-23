#!/bin/bash
# ==============================================================================
# Live Integrated NGINX Verification Script — Mac 2 Primary Edge
# ==============================================================================

EDGE_IP="10.200.251.227"
BACKEND_IP="10.200.251.76"
MKCERT_CA="$(mkcert -CAROOT)/rootCA.pem"

echo "=== 1. Checking NGINX Process ==="
ps aux | grep nginx | grep -v grep

echo ""
echo "=== 2. NGINX Syntax Check ==="
nginx -t

echo ""
echo "=== 3. Testing HTTPS Virtual Host: app.teamX.test:8443 ==="
curl -i --cacert "$MKCERT_CA" \
     --resolve app.teamX.test:8443:$EDGE_IP \
     https://app.teamX.test:8443/

echo ""
echo "=== 4. Testing HTTPS Virtual Host: api.teamX.test:8443 ==="
curl -i --cacert "$MKCERT_CA" \
     --resolve api.teamX.test:8443:$EDGE_IP \
     https://api.teamX.test:8443/

echo ""
echo "=== 5. Testing HTTP Port 8080 Redirect ==="
curl -i --resolve app.teamX.test:8080:$EDGE_IP \
     http://app.teamX.test:8080/

echo ""
echo "=== 6. Sending 10 Requests for Load-Balancing Verification ==="
for i in {1..10}; do
  RESP=$(curl -s -i --cacert "$MKCERT_CA" \
       --resolve app.teamX.test:8443:$EDGE_IP \
       https://app.teamX.test:8443/)
  BACKEND=$(echo "$RESP" | grep -i "X-Backend:" | tr -d '\r')
  STATUS=$(echo "$RESP" | grep "HTTP/" | head -n 1 | tr -d '\r')
  echo "Request #$i -> $STATUS | $BACKEND"
done
