# Phase 2 — Backup DNS Verification Report (Mac 2 — Priyanshu)

**Machine:** Mac 2 (Priyanshu) — `10.200.251.227`  
**Role:** Primary Edge Proxy (`8443`, `8080`) + Backup DNS Resolver (`53`)  
**Primary DNS:** Mac 1 (Mihika) — `10.200.251.106`  
**Dedicated Configuration:** `config/dnsmasq-backup.conf`  
**Execution Timestamp:** 2026-11-23T14:55:00+05:30  

---

## 1. Step 1 — Pre-Flight Audit

1. **Port 53 Collision Check:**
   ```bash
   $ lsof -i:53 -n -P
   # (Empty — Port 53 was completely unallocated)
   ```
2. **Process Audit:** No prior dnsmasq process was running.
3. **Primary Edge NGINX Integrity:** Confirmed that primary nginx is running under `priyanshuagrahari` (PID `70698`, worker `71212`) actively serving on ports `8443` (HTTPS) and `8080` (HTTP).

---

## 2. Step 2 — Installation Audit

- Installed `dnsmasq` version 2.93 via Homebrew:
  ```bash
  $ /opt/homebrew/sbin/dnsmasq -v
  Dnsmasq version 2.93  Copyright (c) 2000-2026 Simon Kelley
  ```

---

## 3. Step 3 & 4 — Configuration & Syntax Validation

Dedicated configuration file: [config/dnsmasq-backup.conf](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf)
```ini
port=53
domain=test
local=/teamX.test/

listen-address=127.0.0.1,10.200.251.227
bind-interfaces

address=/app.teamX.test/10.200.251.227
address=/api.teamX.test/10.200.251.227

local-ttl=30

no-hosts
no-resolv
server=8.8.8.8
server=1.1.1.1

log-queries
cache-size=1000
```

Validation command:
```bash
$ /opt/homebrew/sbin/dnsmasq --test -C config/dnsmasq-backup.conf
dnsmasq: syntax check OK.
```

---

## 4. Step 5 — Service Startup

Command to start dnsmasq on privileged port 53:
```bash
sudo /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
```
*Status: Awaiting root authorization to bind port 53.*

---

## 5. Step 6 — Verification Matrix

| Test Case | Command | Protocol | Target Server | Expected IP | Expected TTL | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Local app (UDP)** | `dig @127.0.0.1 app.teamX.test` | UDP | `127.0.0.1:53` | `10.200.251.227` | `30` | PENDING |
| **Local api (UDP)** | `dig @127.0.0.1 api.teamX.test` | UDP | `127.0.0.1:53` | `10.200.251.227` | `30` | PENDING |
| **LAN app (UDP)** | `dig @10.200.251.227 app.teamX.test` | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | PENDING |
| **LAN api (UDP)** | `dig @10.200.251.227 api.teamX.test` | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | PENDING |
| **Local app (TCP)** | `dig +tcp @127.0.0.1 app.teamX.test` | TCP | `127.0.0.1:53` | `10.200.251.227` | `30` | PENDING |
| **LAN app (TCP)** | `dig +tcp @10.200.251.227 app.teamX.test` | TCP | `10.200.251.227:53` | `10.200.251.227` | `30` | PENDING |
| **Remote Mac 1** | Remote query from Mac 1 | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | PENDING |
| **Remote Mac 3** | Remote query from Mac 3 | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | PENDING |
