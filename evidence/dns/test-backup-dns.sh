#!/bin/bash
# ==============================================================================
# Backup DNS Verification Script — Mac 2 (10.200.251.227)
# ==============================================================================

echo "=== 1. Checking dnsmasq Process ==="
ps aux | grep dnsmasq | grep -v grep

echo ""
echo "=== 2. Checking Listening Ports (UDP & TCP 53) ==="
lsof -iTCP:53 -sTCP:LISTEN -n -P
lsof -iUDP:53 -n -P

echo ""
echo "=== 3. Query app.teamX.test on 127.0.0.1 (UDP) ==="
dig @127.0.0.1 app.teamX.test

echo ""
echo "=== 4. Query api.teamX.test on 127.0.0.1 (UDP) ==="
dig @127.0.0.1 api.teamX.test

echo ""
echo "=== 5. Query app.teamX.test on 10.200.251.227 (UDP) ==="
dig @10.200.251.227 app.teamX.test

echo ""
echo "=== 6. Query api.teamX.test on 10.200.251.227 (UDP) ==="
dig @10.200.251.227 api.teamX.test

echo ""
echo "=== 7. Query app.teamX.test on 127.0.0.1 (TCP) ==="
dig +tcp @127.0.0.1 app.teamX.test

echo ""
echo "=== 8. Query app.teamX.test on 10.200.251.227 (TCP) ==="
dig +tcp @10.200.251.227 app.teamX.test
