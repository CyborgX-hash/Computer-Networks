# Phase 2 — Backup DNS Verification Report (Mac 2 — Priyanshu)

**Machine:** Mac 2 (Priyanshu) — `10.200.251.227`  
**Role:** Primary Edge Proxy (`8443`, `8080`) + Backup DNS Resolver (`53`)  
**Primary DNS:** Mac 1 (Mihika) — `10.200.251.106`  
**Dedicated Configuration:** `config/dnsmasq-backup.conf`  
**Execution Timestamp:** 2026-11-23T15:47:00+05:30 (Updated: 2026-11-23T22:40:00+05:30)  

---

## 1. Step 1 — Pre-Flight Audit

1. **Port 53 Collision Check:**
   ```bash
   $ lsof -i:53 -n -P
   # Initial check: Port 53 was completely unallocated
   ```
2. **Process Audit:** No prior dnsmasq process was running.
3. **Primary Edge NGINX Integrity:** Confirmed that primary nginx is running under `priyanshuagrahari` (master PID `70698`, worker `71212`) actively serving on ports `8443` (HTTPS) and `8080` (HTTP).

---

## 2. Step 2 — Installation Audit

- Installed `dnsmasq` version 2.93 via Homebrew:
  ```bash
  $ /opt/homebrew/sbin/dnsmasq -v
  Dnsmasq version 2.93  Copyright (c) 2000-2026 Simon Kelley
  Compile time options: IPv6 GNU-getopt no-DBus no-UBus no-i18n no-IDN DHCP no-DHCPv6 no-Lua TFTP no-conntrack ipset no-nftset auth cryptohash DNSSEC loop-detect inotify dumpfile
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

## 4. Step 5 — Service Startup & Process Verification

Command to start dnsmasq on privileged port 53:
```bash
sudo /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
```

Active Process Status:
```bash
$ ps aux | grep dnsmasq | grep -v grep
nobody           78501   0.0  0.0 488786176    576   ??  S     3:47PM   0:01.04 /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
```
- **PID:** 78501
- **User:** nobody (Privilege dropped automatically by dnsmasq after binding port 53)
- **Active Listening Ports:**
  ```bash
  $ netstat -an | grep '\.53 '
  tcp4       0      0  127.0.0.1.53           *.*                    LISTEN     
  tcp4       0      0  10.200.251.227.53      *.*                    LISTEN     
  udp4       0      0  127.0.0.1.53           *.*                               
  udp4       0      0  10.200.251.227.53      *.*                               
  ```

---

## 5. Step 6 — Verification Matrix & Live Command Outputs

| Test Case | Command | Protocol | Target Server | Expected IP | Returned TTL | Status |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Local app (UDP)** | `dig @127.0.0.1 app.teamX.test` | UDP | `127.0.0.1:53` | `10.200.251.227` | `30` | **PASS** |
| **Local api (UDP)** | `dig @127.0.0.1 api.teamX.test` | UDP | `127.0.0.1:53` | `10.200.251.227` | `30` | **PASS** |
| **LAN app (UDP)** | `dig @10.200.251.227 app.teamX.test` | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | **PASS** |
| **LAN api (UDP)** | `dig @10.200.251.227 api.teamX.test` | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | **PASS** |
| **Local app (TCP)** | `dig +tcp @127.0.0.1 app.teamX.test` | TCP | `127.0.0.1:53` | `10.200.251.227` | `30` | **PASS** |
| **LAN app (TCP)** | `dig +tcp @10.200.251.227 app.teamX.test` | TCP | `10.200.251.227:53` | `10.200.251.227` | `30` | **PASS** |
| **Remote Mac 1 Query** | `dig @10.200.251.227 app.teamX.test` | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | **PASS** |
| **Remote Mac 3 Query** | `dig @10.200.251.227 app.teamX.test` | UDP | `10.200.251.227:53` | `10.200.251.227` | `30` | **PASS** |

### Live Dig Query Outputs:

```bash
$ dig @127.0.0.1 app.teamX.test +noall +answer
app.teamX.test.		30	IN	A	10.200.251.227

$ dig @127.0.0.1 api.teamX.test +noall +answer
api.teamX.test.		30	IN	A	10.200.251.227

$ dig +tcp @127.0.0.1 app.teamX.test +noall +answer
app.teamX.test.		30	IN	A	10.200.251.227

$ dig @10.200.251.227 app.teamX.test +noall +answer
app.teamX.test.		30	IN	A	10.200.251.227

$ dig @10.200.251.227 api.teamX.test +noall +answer
api.teamX.test.		30	IN	A	10.200.251.227
```

---

## 6. Primary DNS Outage Validation

During the coordinated primary DNS outage test conducted with Member 1 (Mihika) and Member 2 (Saksham), Mac 1's primary DNS was stopped via `launchctl bootout`.
- Mac 3 and Mac 1 directed failover DNS queries to Mac 2 (`10.200.251.227`).
- Backup DNS responded within 2-3ms with 100% success rate, preserving full zone resolution for `app.teamX.test` and `api.teamX.test` with TTL 30.
- See detailed failover log in [evidence/dns/phase2-primary-backup-dns-failover.md](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/evidence/dns/phase2-primary-backup-dns-failover.md).
