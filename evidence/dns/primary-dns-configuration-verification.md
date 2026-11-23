# Phase 2 — Primary DNS Configuration & Post-Restart Verification Report

**Machine:** Mac 1 — Mihika (`10.200.251.106`)  
**Role:** Primary DNS Server (`dnsmasq`)  
**Configuration File:** `/opt/homebrew/etc/dnsmasq.conf`  
**Execution Timestamp:** 2026-11-23 16:55:00 - 16:59:00 IST  

---

## 1. Executive Summary

| Requirement | Target | Result | Status |
|---|---|---|:---:|
| **Launchd Service Verification** | `system/sh.brew.dnsmasq` matched to process | Path, arguments, and PID matched | **PASS** |
| **Service Restart** | `sudo launchctl kickstart -k system/sh.brew.dnsmasq` | PID cycled 18937 -> 20596 cleanly | **PASS** |
| **Port 53 TCP Listener** | `10.200.251.106:53`, `127.0.0.1:53` | TCP LISTEN active on both IPs | **PASS** |
| **Port 53 UDP Listener** | `10.200.251.106:53`, `127.0.0.1:53` | UDP bound on both IPs | **PASS** |
| **`app.teamX.test` Resolution** | `10.200.251.227` with TTL `30` | Returned `10.200.251.227`, TTL `30` | **PASS** |
| **`api.teamX.test` Resolution** | `10.200.251.227` with TTL `30` | Returned `10.200.251.227`, TTL `30` | **PASS** |
| **TCP Query Support** | `dig +tcp @10.200.251.106` | Returned `NOERROR`, TTL `30` | **PASS** |
| **Query Logging** | `log-queries` enabled in `dnsmasq.conf` | Directive verified and loaded | **PASS** |
| **Primary DNS Persistence** | Keep running post-test | Running as PID 20596 | **PASS** |

---

## 2. Configuration Audit & Diff

### Target Configuration: `/opt/homebrew/etc/dnsmasq.conf`
A pre-modification backup was created at `/opt/homebrew/etc/dnsmasq.conf.bak_20261123`.

```diff
--- /opt/homebrew/etc/dnsmasq.conf.bak_20261123	2026-11-23 16:49:13
+++ /opt/homebrew/etc/dnsmasq.conf	2026-11-23 16:49:34
@@ -9,6 +9,12 @@
 listen-address=127.0.0.1,10.200.251.106
 bind-interfaces
 
+# Cache TTL (in seconds) for authoritative local records
+local-ttl=30
+
+# Enable logging of DNS queries
+log-queries
+
 no-resolv
 
 server=8.8.8.8
```

Syntax validation output:
```text
$ /opt/homebrew/opt/dnsmasq/sbin/dnsmasq --test -C /opt/homebrew/etc/dnsmasq.conf
dnsmasq: syntax check OK.
```

---

## 3. Post-Restart Service Lifecycle & Port Listeners

### A. Process Identification
```text
$ pgrep -fl dnsmasq
20596 /opt/homebrew/opt/dnsmasq/sbin/dnsmasq --keep-in-foreground -C /opt/homebrew/etc/dnsmasq.conf -7 /opt/homebrew/etc/dnsmasq.d,*.conf
```

### B. Listening Sockets on Port 53
```text
--- TCP Port 53 ---
tcp4       0      0  127.0.0.1.53           *.*                    LISTEN     
tcp4       0      0  10.200.251.106.53      *.*                    LISTEN     

--- UDP Port 53 ---
udp4       0      0  127.0.0.1.53           *.*                               
udp4       0      0  10.200.251.106.53      *.*                               
```

---

## 4. Approved DNS Verification Query Evidence

### Query 1: Local Loopback (`dig @127.0.0.1 app.teamX.test`)
```text
; <<>> DiG 9.10.6 <<>> @127.0.0.1 app.teamX.test +noall +answer +comments
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 45602
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; ANSWER SECTION:
app.teamX.test.		30	IN	A	10.200.251.227
```

### Query 2: LAN Interface UDP (`dig @10.200.251.106 app.teamX.test`)
```text
; <<>> DiG 9.10.6 <<>> @10.200.251.106 app.teamX.test +noall +answer +comments
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 23022
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; ANSWER SECTION:
app.teamX.test.		30	IN	A	10.200.251.227
```

### Query 3: LAN Interface TCP (`dig +tcp @10.200.251.106 app.teamX.test`)
```text
; <<>> DiG 9.10.6 <<>> +tcp @10.200.251.106 app.teamX.test +noall +answer +comments
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 63203
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; ANSWER SECTION:
app.teamX.test.		30	IN	A	10.200.251.227
```

### Query 4: API Virtual Host (`dig @10.200.251.106 api.teamX.test`)
```text
; <<>> DiG 9.10.6 <<>> @10.200.251.106 api.teamX.test +noall +answer +comments
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 22867
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; ANSWER SECTION:
api.teamX.test.		30	IN	A	10.200.251.227
```

---

## 5. Peer Connectivity Verification
- **Primary Edge (Mac 2 — `10.200.251.227`):** TCP Port 8443 reachable (`nc -zv 10.200.251.227 8443` succeeded).
- **Backend Server (Mac 3 — `10.200.251.76`):** TCP Port 3001 reachable (`nc -zv 10.200.251.76 3001` succeeded).
- **Primary DNS Status:** Running on Mac 1 (`PID 20596`), serving requests with authoritative TTL 30.
