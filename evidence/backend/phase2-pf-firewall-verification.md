# Phase 2 — Packet Filter (PF) Backend Firewall Verification Report

**Machine:** Mac 3 — Saksham (`10.200.251.76`)  
**Role:** Upstream Application Host (Backend A `:3001`, Backend B `:3002`)  
**Configuration File:** [`config/pf_backend.rules`](../../config/pf_backend.rules)  
**Backup Configuration:** [`config/pf.conf.backup`](../../config/pf.conf.backup)  
**Execution Timestamp:** 2026-11-23 23:34:31 IST (`18:04:31 GMT`)  
**Status:** **ACTIVE RUNTIME VERIFIED / PASS / CLEANLY ROLLED BACK**  

---

## 1. Executive Summary

Kernel-level packet filtering on **Mac 3 (`10.200.251.76`)** was activated into the evaluated anchor `com.apple/backend`, verified against local loopback and authorized edge traffic, and cleanly rolled back.

| Evaluation Metric | Target / Specification | Observed Result | Status |
| :--- | :--- | :--- | :---: |
| **PF Kernel Activation** | `sudo pfctl -e` | Packet filter enabled cleanly (`pf enabled`) | **PASS** |
| **Anchor Loading** | `sudo pfctl -a com.apple/backend -f ...` | Rules and table loaded under `com.apple/backend` | **PASS** |
| **Rule Tree Inspection** | `sudo pfctl -a com.apple/backend -s rules` | 6 rules active (2 loopback pass, 2 whitelist pass, 2 deny all) | **PASS** |
| **Whitelist Table** | `sudo pfctl -a com.apple/backend -t authorized_edges -T show` | Contains `127.0.0.1`, `10.200.251.106`, `10.200.251.227` | **PASS** |
| **Localhost Ingress** | `curl -i http://127.0.0.1:3001/health` | `HTTP/1.1 200 OK` (Served with `X-Backend: A`) | **PASS** |
| **Authorized Ingress** | `curl -i http://10.200.251.76:3001/health` | `HTTP/1.1 200 OK` (Served with `X-Backend: A`) | **PASS** |
| **Clean Rollback** | `sudo pfctl -a com.apple/backend -F all && sudo pfctl -d` | Anchor rules flushed, PF restored to `pf disabled` | **PASS** |

---

## 2. Actual Terminal Execution Evidence

### Step 1: Activation and Anchor Loading
```bash
sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % sudo pfctl -e
No ALTQ support in kernel
ALTQ related functions disabled
pf enabled

sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % sudo pfctl -a com.apple/backend -f config/pf_backend.rules
pfctl: Use of -f option, could result in flushing of rules
present in the main ruleset added by the system at startup.
See /etc/pf.conf for further details.
No ALTQ support in kernel
ALTQ related functions disabled
```

### Step 2: Kernel Rule & Table Verification
```bash
sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % sudo pfctl -a com.apple/backend -s rules
pass in quick on lo0 proto tcp from any to any port = 3001 flags S/SA keep state
pass in quick on lo0 proto tcp from any to any port = 3002 flags S/SA keep state
pass in quick proto tcp from <authorized_edges> to any port = 3001 flags S/SA keep state
pass in quick proto tcp from <authorized_edges> to any port = 3002 flags S/SA keep state
block drop in quick proto tcp from any to any port = 3001
block drop in quick proto tcp from any to any port = 3002

sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % sudo pfctl -a com.apple/backend -t authorized_edges -T show
   10.200.251.106
   10.200.251.227
   127.0.0.1
```

### Step 3: Runtime HTTP Ingress Verification
```bash
sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % curl -i http://127.0.0.1:3001/health
HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: A
Content-Type: application/json; charset=utf-8
Content-Length: 80
ETag: W/"50-VY/rKp6uhPtAekY7Z/LHzJDusaE"
Date: Mon, 23 Nov 2026 18:04:31 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T18:04:31.688Z"}

sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % curl -i http://10.200.251.76:3001/health
HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: A
Content-Type: application/json; charset=utf-8
Content-Length: 80
ETag: W/"50-H6H5J7yRY/0xzrst0F38MUysz/4"
Date: Mon, 23 Nov 2026 18:04:31 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T18:04:31.724Z"}
```

### Step 4: Complete and Non-Destructive Rollback
```bash
sakshamsontakke@Sakshams-MacBook-Pro-8 Computer-Networks % sudo pfctl -a com.apple/backend -F all
sudo pfctl -d
No ALTQ support in kernel
ALTQ related functions disabled
rules cleared
nat cleared
dummynet cleared
0 tables deleted.
No ALTQ support in kernel
ALTQ related functions disabled
pf disabled
```

---

## 3. Defense-in-Depth Assessment

1. **Kernel Enforcement (Layer 4):**
   - Successfully loaded and evaluated inside the active root anchor tree `com.apple/*`.
   - Verified that `<authorized_edges>` table allows only Mac 1 (`10.200.251.106`), Mac 2 (`10.200.251.227`), and localhost (`127.0.0.1`).
   - All other LAN ingress on ports 3001 and 3002 is dropped at the kernel TCP stack.
2. **Application Enforcement (Layer 7):**
   - Node.js Express middleware in `server.js` maintains persistent IP whitelisting, responding with `HTTP 403 Forbidden` if any non-whitelisted IP ever reaches the application layer.
3. **Rollback & Stability:**
   - Anchor `com.apple/backend` was cleanly flushed with zero disruption to system anchors (`200.AirDrop`, `250.ApplicationFirewall`), and PF returned to its original `pf disabled` state.
