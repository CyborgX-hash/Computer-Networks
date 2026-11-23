# Phase 2 — Member 3 (Priyanshu) Final Comprehensive Report

**Machine:** Mac 2 — Priyanshu (`10.200.251.227`, `en0`)  
**Assigned Roles:**
1. **Primary Edge Reverse Proxy (`nginx`):** TLS termination (`:8443`), HTTP-to-HTTPS redirect (`:8080`), dual virtual host routing (`app.teamX.test`, `api.teamX.test`), round-robin load balancing across Backend A (`:3001`) and Backend B (`:3002`) on Mac 3 (`10.200.251.76`), passive health checks, and header preservation.
2. **Backup DNS Server (`dnsmasq`):** Dedicated backup DNS server on port 53 (UDP & TCP), authoritative resolution for `.test` zone pointing to Primary Edge (`10.200.251.227`), `local-ttl=30`, public upstream forwarding (`8.8.8.8`, `1.1.1.1`).
3. **DNS Migration & Recovery Architect:** Runbooks and operational procedures for shifting traffic between Primary Edge (`10.200.251.227`) and Standby Edge (`10.200.251.106`) during edge outages.
4. **Peer Coordination:** Alignment with Member 1 (Mihika — Primary DNS & Standby Edge) and Member 2 (Saksham — Backend Node).

**Project Directory:** `/Users/priyanshuagrahari/Desktop/Computer-Networks`  
**Git Branch:** `Configuration`  
**Execution Date:** November 23, 2026  

---

## 1. Network Topology & Member 3 Placement

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

### A. Primary Edge NGINX Configuration (`config/nginx.conf`)

The configuration file is maintained in the repository at [config/nginx.conf](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/config/nginx.conf) and mirrored to `/opt/homebrew/etc/nginx/nginx.conf`.

1. **Global & Process Management:**
   - Worker processes: `1` (unprivileged user `priyanshuagrahari`).
   - Dedicated PID file: `/opt/homebrew/var/run/nginx_edge.pid`.
   - Max worker connections: `128`.

2. **Upstream Backend Pool (`backend_servers`):**
   ```nginx
   upstream backend_servers {
       server 10.200.251.76:3001 max_fails=1 fail_timeout=10s;
       server 10.200.251.76:3002 max_fails=1 fail_timeout=10s;
   }
   ```
   - Target nodes verified: Backend A (`10.200.251.76:3001`) and Backend B (`10.200.251.76:3002`).
   - Native passive health checks: `max_fails=1` marks a backend inactive upon a single failure, removing it for `fail_timeout=10s`.

3. **Virtual Hosts & TLS Termination (Port 8443):**
   - Directives: `listen 8443 ssl;`
   - Server names: `app.teamX.test` and `api.teamX.test`
   - Certificate path: `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem`
   - Private key path: `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test-key.pem`
   - Protocols: `TLSv1.2 TLSv1.3`
   - Cipher suite: `HIGH:!aNULL:!MD5; ssl_prefer_server_ciphers on;`

4. **Upstream Resilience & Header Preservation:**
   ```nginx
   proxy_connect_timeout     2s;
   proxy_read_timeout        5s;
   proxy_next_upstream       error timeout invalid_header http_500 http_502 http_503 http_504;
   proxy_next_upstream_tries 2;

   proxy_set_header Host              $host;
   proxy_set_header X-Real-IP         $remote_addr;
   proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   ```
   - Retries the secondary backend immediately upon upstream error or timeout without returning 502/504 to the client.
   - Preserves backend headers (`X-Backend: A/B`, `Cache-Control: public, max-age=60`).

5. **HTTP to HTTPS Redirection (Port 8080):**
   ```nginx
   server {
       listen       8080;
       server_name  app.teamX.test api.teamX.test;
       return 301 https://$host:8443$request_uri;
   }
   ```
   - Redirects plain HTTP requests permanently (301) to the secure endpoint on port 8443.

---

### B. Backup DNS Server Configuration (`config/dnsmasq-backup.conf`)

Maintained at [config/dnsmasq-backup.conf](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf):

```ini
port=53
domain=test
local=/teamX.test/

listen-address=127.0.0.1,10.200.251.227
bind-interfaces

# Authoritative project records pointing to Primary Edge
address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227

# TTL configured to 30s for rapid migration
local-ttl=30

# Isolated resolver behavior
no-hosts
no-resolv
server=8.8.8.8
server=1.1.1.1

# Logging and cache
log-queries
cache-size=1000
```

1. **Port & Interface Binding:**
   - Listens on `127.0.0.1` and `10.200.251.227` on UDP and TCP port 53.
   - `bind-interfaces` prevents interface collision with other network services.
2. **Authoritative Mappings:**
   - `app.teamX.test` -> `10.200.251.227` (Primary Edge)
   - `api.teamX.test` -> `10.200.251.227` (Primary Edge)
3. **TTL Enforcement:** `local-ttl=30` guarantees fast TTL expiration for DNS failover and migration tests.
4. **Internet Forwarding:** `server=8.8.8.8` and `server=1.1.1.1` ensure non-project domains continue to resolve transparently.

---

## 3. Summary of Verified Tests & Captured Evidence

| Test Scope | Reference Evidence File | Status | Key Verification Output |
|---|---|:---:|---|
| **Primary NGINX Runtime Verification** | [`evidence/nginx/phase2-primary-edge-verification.md`](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/nginx/phase2-primary-edge-verification.md) | **PASS** | Native TLS verification (`SSL certificate verify ok`), HTTP 200 on `app` and `api`, round-robin 50/50 alternation between Backend A and Backend B, HTTP 301 redirect on port 8080. |
| **Integrated NGINX Live Script** | [`evidence/nginx/live-verification.sh`](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/nginx/live-verification.sh) | **PASS** | Executed 10 consecutive requests; confirmed strict alternating sequence (`A, B, A, B, A, B, A, B, A, B`), sub-15ms response times. |
| **Backend Passive Failover Verification** | [`evidence/nginx/phase2-nginx-verification.log`](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/nginx/phase2-nginx-verification.log) | **PASS** | Validated 100% routing to Backend B when A was offline; 100% routing to Backend A when B was offline; 0 client errors. |
| **Backup DNS Service & Sockets** | [`evidence/dns/phase2-backup-dns-verification.md`](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/dns/phase2-backup-dns-verification.md) | **PASS** | `dnsmasq` PID 78501 active under `nobody`. Verified UDP & TCP port 53 listening on `127.0.0.1` and `10.200.251.227`. |
| **Backup DNS Query Resolution & TTL** | [`evidence/dns/test-backup-dns.sh`](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/dns/test-backup-dns.sh) | **PASS** | `dig` and `dig +tcp` on localhost and LAN IP returned `10.200.251.227` with exact `TTL 30`. |
| **Primary DNS Outage Failover** | [`evidence/dns/phase2-primary-backup-dns-failover.md`](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/dns/phase2-primary-backup-dns-failover.md) | **PASS** | During primary DNS outage on Mac 1, Mac 2 backup DNS handled all queries from Mac 3 and Mac 1 with 0 packet drops. |

---

## 4. Operational Runbooks & Procedures

### A. Safe NGINX Control Procedures (Decoupled from Backup DNS)

A critical architectural guarantee of Mac 2 is the complete isolation of NGINX from Backup DNS (`dnsmasq`):
- **NGINX:** Runs as unprivileged user `priyanshuagrahari` (ports 8080, 8443 > 1024). Master PID: `70698`, Worker PID: `71212`. Managed via `/opt/homebrew/var/run/nginx_edge.pid`.
- **dnsmasq:** Runs as a detached system daemon under user `nobody` (PID `78501`) binding privileged port 53.
- **Process Decoupling Rule:** Stopping or restarting NGINX *never* stops or disrupts `dnsmasq`.

#### Commands:

1. **Verify Services Before Any Action:**
   ```bash
   ps aux | grep -E "nginx|dnsmasq" | grep -v grep
   ```

2. **Safe NGINX Stop (Graceful):**
   ```bash
   # Method 1: Using nginx signal
   nginx -s stop

   # Method 2: Targeted PID termination
   kill -QUIT $(cat /opt/homebrew/var/run/nginx_edge.pid)
   ```
   *Verification:*
   ```bash
   # Confirm NGINX is stopped:
   pgrep -fl nginx    # (Returns empty)

   # Confirm Backup DNS remains running uninterrupted:
   pgrep -fl dnsmasq  # (Returns PID 78501)
   dig @127.0.0.1 app.teamX.test +noall +answer # (Returns 10.200.251.227)
   ```

3. **Safe NGINX Start:**
   ```bash
   # Pre-flight syntax validation:
   nginx -t

   # Start NGINX with project configuration:
   nginx -c /Users/priyanshuagrahari/Desktop/Computer-Networks/config/nginx.conf
   ```
   *Verification:*
   ```bash
   curl -k -i https://127.0.0.1:8443/
   ```

4. **Safe NGINX Reload (Zero Downtime Config Update):**
   ```bash
   nginx -s reload
   ```

---

### B. DNS Migration Procedure (Traffic Redirection to Standby Edge `10.200.251.106`)

During a primary edge failure on Mac 2 (`10.200.251.227`), traffic must be redirected to Mac 1 (`10.200.251.106`).

```
                    BEFORE FAILOVER (NORMAL)
Client Queries ───> DNS (Primary/Backup) ───> 10.200.251.227 (Mac 2 Primary Edge)

                    DURING FAILOVER (MIGRATION)
Client Queries ───> DNS (Primary/Backup) ───> 10.200.251.106 (Mac 1 Standby Edge)
```

#### Step 1: Coordinate with Mihika (Primary DNS Owner)
Mihika modifies `/opt/homebrew/etc/dnsmasq.conf` on Mac 1:
```ini
address=/app.teamX.test/10.200.251.106
address=/api.teamX.test/10.200.251.106
```
Mihika reloads Primary DNS:
```bash
sudo launchctl kickstart -k system/sh.brew.dnsmasq
```

#### Step 2: Update Backup DNS on Mac 2
Priyanshu updates `config/dnsmasq-backup.conf`:
```ini
address=/app.teamX.test/10.200.251.106
address=/api.teamX.test/10.200.251.106
```
Validate syntax:
```bash
/opt/homebrew/sbin/dnsmasq --test -C config/dnsmasq-backup.conf
```
Restart backup dnsmasq:
```bash
sudo kill 78501
sudo /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
```

#### Step 3: Mihika Activates Standby NGINX on Mac 1
```bash
nginx -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
```

#### Step 4: Verification of DNS Convergence
Due to `local-ttl=30`, all cached records across client machines expire within 30 seconds:
```bash
dig @10.200.251.106 app.teamX.test +noall +answer
# Result: app.teamX.test. 30 IN A 10.200.251.106

dig @10.200.251.227 app.teamX.test +noall +answer
# Result: app.teamX.test. 30 IN A 10.200.251.106
```

---

### C. DNS Restoration Procedure (Restoring Traffic to Primary Edge `10.200.251.227`)

When Mac 2's Primary Edge proxy recovers and is ready to resume service:

#### Step 1: Verify Primary Edge Health
```bash
nginx -t
curl -k -i https://127.0.0.1:8443/
```
Confirm both backends respond normally.

#### Step 2: Coordinate with Mihika (Revert Primary DNS)
Mihika reverts `/opt/homebrew/etc/dnsmasq.conf` to `10.200.251.227`:
```ini
address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227
```
Mihika reloads Primary DNS:
```bash
sudo launchctl kickstart -k system/sh.brew.dnsmasq
```

#### Step 3: Revert Backup DNS on Mac 2
Priyanshu reverts `config/dnsmasq-backup.conf`:
```ini
address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227
```
Restart backup dnsmasq:
```bash
sudo kill $(pgrep -f "dnsmasq-backup.conf")
sudo /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
```

#### Step 4: De-escalate Standby NGINX on Mac 1
Mihika shuts down Standby NGINX:
```bash
nginx -s stop -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
```

#### Step 5: Verification of Restored State
```bash
dig @10.200.251.106 app.teamX.test +noall +answer
# Result: app.teamX.test. 30 IN A 10.200.251.227

dig @10.200.251.227 app.teamX.test +noall +answer
# Result: app.teamX.test. 30 IN A 10.200.251.227
```

---

## 5. Command Reference Cheat Sheet (Mac 2 — Priyanshu)

| Task | Command |
|---|---|
| **Check All Running Services** | `ps aux \| grep -E "nginx\|dnsmasq" \| grep -v grep` |
| **Check Port 53 Sockets** | `netstat -an \| grep '\.53 '` |
| **Check Ports 8443 & 8080** | `netstat -an \| grep -E '\.(8443\|8080) '` |
| **Validate NGINX Syntax** | `nginx -t` |
| **Start Primary NGINX** | `nginx -c /Users/priyanshuagrahari/Desktop/Computer-Networks/config/nginx.conf` |
| **Stop Primary NGINX** | `nginx -s stop` (or `kill -QUIT $(cat /opt/homebrew/var/run/nginx_edge.pid)`) |
| **Reload Primary NGINX** | `nginx -s reload` |
| **Validate Backup DNS Syntax** | `/opt/homebrew/sbin/dnsmasq --test -C config/dnsmasq-backup.conf` |
| **Query Backup DNS (UDP)** | `dig @10.200.251.227 app.teamX.test +noall +answer` |
| **Query Backup DNS (TCP)** | `dig +tcp @10.200.251.227 app.teamX.test +noall +answer` |
| **Live NGINX Verification Script** | `bash evidence/nginx/live-verification.sh` |
| **Live Backup DNS Verification Script** | `bash evidence/dns/test-backup-dns.sh` |

---

## 6. Acceptance Criteria Checklist

| Deliverable Item | Status | Verification Detail |
|---|:---:|---|
| **Primary NGINX Upstream Configuration** | **IMPLEMENTED** | Upstreams point to `10.200.251.76:3001` and `10.200.251.76:3002`. |
| **Dual Virtual Hosts (Port 8443)** | **IMPLEMENTED** | `app.teamX.test` and `api.teamX.test` terminate TLS securely. |
| **Dual-SAN TLS Certificate** | **IMPLEMENTED** | Valid until Feb 23, 2029; covers both SANs; modulus match verified. |
| **HTTP 8080 Redirect to HTTPS 8443** | **IMPLEMENTED** | Verified returning HTTP 301 `Location: https://app.teamx.test:8443/`. |
| **Round-Robin Load Balancing** | **PREVIOUSLY TESTED** | Verified 10-request round-robin alternation (5 to Backend A, 5 to Backend B). |
| **Passive Backend Health Checks** | **PREVIOUSLY TESTED** | `max_fails=1 fail_timeout=10s` and `proxy_next_upstream` tested with 0 client errors. |
| **Backend Header Preservation** | **IMPLEMENTED** | `X-Backend` and `Cache-Control` passed through to client intact. |
| **Backup DNS Dedicated Service** | **IMPLEMENTED** | Installed `dnsmasq` 2.93 running under `nobody` (PID 78501) on port 53. |
| **Backup DNS Authoritative Mappings** | **CONFIGURED** | `app` and `api` point to `10.200.251.227` with `local-ttl=30`. |
| **Backup DNS UDP & TCP Queries** | **PREVIOUSLY TESTED** | Verified via `dig` and `dig +tcp` on `127.0.0.1` and `10.200.251.227`. |
| **Primary DNS Outage Resilience** | **PREVIOUSLY TESTED** | Seamless failover tested with Mac 1 and Mac 3 during controlled primary outage. |
| **Process Decoupling (NGINX vs DNS)** | **VERIFIED** | NGINX stops/starts independently of `dnsmasq`; no shared resources or parentage. |
| **DNS Migration & Recovery Runbooks** | **READY** | Complete step-by-step procedures documented for planned edge failover. |
| **Disruptive Primary Edge Outage Test** | **PENDING** | Runbook prepared; awaiting coordinated team execution during final acceptance. |
| **No Secrets or Private Keys Committed** | **VERIFIED** | Certificates (`.pem`, `.key`, `rootCA`) excluded from Git tracking. |
| **Git Synchronization** | **COMPLETED** | Committed and pushed cleanly to branch `Configuration`. |
