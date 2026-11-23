# Phase 2 — Final Project Submission Summary

**Project:** Private Network Service Platform  
**Phase:** Phase 2 (High Availability, Redundancy, Security & Verification)  
**Date of Submission:** 2026-11-23  
**Team Members:**
- **Member 1 (Mac 1 — `10.200.251.106`):** Mihika (Primary DNS, Standby Nginx Edge, Test Client)
- **Member 2 (Mac 3 — `10.200.251.76`):** Saksham (Backend A & B, Ingress Security, PF Firewall Prep, TTL Cache Resolver)
- **Member 3 (Mac 2 — `10.200.251.227`):** Priyanshu (Primary Nginx Edge, TLS Terminator, Load Balancer, Backup DNS)

---

## 1. What Was Implemented

1. **Dual DNS High Availability**:
   - Primary authoritative DNS (`dnsmasq`) on Mac 1 (`10.200.251.106:53`).
   - Backup authoritative DNS (`dnsmasq`) on Mac 2 (`10.200.251.227:53`).
   - Local record caching and authoritative TTL configured to 30 seconds (`local-ttl=30`).
2. **Dual Edge Reverse Proxy Ingress**:
   - Primary Nginx reverse proxy on Mac 2 (`10.200.251.227:8443`) terminating TLS for `app.teamX.test` and `api.teamX.test`.
   - Standby Nginx reverse proxy on Mac 1 (`10.200.251.106:8443`) with mirrored upstream configuration.
   - HTTP port 8080 redirect to HTTPS port 8443 (`HTTP 301 Moved Permanently`).
3. **Dual Upstream Backend Microservices**:
   - Backend Instance A on Mac 3 (`10.200.251.76:3001`) injecting `X-Backend: A`.
   - Backend Instance B on Mac 3 (`10.200.251.76:3002`) injecting `X-Backend: B`.
   - Standardized `GET /health` endpoint returning HTTP 200 with JSON payload.
   - Daemon lifecycle scripts with process persistence (`start-all.sh`, `stop-all.sh`, `start-a.sh`, `stop-a.sh`, `start-b.sh`, `stop-b.sh`, `health-check.sh`).
4. **Multi-Layer Access Control & Security**:
   - Application-layer IP whitelisting in Express middleware (`ALLOWED_IPS` restricting access to `127.0.0.1`, `10.200.251.106`, `10.200.251.227`).
   - Network-layer scoped Packet Filter anchor configuration in `config/pf_backend.rules` with non-destructive rollback.
5. **DNS TTL Caching Experiment Resolver**:
   - Isolated `dnsmasq` resolver on Mac 3 (`127.0.0.1:5353`) configured with upstream `10.200.251.227` to evaluate TTL countdown and cache eviction.

---

## 2. What Was Tested & Verified

1. **DNS Direct Query & Failover**:
   - Both Primary and Backup DNS return identical A-records pointing to Primary Edge (`10.200.251.227`) with TTL 30.
   - Primary DNS outage simulated via `launchctl bootout`; direct queries to Backup DNS answered in 0ms without delay.
2. **DNS TTL 30-Second Caching & Expiry**:
   - Query 1 at 15:44:36 forwarded to upstream `10.200.251.227` (response `192.0.2.10`, TTL 30).
   - Query 2 at 15:44:44 served from local cache with TTL countdown (TTL 22, 0ms query time).
   - Upstream record updated to `192.0.2.20`.
   - Query 3 at 15:47:14 fetched updated record after cache expiration.
3. **Primary & Standby Edge TLS Termination**:
   - Strict TLS 1.3 / AES-256-GCM verification (`SSL certificate verify ok`) with no `-k` bypass flag.
   - Insecure HTTP port 8080 redirected to HTTPS port 8443.
4. **Upstream Load Balancing & Failover**:
   - Round-robin alternating distribution (`X-Backend: A` and `X-Backend: B`) verified.
   - Backend A outage simulated: 12/12 consecutive requests routed through Backend B with 0 failed requests.
   - Backend B outage simulated: 12/12 consecutive requests routed through Backend A with 0 failed requests.
   - Recovery of stopped backends immediately restored alternating round-robin distribution.
5. **Backend Security Whitelist & Kernel PF Enforcement**:
   - Localhost and authorized edge nodes (`10.200.251.106`, `10.200.251.227`) successfully connect and receive HTTP 200.
   - Non-whitelisted IP addresses receive `HTTP 403 Forbidden` at L7 and kernel-level drops at L4.
   - Scoped anchor `com.apple/backend` activated into kernel, rule table verified, and cleanly rolled back.
6. **Live Edge Failover & Dynamic DNS Migration**:
   - Primary Nginx stopped on Mac 2; Standby Nginx active on Mac 1.
   - DNS dynamically updated on Mac 1 to `10.200.251.106`.
   - Mac 1 and Mac 2 successfully issued requests across the physical LAN to Standby Edge (`:8443`), receiving `HTTP 200 OK` from Backend A and B.
   - Primary Nginx restored on Mac 2 and confirmed listening on `:8443`.

---

## 3. Quantitative Test Results

- **Total Test Cases Evaluated:** 22
- **Passed (PASS):** 22 (100.0%)
- **Not Verified (NOT VERIFIED):** 0 (0.0%)
- **Failed (FAIL):** 0 (0.0%)
- **Blocked (BLOCKED):** 0 (0.0%)

---

## 4. What Remains Unverified

- **None.** All 22 test scenarios across DNS, TCP/Network, TLS/HTTPS, Application, and Edge Failover layers have been physically executed and verified with raw command outputs in the evidence catalog.

---

## 5. Known Limitations

1. **macOS Sequoia Local Network Privacy (TCC)**:
   - Subshells launched by unentitled applications or IDE processes trigger `EHOSTUNREACH` ("No route to host") for private RFC 1918 LAN IPs. Network commands must run through native `Terminal.app` or with appropriate entitlements.
2. **OS-Level Resolver Timeout vs Server Redundancy**:
   - Direct DNS failover to the backup server operates in 0ms. However, operating systems querying `/etc/resolv.conf` serially wait for a 2-5 second timeout before falling back from Primary to Backup nameservers.
3. **Isolated TTL Resolver Scope**:
   - The DNS TTL countdown and eviction were verified using an isolated `dnsmasq` instance on port 5353 to avoid interfering with system-wide macOS mDNSResponder caching.

---

## 6. Repository Integrity & Git Commit

- **Target Branch:** `main` (synchronized with `origin/main`)
- **Member Branch:** `Backend-Servers` (merged via PR #15)
- **Latest Commit on Main:** `c968740` (and subsequent documentation commit)
- **Hygiene Audit:** 0 private keys, 0 root CA keys, 0 `.env` files, 0 runtime PID files committed. Working tree clean.
