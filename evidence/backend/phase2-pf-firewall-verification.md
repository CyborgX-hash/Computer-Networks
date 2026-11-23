# Phase 2 — Packet Filter (PF) Backend Firewall Verification Report

**Machine:** Mac 3 — Saksham (`10.200.251.76`)  
**Role:** Upstream Application Host (Backend A `:3001`, Backend B `:3002`)  
**Configuration File:** [`config/pf_backend.rules`](../../config/pf_backend.rules)  
**Backup Configuration:** [`config/pf.conf.backup`](../../config/pf.conf.backup)  
**Date:** 2026-11-23  
**Status:** **AUDITED & SYNTAX VALIDATED / SCOPED ANCHOR PREPARED / ACTIVATION PENDING EXPLICIT USER APPROVAL**  

---

## 1. Security Objective (Requirement C)

Restrict inbound access to backend microservice ports (`3001` and `3002`) on Mac 3 (`10.200.251.76`) so that:
1. **Authorized Edge Nodes are ALLOWED**:
   - Mac 1 (Standby Edge): `10.200.251.106`
   - Mac 2 (Primary Edge): `10.200.251.227`
   - Local Loopback: `127.0.0.1` (for local health checks and monitoring)
2. **All Other Inbound LAN Clients are BLOCKED**:
   - Any client outside the `<authorized_edges>` table is dropped/blocked.
3. **No Disruption to Other Services**:
   - Outbound internet access, DNS lookups, SSH, and unrelated macOS network operations must remain 100% unaffected.

---

## 2. Configuration & Syntax Audit

### A. The Scoped Ruleset (`config/pf_backend.rules`)
```pf
# Define Authorized Edge Hosts Table
table <authorized_edges> { 127.0.0.1, 10.200.251.106, 10.200.251.227 }

# Allow local loopback traffic
pass in quick on lo0 proto tcp to any port { 3001, 3002 }

# Allow traffic strictly from authorized edge nodes
pass in quick proto tcp from <authorized_edges> to any port { 3001, 3002 }

# Block and drop all other traffic to backend ports
block drop in quick proto tcp to any port { 3001, 3002 }
```

### B. Syntax & Parse Verification
Rule syntax was strictly validated using macOS `pfctl`:
```bash
$ pfctl -nf config/pf_backend.rules
pfctl: Use of -f option, could result in flushing of rules
present in the main ruleset added by the system at startup.
See /etc/pf.conf for further details.
# Exit Code: 0 (SYNTAX VALID)
```
- **Validation Result:** **PASS**. No syntax errors, table definitions valid, port groupings valid.

---

## 3. System PF Architecture & Anchor Scoping

### A. System `/etc/pf.conf` Integrity
Inspection of macOS system `/etc/pf.conf` confirmed that macOS relies on nested anchors:
```pf
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
```
A verified exact byte-for-byte copy is stored in [`config/pf.conf.backup`](../../config/pf.conf.backup).

### B. Anchor Isolation Principle
To prevent flushing system rules or breaking macOS network services:
- **FORBIDDEN:** `sudo pfctl -F all -f config/pf_backend.rules` (This would flush system rules).
- **REQUIRED & APPROVED:** `sudo pfctl -a backend -f config/pf_backend.rules`
  - Using `-a backend` confines the ruleset to the `backend` sub-anchor.
  - The main ruleset and `com.apple/*` anchors remain completely untouched.

---

## 4. Multi-Layer Security Architecture (Defense-in-Depth)

Mac 3 implements a dual-layer security architecture:

| Layer | Mechanism | Enforcement Point | Configuration | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Layer 7 (Application)** | Express.js Client IP Whitelist Middleware | Inside `server.js` on ports 3001 & 3002 | `ALLOWED_IPS = ['127.0.0.1', '10.200.251.106', '10.200.251.227']` | **ACTIVE & VERIFIED** (Returns `HTTP 403 Forbidden` to unauthorized clients) |
| **Layer 4 (Transport/Kernel)** | macOS Packet Filter (`pfctl`) Scoped Anchor | macOS Kernel TCP socket layer | `config/pf_backend.rules` via anchor `backend` | **PREPARED & VALIDATED** (Ready for activation upon user authorization) |

### Application Whitelist Runtime Evidence:
```bash
$ curl -s -i http://127.0.0.1:3001/health
HTTP/1.1 200 OK
{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T17:25:45.330Z"}
```
When probed from a non-whitelisted IP:
```http
HTTP/1.1 403 Forbidden
Content-Type: application/json; charset=utf-8

{"error":"Forbidden: Access restricted to authorized edge proxies"}
```

---

## 5. Kernel-Level Activation & Rollback Instructions

### Step 1: Activation Commands (Requires User Approval & Root Privileges)
```bash
# 1. Enable Packet Filter (if not currently enabled)
sudo pfctl -e

# 2. Load the backend rules into the scoped anchor "backend"
sudo pfctl -a backend -f config/pf_backend.rules

# 3. Verify loaded rules inside the anchor
sudo pfctl -a backend -s rules
# Expected output:
# pass in quick on lo0 proto tcp from any to any port = 3001 flags S/SA keep state
# pass in quick on lo0 proto tcp from any to any port = 3002 flags S/SA keep state
# pass in quick proto tcp from <authorized_edges> to any port = 3001 flags S/SA keep state
# pass in quick proto tcp from <authorized_edges> to any port = 3002 flags S/SA keep state
# block drop in quick proto tcp from any to any port = 3001
# block drop in quick proto tcp from any to any port = 3002

# 4. Verify table contents
sudo pfctl -a backend -t authorized_edges -T show
# Expected output:
# 127.0.0.1
# 10.200.251.106
# 10.200.251.227
```

### Step 2: Instant Safe Rollback Commands
```bash
# 1. Flush all rules and tables inside the scoped "backend" anchor:
sudo pfctl -a backend -F all

# 2. Confirm the anchor is empty:
sudo pfctl -a backend -s rules
# Output: (empty)
```
> [!IMPORTANT]
> Flushing the `backend` anchor with `sudo pfctl -a backend -F all` removes only the custom rules and tables created for the project. It leaves all other macOS system rules, AirDrop, Apple Services, and SSH completely undisturbed.

---

## 6. Access Policy Verification Matrix

| Source Machine | IP Address | Target Port | Expected Firewall Result | Expected Application Result | Verification Method |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Mac 1** (Standby Edge) | `10.200.251.106` | `3001`, `3002` | **ALLOW** | `HTTP 200 OK` | `curl -i http://10.200.251.76:3001/health` from Mac 1 |
| **Mac 2** (Primary Edge) | `10.200.251.227` | `3001`, `3002` | **ALLOW** | `HTTP 200 OK` | `curl -i http://10.200.251.76:3001/health` from Mac 2 |
| **Mac 3** (Localhost) | `127.0.0.1` | `3001`, `3002` | **ALLOW** | `HTTP 200 OK` | `curl -i http://127.0.0.1:3001/health` on Mac 3 |
| **Unauthorized LAN Client** | e.g. `10.200.251.x` | `3001`, `3002` | **DROP (Timeout)** | `HTTP 403 Forbidden` | `curl --connect-timeout 2 http://10.200.251.76:3001/` |

---

## 7. Status Summary

- **Audit & Syntax:** **PASS** (`pfctl -nf` verified).
- **Express Whitelist:** **ACTIVE & PASSING** (tested locally and verified with authorized peer edge requests).
- **Kernel Activation:** **PENDING USER AUTHORIZATION** (Safety constraints respected; instructions fully prepared for live faculty demonstration).
