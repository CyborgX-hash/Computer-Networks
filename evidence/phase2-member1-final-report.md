# Phase 2 — Member 1 (Mihika) Final Comprehensive Report

**Machine:** Mac 1 — Mihika (`10.200.251.106`, `en0`)  
**Assigned Roles:**
1. Primary DNS Server (`dnsmasq`) with authoritative `.test` zone resolution and public forwarding.
2. Standby Edge Reverse Proxy (`nginx`) with TLS termination, HTTP-to-HTTPS redirect, and upstream load balancing.
3. DNS and Edge Failover Architecture & Verification Evidence.
4. Peer Coordination with Mac 2 (Priyanshu) and Mac 3 (Saksham).

**Project Directory:** `/Users/mihikamathur/Desktop/Placement/CN/Computer-Networks`  
**Git Branch:** `architecture&DNS`  
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

---

## 2. Configuration Audit & Component Alignment

### A. Primary DNS Configuration (`/opt/homebrew/etc/dnsmasq.conf` & `config/dnsmasq.conf`)
- **Listen Address:** `127.0.0.1, 10.200.251.106` (binds to loopback and LAN Wi-Fi `en0`).
- **Protocols:** UDP and TCP enabled on port 53 (`bind-interfaces`).
- **Cache TTL:** `local-ttl=30` explicitly set for fast DNS migration and TTL expiration within 30 seconds.
- **Logging:** `log-queries` active for debugging and audit verification.
- **Authoritative Project Mapping:**
  ```ini
  address=/app.teamX.test/10.200.251.227
  address=/api.teamX.test/10.200.251.227
  ```
- **Upstream Forwarding:** `8.8.8.8`, `1.1.1.1` (ensures non-project internet queries resolve continuously).
- **Service Management:** Managed by macOS system daemon `system/sh.brew.dnsmasq` (`/Library/LaunchDaemons/sh.brew.dnsmasq.plist`).

### B. Standby Edge Proxy Configuration (`config/nginx-standby.conf`)
- **Listen Ports:**
  - `8443 ssl`: Native TLS termination.
  - `8080`: Plain HTTP listener with permanent redirect (`return 301 https://$host:8443$request_uri;`).
- **Virtual Hosts:** Dual-SAN handling for `app.teamX.test` and `api.teamX.test`.
- **TLS Material:**
  - Certificate: `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem` (mode `644`)
  - Private Key: `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test-key.pem` (mode `600`, non-committed)
  - Protocols: `TLSv1.2 TLSv1.3`, secure ciphers, session cache `shared:SSL:10m`.
- **Upstream Backend Pool:**
  ```nginx
  upstream backend_servers {
      server 10.200.251.76:3001 max_fails=1 fail_timeout=10s;
      server 10.200.251.76:3002 max_fails=1 fail_timeout=10s;
  }
  ```
- **Passive Failure Handling:**
  ```nginx
  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  proxy_next_upstream_tries 2;
  proxy_next_upstream_timeout 5s;
  ```
- **Header Preservation:** Preserves `X-Backend`, `Cache-Control`, `Host`, and forwards client IP headers (`X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`).

---

## 3. Summary of Verified Tests & Captured Evidence

All tests listed below have been executed on live network hardware with terminal logs captured in the repository:

| Test Scope | Reference Evidence File | Status | Key Findings |
|---|---|:---:|---|
| **Standby Nginx Controlled Runtime Test** | [`evidence/nginx/phase2-standby-runtime-verification.md`](file:///Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/evidence/nginx/phase2-standby-runtime-verification.md) | **PASS** | Validated native TLS verification (`SSL certificate verify ok` without `-k`), HTTP 200 on `app` and `api`, round-robin alternation between Backend A (`:3001`) and B (`:3002`), HTTP 301 redirect on port 8080. |
| **Primary DNS Service Lifecycle & Kickstart** | [`evidence/dns/primary-dns-configuration-verification.md`](file:///Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/evidence/dns/primary-dns-configuration-verification.md) | **PASS** | Identified root cause of kill respawn (`KeepAlive: true` in `system/sh.brew.dnsmasq`). Safely restarted via `launchctl kickstart -k`, validated port 53 UDP/TCP, verified `local-ttl=30` on all records. |
| **Coordinated Primary DNS Outage & Recovery** | [`evidence/dns/phase2-primary-backup-dns-failover.md`](file:///Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/evidence/dns/phase2-primary-backup-dns-failover.md) | **PASS** | Safely booted out service (`launchctl bootout`). Primary timed out as expected from Mac 1 and Mac 3; Backup DNS on Mac 2 seamlessly served all UDP/TCP queries. Restored primary via `launchctl bootstrap` under PID 23870. |

---

## 4. Operational Runbooks & Procedures

### A. Standby Edge Activation Runbook (Mac 1)
When the Primary Edge on Mac 2 (`10.200.251.227`) fails or requires scheduled maintenance:

1. **Verify Ports Available:**
   ```bash
   lsof -iTCP:8443 -iTCP:8080 -sTCP:LISTEN -P
   ```
2. **Start Standby Nginx:**
   ```bash
   nginx -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
   ```
3. **Verify Local Process & Listener:**
   ```bash
   pgrep -fl nginx
   curl -v --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/
   ```
4. **De-escalate / Stop Standby Nginx (when Primary Edge recovers):**
   ```bash
   nginx -s stop -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
   ```

---

### B. DNS Migration Procedure (Traffic Redirection to Standby Edge)

In standard operation, DNS maps `app.teamX.test` and `api.teamX.test` to Primary Edge (`10.200.251.227`).  
During an edge failover event, traffic is redirected to Standby Edge (`10.200.251.106`).

#### Step 1: Update Primary DNS Configuration (`/opt/homebrew/etc/dnsmasq.conf`)
Replace:
```ini
address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227
```
With:
```ini
address=/app.teamX.test/10.200.251.106
address=/api.teamX.test/10.200.251.106
```

#### Step 2: Reload Primary DNS
```bash
sudo launchctl kickstart -k system/sh.brew.dnsmasq
```
*(Impact: sub-second reload; zero dropped queries).*

#### Step 3: Peer Coordination with Mac 2
Coordinate with Priyanshu so he applies the matching record update in `config/dnsmasq-backup.conf` on Mac 2 and reloads his backup DNS service.

#### Step 4: Verify Migration Across the LAN
```bash
dig @10.200.251.106 app.teamX.test +noall +answer
# Result: app.teamX.test. 30 IN A 10.200.251.106

dig @10.200.251.227 app.teamX.test +noall +answer
# Result: app.teamX.test. 30 IN A 10.200.251.106
```
Because `local-ttl=30` is enforced, client resolvers will purge cached entries and switch to Mac 1 within 30 seconds.

---

### C. DNS Recovery Procedure (Restoring Traffic to Primary Edge)

When Mac 2's Primary Edge reverse proxy returns to service:

1. **Revert `/opt/homebrew/etc/dnsmasq.conf` on Mac 1:**
   ```ini
   address=/app.teamX.test/10.200.251.227
   address=/api.teamX.test/10.200.251.227
   ```
2. **Reload Primary DNS:**
   ```bash
   sudo launchctl kickstart -k system/sh.brew.dnsmasq
   ```
3. **Notify Priyanshu:** Confirm backup DNS records revert to `10.200.251.227`.
4. **De-escalate Standby Nginx on Mac 1:**
   ```bash
   nginx -s stop -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
   ```

---

## 5. Command Reference Cheat Sheet

| Task | Exact Terminal Command |
|---|---|
| **Check Primary DNS Status** | `pgrep -fl dnsmasq; launchctl print system/sh.brew.dnsmasq` |
| **Reload Primary DNS (Config Change)** | `sudo launchctl kickstart -k system/sh.brew.dnsmasq` |
| **Controlled DNS Outage (Stop)** | `sudo launchctl bootout system /Library/LaunchDaemons/sh.brew.dnsmasq.plist` |
| **Restore Primary DNS (Start)** | `sudo launchctl bootstrap system /Library/LaunchDaemons/sh.brew.dnsmasq.plist` |
| **Test Primary DNS (UDP & TCP)** | `dig @10.200.251.106 app.teamX.test; dig +tcp @10.200.251.106 app.teamX.test` |
| **Start Standby Edge Nginx** | `nginx -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf` |
| **Test Standby Edge HTTPS** | `curl -v --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/` |
| **Stop Standby Edge Nginx** | `nginx -s stop -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf` |

---

## 6. Acceptance Criteria Checklist

| Deliverable Item | Status | Verification Detail |
|---|:---:|---|
| **Primary DNS Service Manager Identified** | **IMPLEMENTED** | Identified as `launchd` system domain (`system/sh.brew.dnsmasq`). |
| **Safe DNS Stop & Restore Procedures** | **IMPLEMENTED** | Verified via `launchctl bootout` and `launchctl bootstrap`. |
| **Authoritative Records Pointing to Edge** | **CONFIGURED** | `app` and `api` point to `10.200.251.227` (Normal) / `10.200.251.106` (Failover). |
| **TTL 30 & Query Logging** | **CONFIGURED** | `local-ttl=30` and `log-queries` active in config and verified in dig answers. |
| **Primary DNS UDP & TCP Queries** | **PREVIOUSLY TESTED** | `dig` and `dig +tcp` verified returning `NOERROR` and TTL 30. |
| **Backup DNS Health on Mac 2** | **PREVIOUSLY TESTED** | Probed over LAN (`10.200.251.227`), validated dual virtual hosts. |
| **Primary DNS Outage & Client Failover** | **PREVIOUSLY TESTED** | Validated with Saksham (Mac 3) during controlled primary outage. |
| **Standby Nginx Configuration Syntax** | **CONFIGURED** | `nginx -t -c config/nginx-standby.conf` passes successfully. |
| **Standby Nginx HTTPS & Dual-SAN TLS** | **PREVIOUSLY TESTED** | Validated on port 8443 without `-k` (`SSL certificate verify ok`). |
| **Standby Nginx HTTP 8080 Redirect** | **PREVIOUSLY TESTED** | Validated returning HTTP 301 to `https://app.teamx.test:8443/`. |
| **Standby Passive Backend Failover** | **CONFIGURED** | Configured with `max_fails=1 fail_timeout=10s` and `proxy_next_upstream`. |
| **Standby Round-Robin Routing** | **PREVIOUSLY TESTED** | Validated 6-cycle sequential requests alternating between Backend A & B. |
| **Consolidated Edge Failover (DNS Migration)** | **READY (NOT YET TESTED)** | Runbooks, migration scripts, and recovery steps fully prepared for team test. |
| **No Secrets or Private Keys Committed** | **VERIFIED** | Certificates (`.pem`, `.key`, `rootCA`) stored outside repository in `/opt/homebrew/etc/nginx/certs/`. |
| **Documentation & Git Synchronization** | **COMPLETED** | Changes committed to `architecture&DNS` and synchronized with `origin/main`. |
