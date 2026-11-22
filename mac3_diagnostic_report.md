# MAC 3 Diagnostic Report — Private Network Service Platform (Phase 2)

**Machine:** Mac 3  
**Owner / Engineer:** Saksham (Backend Engineer)  
**Role:** Backend Application Host (Backend A: port 3001, Backend B: port 3002)  
**Stage:** Stage 1 — Complete Diagnostic Audit (Baseline Verification)  
**Timestamp:** 2026-11-23T00:28:30+05:30  

---

## 1. System & Architecture Audit

- **Operating System:** macOS 27.2.1
- **Kernel:** Darwin Kernel Version 27.2.0 (Wed Oct 14 23:43:44 PDT 2026; root:xnu-13432.41.4~25/RELEASE_ARM64_T8122)
- **Hardware Architecture:** Apple Silicon (`arm64`)
- **Hostname:** `Sakshams-MacBook-Pro-8.local`
- **Current User:** `sakshamsontakke`
- **Shell:** zsh

---

## 2. Network Interface & IP Configuration

- **Active Interface:** `en0` (Wi-Fi)
- **Link Status:** `active`, `media: autoselect`
- **IPv4 Address (`MAC3_IP`):** `10.200.251.76`
- **Subnet Mask:** `255.255.255.0` (`0xffffff00`, `/24`)
- **Broadcast Address:** `10.200.251.255`
- **Hardware (MAC) Address:** `c2:09:20:03:49:15`
- **Loopback (`lo0`):** `127.0.0.1` / `::1`
- **Virtual Interfaces:** `utun0`..`utun3` present, but no active peer overlay IPv4 bound.

---

## 3. Gateway, Subnet & Routing Table

- **Default Gateway:** `10.200.251.184`
- **Gateway MAC Address:** `da:10:f8:e3:fb:34`
- **Routing Table Output (`netstat -nr -f inet`):**
  ```
  Destination        Gateway            Flags         Netif Expire
  default            10.200.251.184     UGScg           en0       
  10.200.251/24      link#11            UCS             en0      !
  10.200.251.76/32   link#11            UCS             en0      !
  10.200.251.184/32  link#11            UCS             en0      !
  10.200.251.184     da:10:f8:e3:fb:34  UHLWIir         en0   1198
  127                127.0.0.1          UCS             lo0       
  127.0.0.1          127.0.0.1          UH              lo0       
  ```

---

## 4. Connectivity to Mac 1 and Mac 2 & Peer-to-Peer Evaluation

### Findings:
1. **Unconfirmed Peer IPs:**
   - Neither Mac 1 (`MAC1_IP`, Mihika) nor Mac 2 (`MAC2_IP`, Priyanshu) has submitted a verified, active IP for the current physical network session.
   - An uncommitted working diff in `config/dnsmasq.conf` indicated a prior attempt targeting `10.200.251.227`, but this address is unverified and not answering ARP.
2. **Local Gateway Reachability:**
   - Active ICMP probes to the default gateway `10.200.251.184` resulted in `sendto: No route to host` / 100% packet loss.
3. **Inbound & Peer-to-Peer Assessment:**
   - **Crucial Diagnostic Finding:** Successful internet egress does **not** imply that local peer-to-peer traffic is permitted.
   - The current Wi-Fi network exhibits symptoms of **Client/AP Isolation** (common in campus/guest Wi-Fi networks), where direct station-to-station (peer-to-peer) Layer 2 and Layer 3 frames are blocked by the wireless access point.
   - **Recommendation:** If the Wi-Fi AP enforces isolation, the 3 machines must either:
     - Connect to a shared mobile phone Wi-Fi hotspot with local communication enabled, or
     - Deploy a **Tailscale** private mesh network to bypass Wi-Fi AP isolation reliably.

---

## 5. Tailscale Audit

- **Installation Status:** Not installed (`which tailscale` -> command not found).
- **Application Bundle:** Not present in `/Applications`.
- **Homebrew Cask / Formula:** Not installed.
- **Current Tailscale IP:** None.
- **Decision Point for Team:** If Wi-Fi isolation prevents direct TCP/UDP packets between Mac 1, Mac 2, and Mac 3, Tailscale must be installed by all 3 members (`brew install --cask tailscale`).

---

## 6. Software & Runtimes Audit

- **Node.js:** `v22.21.1` (`/Users/sakshamsontakke/.nvm/versions/node/v22.21.1/bin/node`) — Fully verified and operational.
- **npm:** `10.9.0` (`/Users/sakshamsontakke/.nvm/versions/node/v22.21.1/bin/npm`) — Fully operational.
- **Python 3:** `3.14.0` (`/opt/homebrew/bin/python3`) — Available for auxiliary test automation.
- **Homebrew:** `4.x` (`/opt/homebrew/bin/brew`) — Available.
- **Packet Filter (`pfctl`):** `/sbin/pfctl` — Available.
- **nginx & dnsmasq:** Not installed on Mac 3 (these belong to Mac 1 and Mac 2 per architecture matrix).

---

## 7. Port Availability & Collision Report

- Active scan performed with `lsof -iTCP -sTCP:LISTEN -P -n`.
- **Port 3001 (Backend A):** **FREE** (No listening process).
- **Port 3002 (Backend B):** **FREE** (No listening process).
- **Other local listeners:** `5432` (postgres), `27017` (mongod), `3306`/`33060` (mysql), `11434` (ollama), `51070` (rapportd). All development databases are bound strictly to `127.0.0.1` and will not conflict with project ports.

---

## 8. Backend Code & API Route Audit

### Backend A (`backend/backend-a/server.js`)
- **Runtime:** Express.js `^4.18.2`
- **Listening Interface & Port:** Currently binds to `HOST = '0.0.0.0'`, `PORT = 3001`
- **Middleware:** Injects `X-Backend: A` header on all responses
- **Existing Routes:**
  - `GET /`: Returns `{"backend": "A", "status": "ok", "message": "Backend A is running"}`
  - `GET /api/status`: Returns `{"backend": "A", "status": "ok"}` with `Cache-Control: public, max-age=60`
  - Catch-all 404: Returns `{"error": "Not Found"}`
- **Code Audit Gaps:**
  - Missing dedicated `GET /health` endpoint required for Phase 2 health checking.
  - Binds to wildcard `0.0.0.0` without access control.
  - No access filtering middleware for authorized edge IPs.

### Backend B (`backend/backend-b/server.js`)
- **Runtime:** Express.js `^4.18.2`
- **Listening Interface & Port:** Currently binds to `HOST = '0.0.0.0'`, `PORT = 3002`
- **Middleware:** Injects `X-Backend: B` header on all responses
- **Existing Routes:**
  - `GET /`: Returns `{"backend": "B", "status": "ok", "message": "Backend B is running"}`
  - `GET /api/status`: Returns `{"backend": "B", "status": "ok"}` with `Cache-Control: public, max-age=60`
  - Catch-all 404: Returns `{"error": "Not Found"}`
- **Code Audit Gaps:**
  - Missing dedicated `GET /health` endpoint.
  - Binds to `0.0.0.0` with no edge node access restrictions.

---

## 9. Security & Firewall Posture (Requirement C)

### Current Status:
- macOS Application Firewall (`socketfilterfw`): Disabled (`State = 0`).
- Packet Filter (`pfctl`): Default configuration, no custom project anchors active.

### Security Risks Identified:
1. **Unrestricted Port Exposure:** Binding to `0.0.0.0` without packet filtering or application-level source IP verification exposes ports `3001` and `3002` to any host on the same subnet.
2. **Direct Client Bypass Risk:** If clients bypass the edge reverse proxy (`nginx` on Mac 2 or standby on Mac 1) and hit Mac 3 directly, they bypass TLS termination, load balancing, and rate limiting.
3. **Requirement C Compliance:** Phase 2 explicitly requires that **only** authorized edge nodes (Mac 1 Standby Edge and Mac 2 Primary Edge) can access backend ports; all other clients must be denied.

### Security Remediation Plan:
1. **Network Layer (Packet Filter `pfctl`):**
   - Create a dedicated anchor file (`config/pf_backend.rules` or `/etc/pf.anchors/backend_service`).
   - Rule logic:
     ```pf
     # Allow loopback
     pass in quick on lo0 proto tcp to port {3001, 3002}
     # Allow authorized edge nodes only
     pass in quick proto tcp from $MAC1_IP to any port {3001, 3002}
     pass in quick proto tcp from $MAC2_IP to any port {3001, 3002}
     # Block and drop all other traffic to backend ports
     block drop in quick proto tcp to any port {3001, 3002}
     ```
2. **Application Layer (Defense-in-Depth Middleware):**
   - Implement an IP validation middleware in Express for both Backend A and Backend B:
     ```javascript
     const ALLOWED_IPS = new Set(['127.0.0.1', '::1', MAC1_IP, MAC2_IP]);
     // Normalize remote IPv4/IPv6 addresses and reject unauthorized callers with 403 Forbidden
     ```
   - This provides bulletproof dual-layer security even if host packet filter rules are temporarily disabled or flushed.

---

## 10. Repository & Phase 1 Integrity

- Git status: Workspace is completely intact.
- Phase 1 baseline artifacts and evidence preserved in `architecture/`, `config/`, and `evidence/`.
- No files deleted or destroyed.

---

## 11. Proposed Stage 2 Implementation Plan for Mac 3

Upon receipt of confirmed IP addresses from Mihika (Mac 1) and Priyanshu (Mac 2):

1. **Step 1: Enhance Express Application Architecture**
   - Update `backend/backend-a/server.js` and `backend/backend-b/server.js`:
     - Add `GET /health` returning `{"status": "UP", "backend": "A" / "B", "timestamp": "..."}` with HTTP 200.
     - Add dual-layer access control middleware restricting callers to `MAC1_IP`, `MAC2_IP`, and loopback.
     - Ensure `X-Backend: A` and `X-Backend: B` headers remain present on all routes.
2. **Step 2: Process Management & Automation Scripts**
   - In `backend/`:
     - `start-a.sh` / `stop-a.sh` (Independently start and stop Backend A on port 3001)
     - `start-b.sh` / `stop-b.sh` (Independently start and stop Backend B on port 3002)
     - `start-all.sh` / `stop-all.sh`
     - `health-check.sh` (Queries `http://localhost:3001/health` and `http://localhost:3002/health`)
3. **Step 3: Security & Firewall Enforcement**
   - Create `config/pf_backend.conf` scoped specifically to ports 3001 & 3002 and peer edge IPs.
   - Provide non-destructive activation/deactivation commands (`pfctl -a backend -f ...`).
4. **Step 4: Integration, Failover & Recovery Testing**
   - Create automated test script `test-backend-failover.sh` to execute the 8 required steps:
     1. Both backends running.
     2. Verify responses alternating via nginx (`X-Backend: A`, `X-Backend: B`).
     3. Stop Backend A.
     4. Verify 100% of responses routed through Backend B (`X-Backend: B`).
     5. Restart Backend A.
     6. Verify traffic alternates across both again.
     7. Stop Backend B and verify 100% traffic routed through Backend A.
     8. Restart Backend B and verify full recovery.
5. **Step 5: Access Security Verification Testing**
   - Test authorized request from Mac 2 -> HTTP 200.
   - Test authorized request from Mac 1 -> HTTP 200.
   - Test unauthorized request from third IP or test client -> Dropped / 403 Forbidden.
   - Capture packet headers and terminal outputs in `evidence/`.

---

## 12. Input Needed From Peers Before Entering Stage 2

1. **Mac 1 (Mihika):** Verified IP address on the shared network (`MAC1_IP`).
2. **Mac 2 (Priyanshu):** Verified IP address on the shared network (`MAC2_IP`).
3. **Network Mode:** Confirmation whether all 3 machines can communicate over the Wi-Fi LAN or if we switch to Tailscale.
