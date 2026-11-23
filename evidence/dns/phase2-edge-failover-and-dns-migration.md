# Phase 2 — Edge Failover and DNS Migration Runbook & Verification Report

**Project:** Private Network Service Platform (Phase 2)  
**Author:** Multi-Node Integration Team (Mac 1, Mac 2, Mac 3)  
**Date:** 2026-11-23  
**Status:** **PREPARED / RUNTIME MIGRATION PENDING COORDINATED LIVE EXECUTION**  

---

## 1. Objective and Architectural Overview

In the baseline Phase 2 architecture:
- **Primary Edge Reverse Proxy:** Hosted on **Mac 2** (`10.200.251.227`), terminating TLS on port `8443` and load balancing to Mac 3.
- **Standby Edge Reverse Proxy:** Deployed on **Mac 1** (`10.200.251.106`), maintaining an identical upstream configuration and certificate chain.
- **Primary DNS Server:** Hosted on **Mac 1** (`10.200.251.106:53`), resolving `app.teamX.test` and `api.teamX.test` to `10.200.251.227`.
- **Backup DNS Server:** Hosted on **Mac 2** (`10.200.251.227:53`), resolving `app.teamX.test` and `api.teamX.test` to `10.200.251.227` with TTL `30s`.
- **Dual Backends:** Hosted on **Mac 3** (`10.200.251.76`), listening on ports `3001` (Backend A) and `3002` (Backend B).

### Edge Failover Goal:
When the Primary Edge proxy on Mac 2 undergoes planned maintenance or unscheduled outage:
1. Client traffic must seamlessly fail over to the Standby Edge proxy on Mac 1 (`10.200.251.106`).
2. Both authoritative DNS servers (Mac 1 Primary and Mac 2 Backup) must update their A-records for `app.teamX.test` and `api.teamX.test` from `10.200.251.227` to `10.200.251.106`.
3. Upstream backends on Mac 3 (`10.200.251.76`) must remain fully accessible via the Standby Edge.
4. Following Primary Edge recovery, DNS records and traffic routing must be cleanly restored to Mac 2.

```
NORMAL STATE:
Client ──[ DNS Query: app.teamX.test ]──> Mac 1 / Mac 2 DNS ──> Returns 10.200.251.227 (Mac 2)
Client ──[ HTTPS :8443 ]────────────────> Mac 2 (Primary Edge) ──> Mac 3 (Backends A & B)

FAILOVER STATE (Mac 2 Edge Down):
Client ──[ DNS Query: app.teamX.test ]──> Mac 1 / Mac 2 DNS ──> Returns 10.200.251.106 (Mac 1)
Client ──[ HTTPS :8443 ]────────────────> Mac 1 (Standby Edge) ──> Mac 3 (Backends A & B)
```

---

## 2. Preflight Health Verification (Baseline)

Before executing any failover migration, all services must be confirmed operational:

```bash
# 1. Verify Backend A and Backend B on Mac 3 (10.200.251.76)
curl -s http://127.0.0.1:3001/health    # Expected: HTTP 200 {"status":"UP","backend":"A"}
curl -s http://127.0.0.1:3002/health    # Expected: HTTP 200 {"status":"UP","backend":"B"}

# 2. Verify Primary Edge on Mac 2 (10.200.251.227)
curl -k -s -I https://10.200.251.227:8443/health    # Expected: HTTP/2 200 OK

# 3. Verify Backup DNS on Mac 2 (10.200.251.227)
dig @10.200.251.227 app.teamX.test +short          # Expected: 10.200.251.227

# 4. Verify Primary DNS on Mac 1 (10.200.251.106)
dig @10.200.251.106 app.teamX.test +short          # Expected: 10.200.251.227
```

---

## 3. Step-by-Step Edge Failover & Migration Procedure

### Phase A: Start Standby Nginx on Mac 1 (Standby Edge Node)
On **Mac 1** (`10.200.251.106`), launch the Standby Nginx instance in daemon mode:
```bash
# Verify configuration syntax
nginx -t -c /opt/homebrew/etc/nginx/nginx-standby.conf

# Start Standby Edge proxy
nginx -c /opt/homebrew/etc/nginx/nginx-standby.conf

# Verify listening listeners
netstat -an | grep -E '\.(8443|8080) '
# Expected: TCP *:8443 (LISTEN) and TCP *:8080 (LISTEN)
```

### Phase B: Stop Primary Nginx on Mac 2 (Primary Edge Outage)
On **Mac 2** (`10.200.251.227`), simulate Primary Edge outage by gracefully stopping Nginx:
```bash
# Gracefully stop primary nginx
nginx -s stop

# IMPORTANT: Do NOT stop dnsmasq on Mac 2! Backup DNS must remain running.
# Confirm Backup DNS is still listening:
sudo lsof -iUDP:53 -P -n
```

### Phase C: Update DNS Records on Both DNS Servers
Both DNS servers must now advertise Mac 1 (`10.200.251.106`) as the active edge address:

#### 1. On Mac 1 (Primary DNS):
Edit `/opt/homebrew/etc/dnsmasq.conf`:
```conf
address=/app.teamX.test/10.200.251.106
address=/api.teamX.test/10.200.251.106
```
Restart Primary DNS:
```bash
sudo brew services restart dnsmasq
```

#### 2. On Mac 2 (Backup DNS):
Edit `/opt/homebrew/etc/dnsmasq-backup.conf`:
```conf
address=/app.teamX.test/10.200.251.106
address=/api.teamX.test/10.200.251.106
```
Restart Backup DNS:
```bash
sudo kill -HUP $(cat /opt/homebrew/var/run/dnsmasq-backup.pid) || sudo brew services restart dnsmasq
```

### Phase D: DNS TTL Wait & Validation
Wait **30 seconds** for local cache records to expire (enforcing Phase 2 TTL 30s):
```bash
sleep 35

# Query Primary DNS on Mac 1
dig @10.200.251.106 app.teamX.test +short
# Expected Answer: 10.200.251.106

# Query Backup DNS on Mac 2
dig @10.200.251.227 app.teamX.test +short
# Expected Answer: 10.200.251.106
```

### Phase E: Application Traffic Validation via Standby Edge (Mac 1)
From any client machine (Mac 3 or external test client):
```bash
# Test HTTPS access through Standby Edge
curl -i https://app.teamX.test:8443/
# Expected: HTTP/2 200 OK
# Response: {"backend":"A","status":"ok","message":"Backend A is running"} (or Backend B)

# Verify Round-Robin load balancing through Standby Edge
for i in {1..4}; do
  curl -s -i https://app.teamX.test:8443/api/status | grep "x-backend"
done
# Expected Output: Alternation between x-backend: A and x-backend: B

# Verify HTTP to HTTPS 8080 redirect
curl -i http://app.teamX.test:8080/
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://app.teamX.test:8443/
```

---

## 4. Step-by-Step Restoration Procedure (Recovery)

Once maintenance on Mac 2 is complete:

### Step 1: Restore Primary Nginx on Mac 2
```bash
nginx -c /opt/homebrew/etc/nginx/nginx.conf
# Verify port 8443 is listening
netstat -an | grep 8443
```

### Step 2: Revert DNS Records on Both Servers
#### On Mac 1 (Primary DNS):
Edit `/opt/homebrew/etc/dnsmasq.conf`:
```conf
address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227
```
Restart: `sudo brew services restart dnsmasq`

#### On Mac 2 (Backup DNS):
Edit `/opt/homebrew/etc/dnsmasq-backup.conf`:
```conf
address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227
```
Restart: `sudo brew services restart dnsmasq`

### Step 3: Wait TTL Period & Validate Normal Ingress
```bash
sleep 35

# Verify DNS resolution points back to Primary Edge (10.200.251.227)
dig @10.200.251.106 app.teamX.test +short    # 10.200.251.227
dig @10.200.251.227 app.teamX.test +short    # 10.200.251.227

# Verify normal HTTPS traffic through Mac 2
curl -i https://app.teamX.test:8443/
# Expected: HTTP/2 200 OK from Mac 2
```

### Step 4: Gracefully Stop Standby Nginx on Mac 1
```bash
nginx -s stop -c /opt/homebrew/etc/nginx/nginx-standby.conf
```

---

## 5. Verification Status & Technical Blocker Report

| Test Item | Specification | Status | Evidence Reference |
| :--- | :--- | :---: | :--- |
| **Standby Edge Runtime Validation** | Standby Nginx serves HTTPS :8443, terminates TLS, and proxies to Mac 3 | **PASS** | [`evidence/nginx/phase2-standby-runtime-verification.md`](../nginx/phase2-standby-runtime-verification.md) |
| **Standby Edge Backend Failover** | Standby Nginx handles Backend A/B outages with 12/12 successful requests | **PASS** | [`evidence/backend/phase2-standby-backend-failover.md`](../backend/phase2-standby-backend-failover.md) |
| **Primary/Backup DNS Dual Server Verification** | Both DNS daemons active and serving identical A-records with TTL 30s | **PASS** | [`evidence/dns/phase2-primary-backup-dns-failover.md`](phase2-primary-backup-dns-failover.md) |
| **DNS TTL 30s Caching & Expiry** | 30s countdown, cache hit, upstream update, and cache expiry re-query verified | **PASS** | [`evidence/dns/phase2-dns-ttl-caching.md`](phase2-dns-ttl-caching.md) |
| **Live Simultaneous Cross-Machine Edge Cutover** | Automated DNS address change during live simulated outage of Mac 2 | **NOT VERIFIED (PREPARED)** | **Blocker:** Requires physical operator action on Mac 1 and Mac 2 simultaneously to stop Mac 2 Nginx and edit `/etc/dnsmasq*.conf` in real-time. Standalone components and procedure fully verified. |

> [!NOTE]
> The migration plan and individual operational components (Mac 1 Standby Edge proxying to Backends, DNS record modification, and TTL 30s propagation) have each been independently proven and logged. Live concurrent multi-node migration is fully scripted above and ready for faculty live demonstration.
