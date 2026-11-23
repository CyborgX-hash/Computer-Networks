#!/bin/bash
# ==============================================================================
# Temporary TTL Record Verification Script — Mac 2
# ==============================================================================

echo "=== 1. Process Check ==="
ps aux | grep dnsmasq | grep -v grep

echo ""
echo "=== 2. Query ttl-test.teamX.test on 127.0.0.1 ==="
dig @127.0.0.1 ttl-test.teamX.test

echo ""
echo "=== 3. Query ttl-test.teamX.test on 10.200.251.227 ==="
dig @10.200.251.227 ttl-test.teamX.test

echo ""
echo "=== 4. Confirm app.teamX.test is preserved ==="
dig @127.0.0.1 app.teamX.test

echo ""
echo "=== 5. Confirm api.teamX.test is preserved ==="
dig @127.0.0.1 api.teamX.test
