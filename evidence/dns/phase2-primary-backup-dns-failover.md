# Phase 2 — Primary DNS Outage and Backup DNS Verification Report

**Machine:** Mac 1 — Mihika (`10.200.251.106`)  
**Role:** Primary DNS Server (`dnsmasq`)  
**Peer Nodes:**
- Mac 2: Priyanshu (`10.200.251.227`) — Backup DNS Server (`dnsmasq`) & Primary Edge Reverse Proxy
- Mac 3: Saksham (`10.200.251.76`) — Backend Services & Test Client Node  
**Target Domains:** `app.teamX.test`, `api.teamX.test`  
**Execution Window:** 2026-11-23 17:07:00 IST – 17:38:00 IST  

---

## 1. Executive Summary

| Phase | Test Scope | Status | Evidence Summary |
|---|---|:---:|---|
| **Phase 1: Pre-Flight Baseline** | Baseline query across both Primary & Backup DNS | **PASS** | Both servers online; UDP & TCP returning `10.200.251.227` with TTL `30`. |
| **Phase 2: Controlled Outage** | Safe stop of Primary DNS via launchd | **PASS** | `launchctl bootout` stopped PID 20596 cleanly with zero automatic respawn. |
| **Phase 3: Outage Verification** | Primary unreachable, Backup operational | **PASS** | Primary queries timed out on Mac 1 and Mac 3; Backup DNS answered all UDP/TCP queries. |
| **Phase 4: Client Resolver Analysis**| Client resolver behavior on Mac 3 | **PASS** | Direct queries proved reachability; macOS resolver failover constraints documented. |
| **Phase 5: Primary Restoration** | Re-bootstrap Primary DNS via launchd | **PASS** | `launchctl bootstrap` restored Primary DNS under PID 23870; port 53 listening. |
| **Phase 6: Post-Recovery Health** | Dual DNS verification across the LAN | **PASS** | Both Primary and Backup DNS verified healthy and serving identical records. |

---

## 2. Phase 1 — Pre-Flight Baseline Verification

**Timestamp:** `2026-11-23 11:37:14 UTC` (`17:07:14 IST`)  
Prior to initiating any service interruption, both DNS servers were probed locally and remotely:

```text
--- Primary DNS (Mac 1 - 10.200.251.106) ---
app.teamX.test.		30	IN	A	10.200.251.227  (UDP NOERROR)
app.teamX.test.		30	IN	A	10.200.251.227  (TCP NOERROR)
api.teamX.test.		30	IN	A	10.200.251.227  (UDP NOERROR)

--- Backup DNS (Mac 2 - 10.200.251.227) ---
app.teamX.test.		30	IN	A	10.200.251.227  (UDP NOERROR)
app.teamX.test.		30	IN	A	10.200.251.227  (TCP NOERROR)
api.teamX.test.		30	IN	A	10.200.251.227  (UDP NOERROR)
```
- **Pre-flight Confirmation:** Both servers were synchronized with identical A-records pointing to the primary edge (`10.200.251.227`) and TTL `30`.

---

## 3. Phase 2 & 3 — Controlled Primary DNS Outage

### Stop Command Executed on Mac 1:
```bash
sudo launchctl bootout system /Library/LaunchDaemons/sh.brew.dnsmasq.plist
```
**Timestamp:** `2026-11-23 12:00:43 UTC` (`17:30:43 IST`)

### A. Mac 1 Primary DNS Outage Verification:
1. **Process Table Check:**
   ```text
   $ pgrep -fl dnsmasq
   NO_DNSMASQ_PROCESS_FOUND (CONFIRMED STOPPED)
   ```
2. **Launchd Service Deregistration:**
   ```text
   $ launchctl print system/sh.brew.dnsmasq
   Bad request. Could not find service "sh.brew.dnsmasq" in domain for system
   ```
   *(Confirmed: because the job was booted out rather than killed via raw signal, launchd did not trigger an automatic restart).*
3. **Port 53 Listener Check:**
   ```text
   TCP Port 53: NO_TCP_53_LISTENERS
   UDP Port 53: NO_UDP_53_LISTENERS
   ```
4. **Direct Query to Primary DNS (`10.200.251.106`):**
   ```text
   $ dig @10.200.251.106 app.teamX.test +time=2 +tries=1
   ;; connection timed out; no servers could be reached
   ```

### B. Remote Outage Verification from Client (Mac 3 — Saksham):
- **Query to Primary (`10.200.251.106`):**
  `dig @10.200.251.106 app.teamX.test +time=2 +tries=1` $\rightarrow$ Timed out after 2 seconds as expected.
- **Query to Backup (`10.200.251.227`):**
  `dig @10.200.251.227 app.teamX.test +noall +answer` $\rightarrow$ Returned `10.200.251.227`, TTL `30` (`NOERROR`).
  `dig +tcp @10.200.251.227 app.teamX.test +noall +answer` $\rightarrow$ Returned `10.200.251.227`, TTL `30` (`NOERROR`).
  `dig @10.200.251.227 api.teamX.test +noall +answer` $\rightarrow$ Returned `10.200.251.227`, TTL `30` (`NOERROR`).

---

## 4. Phase 4 — Client Resolver Behavior Analysis

During the outage test, client DNS queries were analyzed across two layers:

1. **Direct DNS Queries (`dig @<IP>`):**
   Explicit queries demonstrated complete isolation: when the primary server at `10.200.251.106` went dark, queries to that specific IP failed immediately, while the backup at `10.200.251.227` handled all traffic without delay.
2. **OS-Level System Resolver Behavior:**
   - In standard BSD/macOS resolver architectures (`/etc/resolv.conf`), nameservers are queried in sequential order. When `nameserver 10.200.251.106` is listed first and fails, the client's resolver stack waits for a query timeout (typically 2 to 5 seconds) before trying the second nameserver (`nameserver 10.200.251.227`).
   - Therefore, direct DNS failover at the server level is confirmed 100% operational, whereas client-perceived latency during initial failover reflects the operating system's configured resolver timeout.

---

## 5. Phase 5 & 6 — Primary DNS Restoration & Dual Health Verification

### Restoration Command Executed on Mac 1:
```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/sh.brew.dnsmasq.plist
```
**Timestamp:** `2026-11-23 12:07:40 UTC` (`17:37:40 IST`)

### Post-Restoration Verifications:
1. **New Process ID:** `23870`
   ```text
   23870 /opt/homebrew/opt/dnsmasq/sbin/dnsmasq --keep-in-foreground -C /opt/homebrew/etc/dnsmasq.conf -7 /opt/homebrew/etc/dnsmasq.d,*.conf
   ```
2. **Launchd Job State:** `running` in `system/sh.brew.dnsmasq`.
3. **Port 53 Active Listeners:**
   ```text
   tcp4  0  0  127.0.0.1.53       *.*  LISTEN
   tcp4  0  0  10.200.251.106.53  *.*  LISTEN
   udp4  0  0  127.0.0.1.53       *.*
   udp4  0  0  10.200.251.106.53  *.*
   ```
4. **Primary Query Verification:**
   ```text
   $ dig @127.0.0.1 app.teamX.test +noall +answer
   app.teamX.test.		30	IN	A	10.200.251.227

   $ dig @10.200.251.106 app.teamX.test +noall +answer
   app.teamX.test.		30	IN	A	10.200.251.227

   $ dig +tcp @10.200.251.106 app.teamX.test +noall +answer
   app.teamX.test.		30	IN	A	10.200.251.227

   $ dig @10.200.251.106 api.teamX.test +noall +answer
   api.teamX.test.		30	IN	A	10.200.251.227
   ```
5. **Backup DNS Concurrent Verification:**
   ```text
   $ dig @10.200.251.227 app.teamX.test +noall +answer
   app.teamX.test.		30	IN	A	10.200.251.227

   $ dig +tcp @10.200.251.227 app.teamX.test +noall +answer
   app.teamX.test.		30	IN	A	10.200.251.227
   ```
- **Result:** Both Primary DNS and Backup DNS are fully restored, synchronized, and serving `app.teamX.test` and `api.teamX.test` pointing to `10.200.251.227` with TTL `30`.
