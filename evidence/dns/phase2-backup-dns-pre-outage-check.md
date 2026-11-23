# Phase 2 — Local Backup DNS Pre-Outage Verification Report

**Machine:** Mac 2 (Priyanshu) — `10.200.251.227`  
**Role:** Backup DNS Resolver + Primary Edge NGINX  
**Execution Timestamp:** 2026-11-23T17:10:00+05:30  
**Status:** **READY FOR PRIMARY DNS OUTAGE TEST**

---

## 1. Process & Port Status

### A. Backup dnsmasq Process
```text
$ ps aux | grep dnsmasq
nobody  78501   0.0  0.0  /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
```
- **PID:** `78501`
- **Owner:** `nobody`
- **Configuration:** `/Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf`

### B. Port 53 Listeners (UDP & TCP)
- **TCP 53 on 127.0.0.1:** `Connection to 127.0.0.1 port 53 [tcp/domain] succeeded!`
- **TCP 53 on 10.200.251.227:** `Connection to 10.200.251.227 port 53 [tcp/domain] succeeded!`
- **UDP 53:** Bound via `bind-interfaces` to `127.0.0.1` and `10.200.251.227`.

### C. Primary Edge NGINX Listeners
- **Port 8443 (HTTPS):** PID `70698` (worker `71212`) listening.
- **Port 8080 (HTTP redirect):** PID `70698` (worker `71212`) listening.

---

## 2. DNS Query Verification (Local & LAN)

### Query 1: `dig @127.0.0.1 app.teamX.test +noall +answer` (UDP)
```text
app.teamX.test.		30	IN	A	10.200.251.227
```
- **Resolved IP:** `10.200.251.227`
- **TTL:** `30`
- **Result:** **PASS**

### Query 2: `dig +tcp @127.0.0.1 app.teamX.test +noall +answer` (TCP)
```text
app.teamX.test.		30	IN	A	10.200.251.227
```
- **Resolved IP:** `10.200.251.227`
- **TTL:** `30`
- **Result:** **PASS**

### Query 3: `dig @127.0.0.1 api.teamX.test +noall +answer` (UDP)
```text
api.teamX.test.		30	IN	A	10.200.251.227
```
- **Resolved IP:** `10.200.251.227`
- **TTL:** `30`
- **Result:** **PASS**

### Query 4: `dig @10.200.251.227 app.teamX.test +noall +answer` (LAN IP)
```text
app.teamX.test.		30	IN	A	10.200.251.227
```
- **Resolved IP:** `10.200.251.227`
- **TTL:** `30`
- **Result:** **PASS**

### Query 5: `dig @10.200.251.227 api.teamX.test +noall +answer` (LAN IP)
```text
api.teamX.test.		30	IN	A	10.200.251.227
```
- **Resolved IP:** `10.200.251.227`
- **TTL:** `30`
- **Result:** **PASS**

### Query 6: `dig +tcp @10.200.251.227 app.teamX.test +noall +answer` (LAN IP TCP)
```text
app.teamX.test.		30	IN	A	10.200.251.227
```
- **Resolved IP:** `10.200.251.227`
- **TTL:** `30`
- **Result:** **PASS**

---

## 3. Pre-Outage Readiness Conclusion

All pre-outage requirements are satisfied:
1. Backup dnsmasq is running (PID `78501`).
2. UDP and TCP port 53 are listening on both `127.0.0.1` and `10.200.251.227`.
3. `app.teamX.test` and `api.teamX.test` return `10.200.251.227` with TTL `30`.
4. Mac 2 Primary NGINX is actively serving on ports `8080` and `8443`.
5. Mac 2 is **100% READY** to accept client DNS traffic when Mac 1 stops its primary DNS server.
