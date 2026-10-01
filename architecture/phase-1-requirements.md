# Phase 1 Requirements & Verification Checklist

This document defines the actionable requirements, verification criteria, and completion gates for Phase 1 of the Private Network Service Platform.

---

## 1. Task-by-Task Requirements Checklist

### Task A: Network Foundation & Connectivity Setup
- [ ] **LAN Interconnection:** Ensure all 3 macOS laptops are connected to the same physical or Wi-Fi local area network (single broadcast domain).
- [ ] **Interface & Address Recording:** Record active network parameters for all machines in `architecture/ip-service-table.md`:
  - Active Interface (e.g., `en0`)
  - IPv4 Address (`MAC1_IP`, `MAC2_IP`, `MAC3_IP`)
  - Subnet Mask & CIDR Prefix (`SUBNET_PREFIX`)
  - Default Gateway IP (`DEFAULT_GATEWAY_IP`)
  - Hardware MAC Address (`MAC1_MAC_ADDR`, `MAC2_MAC_ADDR`, `MAC3_MAC_ADDR`)
- [ ] **ICMP Reachability:** Verify bidirectional `ping` reachability between all pairs of machines (Mac 1 $\leftrightarrow$ Mac 2 $\leftrightarrow$ Mac 3).
- [ ] **Topology Diagram:** Complete and verify the topology specification in `architecture/topology.md`.

---

### Task B: Private DNS Infrastructure
- [ ] **DNS Daemon:** Run `dnsmasq` service on Mac 1 listening on UDP port `53`.
- [ ] **Domain Mapping:** Configure custom DNS records targeting Mac 2:
  - `app.teamX.test` $\rightarrow$ `MAC2_IP`
  - `api.teamX.test` $\rightarrow$ `MAC2_IP`
- [ ] **Multi-Client Verification:** Configure at least two client machines to use `MAC1_IP` as their primary DNS resolver.
- [ ] **Query Verification:** Validate DNS resolution using `dig` and `nslookup`:
  ```bash
  dig @MAC1_IP app.teamX.test
  nslookup app.teamX.test MAC1_IP
  ```

---

### Task C: Dual Backend HTTP Services
- [ ] **Backend A Deployment:** Run Node.js HTTP server on Mac 3 listening on TCP port `3001`.
- [ ] **Backend B Deployment:** Run Node.js HTTP server on Mac 3 listening on TCP port `3002`.
- [ ] **Required Routes:** Implement the following endpoints on both backends:
  - `GET /` — Serves baseline application response.
  - `GET /api/status` — Serves health/status information.
- [ ] **Tracking Header:** Ensure each backend injects the custom response header:
  - Backend A: `X-Backend: A`
  - Backend B: `X-Backend: B`

---

### Task D: Reverse Proxy & Load Balancing (Edge Layer)
- [ ] **Reverse Proxy Configuration:** Deploy `nginx` on Mac 2 acting as the single edge ingress.
- [ ] **Load Balancing Algorithm:** Configure an upstream cluster with **Round-Robin** distribution targeting:
  - `MAC3_IP:3001`
  - `MAC3_IP:3002`
- [ ] **Network Isolation:** Ensure clients only connect to Mac 2 (`nginx`); clients never make direct requests to backend ports `3001` or `3002` on Mac 3.

---

### Task E: Transport Layer Security (TLS/HTTPS)
- [ ] **HTTPS Ingress:** Configure `nginx` on Mac 2 to listen for secure traffic on TCP port `443` (or `8443`).
- [ ] **TLS Termination:** Terminate TLS at `nginx` (traffic between Mac 2 and Mac 3 remains internal plaintext HTTP).
- [ ] **Certificate Generation:** Create a local certificate and private key matching domain `*.teamX.test` / `app.teamX.test`.
- [ ] **Client Trust Store:** Install and trust the CA / certificate on client machines so HTTPS requests succeed natively without security warnings.
- [ ] **Strict Verification Rule:** Final demonstration must execute cleanly **without** the insecure flag (`curl -k` / `curl --insecure` is strictly forbidden in final demo).

---

### Task F: HTTP Caching Behaviors
- [ ] **Cache Headers:** Implement standard caching headers (`Cache-Control: max-age=...`, `public` / `private`).
- [ ] **Validation Headers:** Implement entity tags (`ETag`) or `Last-Modified` validation headers.
- [ ] **Cache Verification:** Demonstrate HTTP cache hits and conditional `304 Not Modified` responses when revalidating requests.

---

### Task G: Network Packet Evidence & Protocol Analysis
Collect network capture evidence (using Wireshark or `tcpdump`) verifying:
- [ ] **DNS Resolution:** UDP packet capturing query and response for `app.teamX.test`.
- [ ] **TCP 3-Way Handshake:** Capture `SYN`, `SYN-ACK`, `ACK` exchange on port `443`/`8443`.
- [ ] **TLS Handshake:** Capture `ClientHello`, `ServerHello`, Certificate, and Cipher Suite negotiation.
- [ ] **Encrypted Application Data:** Capture Application Data records confirming encrypted payload transmission over the wire.
- [ ] **HTTP Headers:** Capture plaintext HTTP headers at the backend layer (showing `Host`, `X-Backend`, `Cache-Control`).
- [ ] **Load Balancing Distribution:** Capture consecutive requests proving distribution across Backend A (`:3001`) and Backend B (`:3002`).
- [ ] **Port Breakdown:** Document source/destination ports for each protocol flow.

---

## 2. Phase 1 Completion Gate

To successfully pass the Phase 1 milestone, the following end-to-end integration flow must execute successfully:

> **Phase 1 Pass Criteria:**
> A client machine on the network must:
> 1. Resolve domain `app.teamX.test` through the private DNS server on Mac 1.
> 2. Establish a trusted HTTPS connection to Mac 2 on port `443` (or `8443`) with zero certificate errors.
> 3. Receive valid HTTP responses alternating between Backend A (`X-Backend: A`) and Backend B (`X-Backend: B`) proxied through `nginx`.
