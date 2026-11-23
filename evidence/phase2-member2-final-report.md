# Phase 2 — Member 2 (Saksham) Final Comprehensive Report

**Machine:** Mac 3 — Saksham (`10.200.251.76`, `en0`)  
**Assigned Roles:**
1. **Dual Upstream Backend Microservices:** Express.js Backend A (TCP port `3001`) and Backend B (TCP port `3002`).
2. **Backend Application Architecture:** Baseline routing (`GET /`), cached telemetry (`GET /api/status`), and dedicated health monitoring (`GET /health`).
3. **Response Identification & Header Preservation:** Injection of tracking headers (`X-Backend: A` and `X-Backend: B`) and HTTP caching directives (`Cache-Control: public, max-age=60`).
4. **Backend Ingress Security (Requirement C):** Dual-layer access control enforcing strict access restriction so only authorized edge nodes (Mac 1 Standby Edge `10.200.251.106` and Mac 2 Primary Edge `10.200.251.227`) can reach backend ports.
5. **Packet Filter (PF) Firewall Preparation:** Authoring, validating, and testing scoped PF anchor rules (`config/pf_backend.rules`) with non-destructive activation and safe rollback procedures.
6. **Backend Process Lifecycle Management:** Autonomous daemon startup, shutdown, health-check, and automated failover/recovery verification scripts.
7. **DNS TTL Caching & Expiry Experimentation:** Implementing an isolated local caching resolver (`127.0.0.1:5353`) and empirically verifying 30s TTL countdown, cache hit, and automatic cache eviction.

**Project Directory:** `/Users/sakshamsontakke/Desktop/untitled folder 5/Computer-Networks`  
**Git Branch:** `Backend-Servers`  
**Execution Date:** November 23, 2026  

---

## 1. Network Topology & System Architecture

```
                  ┌─────────────────────────────────────────────────┐
                  │                 LAN SUBNET                      │
                  │              10.200.251.0/24                    │
                  └──────────────────────┬──────────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        │                                │                                │
┌───────▼──────────────┐      ┌──────────▼───────────┐      ┌─────────────▼──────────┐
│   MAC 1 — MIHIKA     │      │ MAC 2 — PRIYANSHU    │      │    MAC 3 — SAKSHAM     │
│   10.200.251.106     │      │   10.200.251.227     │      │     10.200.251.76      │
├──────────────────────┤      ├──────────────────────┤      ├────────────────────────┤
│ • Primary DNS        │      │ • Primary Edge Nginx │      │ • Backend A (:3001)    │
│   (dnsmasq:53 UDP/TCP│      │   (:8443 SSL, :8080) │      │ • Backend B (:3002)    │
│   local-ttl=30)      │      │ • Backup DNS         │      │ • Express API          │
│ • Standby Edge Nginx │      │   (dnsmasq:53 UDP/TCP│      │   (Access Control:     │
│   (:8443 SSL, :8080) │      │   local-ttl=30)      │      │   allowed project IPs) │
└──────────────────────┘      └──────────────────────┘      └────────────────────────┘
```

### Machine Allocation Summary
| Node | Owner | LAN IPv4 (`en0`) | Core Services | Ports & Protocols |
| :--- | :--- | :--- | :--- | :--- |
| **Mac 1** | Mihika | `10.200.251.106` | Primary DNS + Standby Edge NGINX | UDP/TCP 53, TCP 8443, TCP 8080 |
| **Mac 2** | Priyanshu | `10.200.251.227` | Primary Edge NGINX + Backup DNS | TCP 8443, TCP 8080, UDP/TCP 53 |
| **Mac 3** | Saksham | `10.200.251.76` | Backend A + Backend B + Isolated Cache Resolver | TCP 3001, TCP 3002, UDP/TCP 5353 |

---

## 2. Backend Application Architecture (Backend A & Backend B)

Both backend microservices are developed using Node.js and Express.js, hosted independently on Mac 3.

### A. Source Code Implementation
- **Backend A:** [backend/backend-a/server.js](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/backend-a/server.js) (Port `3001`)
- **Backend B:** [backend/backend-b/server.js](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/backend-b/server.js) (Port `3002`)

### B. Endpoints Specification
| Endpoint | Method | Response Payload Format | Response Headers | Purpose |
| :--- | :---: | :--- | :--- | :--- |
| `GET /` | HTTP | `{"backend":"A","status":"ok","message":"Backend A is running"}` | `X-Backend: A`<br>`Content-Type: application/json` | Baseline application response identifying serving backend |
| `GET /api/status` | HTTP | `{"backend":"A","status":"ok"}` | `X-Backend: A`<br>`Cache-Control: public, max-age=60` | Telemetry endpoint with downstream HTTP caching headers |
| `GET /health` | HTTP | `{"status":"UP","backend":"A","port":3001,"timestamp":"..."}` | `X-Backend: A`<br>`Content-Type: application/json` | Dedicated health-check endpoint for upstream reverse proxy monitors |
| Catch-All `*` | HTTP | `{"error":"Not Found"}` | `HTTP 404 Not Found` | Standard 404 error handler for undefined routes |

*(Backend B provides identical JSON schemas with `"backend":"B"`, port `3002`, and header `X-Backend: B`).*

### C. Network Binding & Multi-Interface Accessibility
- Both services bind to `0.0.0.0` (`const HOST = '0.0.0.0'`).
- This binds to all local interfaces, enabling incoming connections from:
  1. Local loopback (`127.0.0.1`) for local diagnostics.
  2. Physical LAN Wi-Fi interface `en0` (`10.200.251.76`) for incoming proxy traffic from Mac 1 and Mac 2.

---

## 3. Backend Access Security & Network Isolation (Requirement C)

Requirement C dictates that only authorized edge nodes may access backend ports `3001` and `3002`, while all unauthorized clients must be denied. To achieve military-grade defense, Mac 3 employs a **Dual-Layer Security Architecture**:

### Layer 1: Application-Layer IP Whitelisting (Express Middleware)
Both `backend-a` and `backend-b` enforce access control via middleware before processing any incoming HTTP request:

```javascript
const ALLOWED_IPS = new Set([
  '127.0.0.1', '::1', '::ffff:127.0.0.1',
  '10.200.251.106', '::ffff:10.200.251.106',  // Mac 1 (Standby Edge)
  '10.200.251.227', '::ffff:10.200.251.227',  // Mac 2 (Primary Edge)
  '10.200.251.76',  '::ffff:10.200.251.76'    // Mac 3 (Localhost)
]);

app.use((req, res, next) => {
  const clientIp = req.socket.remoteAddress;
  if (!ALLOWED_IPS.has(clientIp)) {
    console.warn(`[SECURITY ALERT] Unauthorized access denied from IP: ${clientIp}`);
    return res.status(403).json({
      error: 'Forbidden',
      message: 'Access denied: client IP is not an authorized edge node',
      clientIp: clientIp,
      backend: 'A'
    });
  }
  next();
});
```

### Layer 2: Network-Layer Packet Filter (`pfctl`) Scoped Anchor
To prevent unauthorized TCP handshakes from even reaching Node.js user-space, a dedicated PF anchor ruleset is maintained at [config/pf_backend.rules](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/config/pf_backend.rules):

```pf
# Scoped PF Ruleset for Mac 3 Backend Protection
table <authorized_edges> { 127.0.0.1, 10.200.251.106, 10.200.251.227 }

pass in quick on lo0 proto tcp to any port { 3001, 3002 }
pass in quick proto tcp from <authorized_edges> to any port { 3001, 3002 }
block drop in quick proto tcp to any port { 3001, 3002 }
```

#### Safe Non-Destructive Management & Rollback
1. **Rule Validation (Dry Run):**
   ```bash
   pfctl -v -n -f config/pf_backend.rules
   ```
2. **Safe Activation into Scoped Anchor:**
   ```bash
   sudo pfctl -a backend -f config/pf_backend.rules
   ```
   *Note: Loading into anchor `backend` does NOT overwrite or flush the main system ruleset `/etc/pf.conf` and does NOT affect SSH or normal LAN connectivity.*
3. **Instant Rollback / Deactivation:**
   ```bash
   sudo pfctl -a backend -F all
   ```
4. **Configuration Backup:**
   Original operating system configuration backed up at [config/pf.conf.backup](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/config/pf.conf.backup).

---

## 4. Service Automation & Process Lifecycle

A modular set of shell automation scripts manages backend service lifecycles:

| Script | Path | Function |
| :--- | :--- | :--- |
| `start-a.sh` | [backend/start-a.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/start-a.sh) | Starts Backend A (`:3001`), decouples stdin (`< /dev/null`), appends log, disowns process, records PID to `backend-a.pid`. |
| `stop-a.sh` | [backend/stop-a.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/stop-a.sh) | Gracefully terminates Backend A, verifies port 3001 is freed, cleans PID file. |
| `start-b.sh` | [backend/start-b.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/start-b.sh) | Starts Backend B (`:3002`), decouples stdin, disowns process, records PID to `backend-b.pid`. |
| `stop-b.sh` | [backend/stop-b.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/stop-b.sh) | Gracefully terminates Backend B, verifies port 3002 is freed, cleans PID file. |
| `start-all.sh` | [backend/start-all.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/start-all.sh) | Single command to launch both backends and verify health status. |
| `stop-all.sh` | [backend/stop-all.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/stop-all.sh) | Single command to stop both backends cleanly. |
| `health-check.sh` | [backend/health-check.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/health-check.sh) | Queries `/health` on 3001 and 3002 and prints formatted status report. |
| `test-backend-failover.sh` | [backend/test-backend-failover.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/test-backend-failover.sh) | Automated local 6-step failover and recovery test script. |
| `test-standby-failover.sh` | [backend/test-standby-failover.sh](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/backend/test-standby-failover.sh) | Coordinated failover test script issuing traffic through Mac 1 Standby Edge. |

---

## 5. Verification & Test Evidence Catalog

### A. Coordinated Standby Failover Test
- **Evidence Document:** [evidence/backend/phase2-standby-backend-failover.md](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/evidence/backend/phase2-standby-backend-failover.md)
- **Key Results:**
  - **Baseline:** Alternating round-robin through Mac 1 Standby Edge (`X-Backend: A` and `X-Backend: B`).
  - **Backend A Outage:** Port 3001 stopped. 12/12 consecutive requests succeeded cleanly via Backend B (`X-Backend: B`, `HTTP 200 OK`, 0 failed requests).
  - **Backend A Recovery:** Service restarted. Traffic returned to balanced distribution across both backends.
  - **Backend B Outage:** Port 3002 stopped. 12/12 consecutive requests succeeded cleanly via Backend A (`X-Backend: A`, `HTTP 200 OK`, 0 failed requests).
  - **Backend B Recovery:** Service restarted. Full dual-backend load balancing restored.

### B. DNS TTL Caching & Expiration Experiment
- **Evidence Document:** [evidence/dns/phase2-dns-ttl-caching.md](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/evidence/dns/phase2-dns-ttl-caching.md)
- **Resolver Setup:** Local isolated resolver on `127.0.0.1:5353` forwarding to Mac 2 (`10.200.251.227:53`).
- **Key Results:**
  - Initial query at `15:44:36`: Forwarded to Mac 2, returned `192.0.2.10` with `TTL 30`.
  - Cache query at `15:44:44` (+8s): Served from local cache, returned `192.0.2.10` with `TTL 22` (`cached ttl-test.teamx.test is 192.0.2.10`).
  - Cache expiry at `15:47:14` (>30s): Record evicted, re-forwarded to Mac 2, fetched updated record `192.0.2.20` with fresh `TTL 30`.

### C. Backend Startup & Remote Connectivity Fix
- **Evidence Document:** [evidence/backend/mac3-backend-startup-verification.log](file:///Users/sakshamsontakke/Desktop/untitled%20folder%205/Computer-Networks/evidence/backend/mac3-backend-startup-verification.log)
- **Key Results:**
  - Decoupled process stdin (`< /dev/null`) and added `disown` to ensure persistent daemons surviving shell exits.
  - Verified listeners on `*:3001` and `*:3002`.
  - Verified reachability via loopback (`127.0.0.1`) and LAN interface (`10.200.251.76`).

---

## 6. Comprehensive Troubleshooting Matrix

### A. DNS Subsystem Failures
| Failure Scenario | Detection Command | Expected Symptom | Root Cause | Fix & Verification Command |
| :--- | :--- | :--- | :--- | :--- |
| **Name Resolution Failure** | `dig @10.200.251.106 app.teamX.test` | `connection timed out; no servers could be reached` | `dnsmasq` service stopped on Mac 1 or port 53 blocked. | `sudo brew services restart dnsmasq` on Mac 1; verify with `nc -z -v -w 2 10.200.251.106 53`. |
| **Primary DNS Outage** | `dig @10.200.251.106 app.teamX.test` | Query timeout / SERVFAIL | Mac 1 host down or unreachable on Wi-Fi LAN. | Failover to Backup DNS on Mac 2: `dig @10.200.251.227 app.teamX.test`. |
| **Incorrect A Record** | `dig @10.200.251.106 app.teamX.test +short` | Returns wrong IP (e.g. stale IP from Phase 1) | `dnsmasq.conf` contains outdated IP mapping. | Update `address=/app.teamX.test/10.200.251.227` in `dnsmasq.conf`; reload via `kill -HUP $(pgrep dnsmasq)`. |
| **TTL Cache Delay** | `dig @127.0.0.1 -p 5353 app.teamX.test` | Returns old IP address after upstream change | Resolver cache still holds unexpired record ($TTL > 0$). | Wait for TTL timer to expire, or flush resolver cache via `sudo killall -HUP mDNSResponder` or `kill -HUP <dnsmasq_pid>`. |

### B. TCP Layer Failures
| Failure Scenario | Detection Command | Expected Symptom | Root Cause | Fix & Verification Command |
| :--- | :--- | :--- | :--- | :--- |
| **Connection Refused** | `nc -z -v -w 2 10.200.251.76 3001` | `connectx to 10.200.251.76 port 3001 failed: Connection refused` | Backend process is stopped and not listening on port. | Run `./backend/start-a.sh` on Mac 3; verify with `lsof -iTCP:3001 -sTCP:LISTEN -P -n`. |
| **Connection Timeout** | `nc -z -v -w 2 10.200.251.76 3001` | `Operation timed out` after 2 seconds | Host unreachable, ARP resolution failure, or silent packet drop. | Verify IP reachability via `ping -c 2 10.200.251.76`; verify ARP entry via `arp -n 10.200.251.76`. |
| **Firewall Block** | `curl -i http://10.200.251.76:3001/` | Packet dropped silently (PF drop) or `HTTP 403 Forbidden` | Client IP is not in `<authorized_edges>` or `ALLOWED_IPS`. | Add client IP to `ALLOWED_IPS` in `server.js` or reload PF table: `sudo pfctl -a backend -t authorized_edges -T add <client-ip>`. |

### C. TLS Layer Failures
| Failure Scenario | Detection Command | Expected Symptom | Root Cause | Fix & Verification Command |
| :--- | :--- | :--- | :--- | :--- |
| **Untrusted Certificate** | `curl -i https://app.teamX.test:8443/` | `SSL certificate problem: unable to get local issuer certificate` | Root CA generated via `mkcert` is not installed in macOS Trust Store. | Install root CA: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain rootCA.pem`. |
| **Hostname Mismatch** | `curl -i https://10.200.251.227:8443/` | `SSL: certificate subject name does not match target host name` | Connecting via raw IP address instead of domain name. | Use domain with resolve flag: `curl --resolve app.teamX.test:8443:10.200.251.227 https://app.teamX.test:8443/`. |
| **Expired Certificate** | `openssl s_client -connect 10.200.251.227:8443` | `verify error:num=10:certificate has expired` | Certificate validity period lapsed. | Reissue certificate using `mkcert "app.teamX.test" "api.teamX.test"`; reload nginx via `nginx -s reload`. |

### D. Application & Reverse Proxy Failures
| Failure Scenario | Detection Command | Expected Symptom | Root Cause | Fix & Verification Command |
| :--- | :--- | :--- | :--- | :--- |
| **HTTP 502 Bad Gateway** | `curl -i https://app.teamX.test:8443/` | `HTTP/1.1 502 Bad Gateway` | Both Backend A and Backend B on Mac 3 are stopped simultaneously. | Start backends on Mac 3: `./backend/start-all.sh`; verify with `./backend/health-check.sh`. |
| **HTTP 403 Forbidden** | `curl -i http://10.200.251.76:3001/` | `HTTP/1.1 403 Forbidden` — `{"error":"Forbidden"}` | Ingress attempted from unauthorized IP (bypassing edge proxy). | Route requests through authorized edge proxy (`10.200.251.227` or `10.200.251.106`). |
| **HTTP 404 Not Found** | `curl -i https://app.teamX.test:8443/invalid` | `HTTP/1.1 404 Not Found` — `{"error":"Not Found"}` | Requested URI route is undefined in Express application. | Verify route in `server.js` (`/`, `/api/status`, `/health`). |

---

## 7. Faculty Demonstration Commands

To demonstrate Phase 2 functionality for evaluation, execute the following commands in sequence:

```bash
# 1. Verify Both Backends are Healthy on Mac 3
./backend/health-check.sh

# 2. Demonstrate Round-Robin Load Balancing via Primary Edge (Mac 2)
for i in {1..4}; do
  curl -s -k --resolve app.teamX.test:8443:10.200.251.227 https://app.teamX.test:8443/ | grep -E "backend"
done

# 3. Simulate Backend A Failure
./backend/stop-a.sh

# 4. Verify Traffic Automatically Fails Over to Backend B via Standby Edge (Mac 1)
for i in {1..4}; do
  curl -s -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/ | grep -E "backend"
done

# 5. Restore Backend A
./backend/start-a.sh
./backend/health-check.sh

# 6. Verify Dual-Backend Recovery
for i in {1..4}; do
  curl -s -k --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/ | grep -E "backend"
done
```
