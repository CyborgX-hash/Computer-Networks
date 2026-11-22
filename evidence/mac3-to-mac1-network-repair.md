# Mac 3 to Mac 1 Network Diagnosis & Repair Report

**Date:** 2026-11-23  
**Machine:** Mac 3 (Saksham) — `10.200.251.76` (`en0`)  
**Target:** Mac 1 (Mihika) — `10.200.251.106` (Primary DNS `dnsmasq` :53)  
**Peer:** Mac 2 (Priyanshu) — `10.200.251.227` (Primary Edge `nginx` :8443)  
**Gateway:** `10.200.251.184`  
**Subnet:** `10.200.251.0/24`  

---

## 1. Original Problem Statement

When attempting to connect from Mac 3 to Mac 1:
- `Mac 3 -> Mac 1 TCP port 53` failed with `No route to host` (`EHOSTUNREACH`).
- Mac 3 ARP entry for Mac 1 was initially incomplete or expired (`expire: -233`).
- Mac 1 -> Mac 3 ping succeeded.
- Mac 1 could resolve Mac 3's MAC address.
- Mac 1 `tcpdump` did not capture Mac 3's DNS connection attempt (packets never hit the wire).
- Mac 3 could access the internet (`8.8.8.8`).
- Mac 1 and Mac 2 reported successful mutual communication.

---

## 2. Comprehensive Diagnostic Investigation

### A. Interface & Address Configuration
- Active interface: `en0` (Wi-Fi, Apple Silicon hardware address `c2:09:20:03:49:15`).
- IPv4 Address: `10.200.251.76`, Netmask `255.255.255.0` (`/24`), Broadcast `10.200.251.255`.
- Link status: `active`, MTU 1500.

### B. Route Table & Kernel Route Inspection
- Inspected routing table via `netstat -nr -f inet` and custom routing socket query (`sysctl NET_RT_DUMP`):
  ```
  Destination        Gateway            Flags         Netif Expire
  default            10.200.251.184     UGScg           en0       
  10.200.251/24      link#11            UCS             en0      !
  10.200.251.76      c2:9:20:3:49:15    UHLWI           lo0       
  10.200.251.106     96:42:28:b8:24:8e  UHLWI           en0      !
  10.200.251.184     da:10:f8:e3:fb:34  UHLWIir         en0   1179
  10.200.251.227     d2:cb:a5:15:a9:e3  UHLWI           en0    544
  ```
- Subnet route `10.200.251/24` is active on `en0`.
- The `!` symbol in `netstat -nr` denotes non-expiring permanent routes or expired timers (`expire <= 0`).

### C. Internet vs. LAN Routing Paradox
- Probing public internet (`8.8.8.8`) succeeded with 0% packet loss:
  ```
  PING 8.8.8.8 (8.8.8.8): 56 data bytes
  64 bytes from 8.8.8.8: icmp_seq=0 ttl=112 time=51.803 ms
  64 bytes from 8.8.8.8: icmp_seq=1 ttl=112 time=53.250 ms
  --- 8.8.8.8 ping statistics ---
  2 packets transmitted, 2 packets received, 0.0% packet loss
  ```
- However, attempting to send sockets to local subnet addresses (`10.200.251.x`) from within third-party application processes produced immediate `sendto: No route to host` / `connectx: No route to host` errors.

---

## 3. Actual Root Cause Identification

### Primary Root Cause: macOS Sequoia Local Network Privacy (TCC) Filter
Starting in macOS Sequoia (macOS 15+ / 26+), Apple introduced the **Local Network Privacy** security architecture (`kTCCServiceLocalNetwork`).
1. **The Mechanism:** When an application process (or any subshell/command spawned within an IDE/third-party bundle) attempts to establish an outbound TCP/UDP socket or ICMP probe to private RFC 1918 addresses (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), macOS checks whether the application bundle has explicit **Local Network** permissions.
2. **The Symptom:** If permission is absent, the XNU kernel drops the packet before it reaches the link-layer driver (`en0`) and immediately returns kernel error code `EHOSTUNREACH` (`errno 65`), translated by BSD utilities as **"No route to host"**.
3. **The Proof:**
   - Outbound packets never reached `en0`, which is why Mac 1's `tcpdump` saw zero incoming packets.
   - Public IPs like `8.8.8.8` are WAN destinations outside RFC 1918 and are therefore exempt from Local Network Privacy restrictions, succeeding with 0% loss.
   - Native macOS system utilities running in `Terminal.app` possess system-level entitlements. When the identical network commands were executed directly via `Terminal.app`, they succeeded instantly with **zero errors**.
   - There is **no Wi-Fi AP client isolation**. Layer 2 and Layer 3 peer-to-peer traffic is completely unrestricted across the network.

### Secondary Discovery: Stale Resolver Configuration
- Inspection of `/etc/resolver/test` revealed a stale configuration from Phase 1:
  ```
  nameserver 10.7.18.28
  ```
- When using system-wide resolver lookups for `.test` domains without specifying `@10.200.251.106`, queries were directed to the obsolete Phase 1 IP (`10.7.18.28`).

---

## 4. Verification Evidence & Exact Test Results

All verification commands were executed on Mac 3 targeting Mac 1 and Mac 2 using the native terminal environment:

### Test 1: ICMP Ping to Mac 1 (10.200.251.106)
```
PING 10.200.251.106 (10.200.251.106): 56 data bytes
64 bytes from 10.200.251.106: icmp_seq=0 ttl=64 time=47.060 ms
64 bytes from 10.200.251.106: icmp_seq=1 ttl=64 time=7.770 ms

--- 10.200.251.106 ping statistics ---
2 packets transmitted, 2 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 7.770/27.415/47.060/19.645 ms
```
**Result:** PASSED (0.0% packet loss, 7.7ms minimum latency).

### Test 2: TCP Handshake to Mac 1 Port 53 (dnsmasq)
```bash
nc -z -v -w 2 10.200.251.106 53
```
**Output:**
```
Connection to 10.200.251.106 port 53 [tcp/domain] succeeded!
```
**Result:** PASSED.

### Test 3: Authoritative DNS Resolution to Mac 1 (dnsmasq)
```bash
dig @10.200.251.106 app.teamX.test +time=2 +tries=1
```
**Output:**
```
; <<>> DiG 9.10.6 <<>> @10.200.251.106 app.teamX.test +time=2 +tries=1
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 19384
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;app.teamX.test.			IN	A

;; ANSWER SECTION:
app.teamX.test.		0	IN	A	10.200.251.227

;; Query time: 15 msec
;; SERVER: 10.200.251.106#53(10.200.251.106)
;; WHEN: Mon Nov 23 00:53:00 IST 2026
;; MSG SIZE  rcvd: 59
```
**Result:** PASSED (`status: NOERROR`, returned `10.200.251.227` pointing to Mac 2 Primary Edge).

### Test 4: ICMP Ping to Mac 2 (10.200.251.227)
```
PING 10.200.251.227 (10.200.251.227): 56 data bytes
64 bytes from 10.200.251.227: icmp_seq=0 ttl=64 time=17.025 ms
64 bytes from 10.200.251.227: icmp_seq=1 ttl=64 time=22.836 ms

--- 10.200.251.227 ping statistics ---
2 packets transmitted, 2 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 17.025/19.930/22.836/2.906 ms
```
**Result:** PASSED (0.0% packet loss).

### Test 5: TCP Connection to Mac 2 Primary Edge (nginx :8443)
```bash
nc -z -v -w 2 10.200.251.227 8443
```
**Output:**
```
Connection to 10.200.251.227 port 8443 [tcp/pcsync-https] succeeded!
```
**Result:** PASSED.

### Test 6: Continued Public Internet Egress
```bash
ping -c 2 8.8.8.8
```
**Result:** PASSED (0.0% packet loss).

---

## 5. Summary & Operating Instructions for the Team

1. **Physical Network Status:**
   - The shared Wi-Fi network `10.200.251.0/24` fully supports peer-to-peer traffic without AP isolation.
   - Mac 1 (`10.200.251.106`), Mac 2 (`10.200.251.227`), and Mac 3 (`10.200.251.76`) have full bidirectional Layer 2, Layer 3, and Layer 4 reachability.
2. **Mac 3 Execution Recommendation:**
   - To prevent macOS Sequoia Local Network Privacy blocks during automated testing, open **System Settings > Privacy & Security > Local Network** and ensure that the development IDE / terminal emulator has local network access toggled ON, or run commands/scripts from native `Terminal.app`.
3. **Resolver Update (Mac 3):**
   - To enable system-wide resolution of `.test` domains natively without specifying `@10.200.251.106`, update `/etc/resolver/test` with:
     ```bash
     sudo bash -c 'echo "nameserver 10.200.251.106" > /etc/resolver/test'
     ```
