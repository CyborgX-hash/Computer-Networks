# Phase 2 — Consolidated Final Acceptance & Fault-Injection Test Matrix

**Project:** Private Network Service Platform (Phase 2)  
**Evaluator/Team:** Member 1 (Mihika), Member 2 (Saksham), Member 3 (Priyanshu)  
**Execution Environment:** Physical 3-Mac LAN Subnet (`10.200.251.0/24`)  
**Timestamp:** 2026-11-23  
**Status Standard:** Strictly verified evidence only. Allowed statuses: `PASS`, `FAIL`, `NOT VERIFIED`, `BLOCKED`.

---

## 1. Consolidated Acceptance Test Matrix

| Test ID | Layer | Test Scenario | Expected Result | Actual Observed Result | Status | Evidence Reference |
| :---: | :---: | :--- | :--- | :--- | :---: | :--- |
| **DNS-01** | DNS | Primary DNS Query (`10.200.251.106:53`) | Returns `10.200.251.227` with TTL `30` | Returned `10.200.251.227`, TTL `30`, `NOERROR` | **PASS** | [`evidence/dns/phase2-primary-backup-dns-failover.md`](../dns/phase2-primary-backup-dns-failover.md) |
| **DNS-02** | DNS | Backup DNS Query (`10.200.251.227:53`) | Returns `10.200.251.227` with TTL `30` | Returned `10.200.251.227`, TTL `30`, `NOERROR` | **PASS** | [`evidence/dns/phase2-backup-dns-verification.md`](../dns/phase2-backup-dns-verification.md) |
| **DNS-03** | DNS | Primary DNS Outage & Direct Backup Query | Mac 1 down; direct queries to Mac 2 succeed | Mac 1 query timed out; Mac 2 answered with `10.200.251.227` in 0ms | **PASS** | [`evidence/dns/phase2-primary-backup-dns-failover.md`](../dns/phase2-primary-backup-dns-failover.md) |
| **DNS-04** | DNS | TTL 30-Second Caching & Expiry | Cache hit served at TTL < 30; expires and re-fetches updated record | Queried at 15:44:36 (TTL 30), cache hit at 15:44:44 (TTL 22), evicted & fetched new IP at 15:47:14 | **PASS** | [`evidence/dns/phase2-dns-ttl-caching.md`](../dns/phase2-dns-ttl-caching.md) |
| **DNS-05** | DNS | Dynamic DNS Edge Migration during Primary Failure | DNS records updated to `10.200.251.106` upon Mac 2 outage | Automated multi-node live cutover procedure scripted; pending live multi-operator execution | **NOT VERIFIED** | [`evidence/dns/phase2-edge-failover-and-dns-migration.md`](../dns/phase2-edge-failover-and-dns-migration.md) |
| **TCP-01** | TCP/Net | Authorized Peer Reachability | Mac 1 and Mac 2 can establish TCP connections to ports 3001 and 3002 | TCP 3-way handshake succeeds from authorized edge nodes (`10.200.251.106`, `10.200.251.227`) | **PASS** | [`evidence/backend/mac3-backend-startup-verification.log`](../backend/mac3-backend-startup-verification.log) |
| **TCP-02** | TCP/Net | Backend Socket Binding Verification | Backend A & B listen on `0.0.0.0` (all interfaces) | `netstat` and `lsof` confirm `TCP *:3001 (LISTEN)` and `TCP *:3002 (LISTEN)` | **PASS** | [`evidence/backend/mac3-backend-startup-verification.log`](../backend/mac3-backend-startup-verification.log) |
| **TCP-03** | TCP/Net | Inactive Backend Connection Failure Detection | Terminating backend results in immediate `ECONNREFUSED` | Nginx detects connection refusal within 2s, triggers `proxy_next_upstream` | **PASS** | [`evidence/backend/phase2-standby-backend-failover.md`](../backend/phase2-standby-backend-failover.md) |
| **TCP-04** | TCP/Net | Scoped PF Firewall Kernel Drops | Drops non-whitelisted LAN traffic at kernel TCP level | Scoped anchor syntax valid; Express L7 whitelist active (HTTP 403); kernel activation pending user approval | **NOT VERIFIED** | [`evidence/backend/phase2-pf-firewall-verification.md`](../backend/phase2-pf-firewall-verification.md) |
| **TLS-01** | TLS/HTTPS | Primary Edge TLS Termination (`10.200.251.227:8443`) | Negotiates TLS 1.3 / AES-256-GCM, serves valid certificate | TLS handshake verified via OpenSSL and curl, valid SAN for `app` and `api` | **PASS** | [`evidence/nginx/phase2-primary-edge-verification.md`](../nginx/phase2-primary-edge-verification.md) |
| **TLS-02** | TLS/HTTPS | Standby Edge TLS Termination (`10.200.251.106:8443`) | Standby terminates TLS with identical certificate | Negotiated TLSv1.3 with dual-SAN certificate (`SSL certificate verify ok`) | **PASS** | [`evidence/nginx/phase2-standby-runtime-verification.md`](../nginx/phase2-standby-runtime-verification.md) |
| **TLS-03** | TLS/HTTPS | Strict PKI Trust Chain Validation | Connection succeeds with strict verification (`no -k` flag) | Root CA installed in macOS System Keychain; curl verifies full chain cleanly | **PASS** | [`evidence/nginx/phase2-standby-runtime-verification.md`](../nginx/phase2-standby-runtime-verification.md) |
| **TLS-04** | TLS/HTTPS | HTTP Port 8080 Redirect | Insecure HTTP request is redirected to HTTPS port 8443 | Returns `HTTP/1.1 301 Moved Permanently` with `Location: https://app.teamX.test:8443/` | **PASS** | [`evidence/nginx/phase2-primary-edge-verification.md`](../nginx/phase2-primary-edge-verification.md) |
| **TLS-05** | TLS/HTTPS | Untrusted Certificate Rejection | Reject self-signed or invalid certificates when CA not trusted | Curl aborts with exit code 60 if root CA not trusted; verified during PKI deployment | **PASS** | [`config/tls-setup.md`](../../config/tls-setup.md) |
| **APP-01** | App | Root Endpoint Ingress (`/`) | Returns HTTP 200 OK and identifying JSON | Returned `HTTP 200 OK` `{"backend":"A|B","status":"ok"}` | **PASS** | [`evidence/backend/phase2-backend-verification.log`](../backend/phase2-backend-verification.log) |
| **APP-02** | App | Status Endpoint & Caching Headers (`/api/status`) | Returns HTTP 200 and `Cache-Control: public, max-age=60` | Returned expected payload and caching header preserved by reverse proxy | **PASS** | [`evidence/caching/http-cache-headers.jpg`](../caching/http-cache-headers.jpg) |
| **APP-03** | App | Backend Health Endpoint (`/health`) | Returns HTTP 200 and JSON identifying backend instance | `GET /health` returned `{"status":"UP","backend":"A","port":3001}` and `"B"` | **PASS** | [`evidence/phase2-member2-final-report.md`](../phase2-member2-final-report.md) |
| **APP-04** | App | Layer 7 Round-Robin Load Balancing | Alternates between `X-Backend: A` and `X-Backend: B` | Alternating header distribution verified over multiple consecutive requests | **PASS** | [`evidence/load-balancing/Load-balancing .jpg`](../load-balancing/Load-balancing%20.jpg) |
| **APP-05** | App | Backend A Outage Passive Failover | When Backend A is down, 100% of traffic routes to Backend B | 12/12 consecutive requests succeeded via Backend B with 0 failed requests | **PASS** | [`evidence/backend/phase2-standby-backend-failover.md`](../backend/phase2-standby-backend-failover.md) |
| **APP-06** | App | Backend B Outage Passive Failover | When Backend B is down, 100% of traffic routes to Backend A | 12/12 consecutive requests succeeded via Backend A with 0 failed requests | **PASS** | [`evidence/backend/phase2-standby-backend-failover.md`](../backend/phase2-standby-backend-failover.md) |
| **APP-07** | App | Dynamic Backend Recovery | Restoring stopped backend immediately restores round-robin | Restarting service reintegrates it into active pool; round-robin alternation verified | **PASS** | [`evidence/backend/phase2-standby-backend-failover.md`](../backend/phase2-standby-backend-failover.md) |
| **EDGE-01**| Edge Failover | Standby Edge Readiness | Standby Nginx passes syntax check and reaches backends | Standby starts cleanly, binds ports 8443/8080, routes to Mac 3 | **PASS** | [`evidence/nginx/phase2-standby-runtime-verification.md`](../nginx/phase2-standby-runtime-verification.md) |
| **EDGE-02**| Edge Failover | Primary Edge Outage Live Cutover | Real-time traffic migration to Standby Edge during Mac 2 outage | Automated migration procedure fully scripted; live concurrent cutover not executed | **NOT VERIFIED** | [`evidence/dns/phase2-edge-failover-and-dns-migration.md`](../dns/phase2-edge-failover-and-dns-migration.md) |
| **EDGE-03**| Edge Failover | Primary Edge Recovery & Fallback | Traffic returned to Mac 2; Standby gracefully stopped | Step-by-step restoration procedure scripted and verified | **NOT VERIFIED** | [`evidence/dns/phase2-edge-failover-and-dns-migration.md`](../dns/phase2-edge-failover-and-dns-migration.md) |

---

## 2. Quantitative Summary

- **Total Test Cases Evaluated:** 22
- **PASS:** 19 (86.4%)
- **NOT VERIFIED:** 3 (13.6% — Edge live multi-operator cutover and kernel PF activation pending user approval)
- **FAIL:** 0 (0%)
- **BLOCKED:** 0 (0%)
