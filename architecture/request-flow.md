# Phase 1 Complete Request Flow & Protocol Specification

This document details the complete end-to-end request lifecycle for the Private Network Service Platform across the protocol stack.

---

## 1. End-to-End Request Flow Sequence

```
Client (Mac 1)            DNS (Mac 1:53)          Edge / Nginx (Mac 2)     Backend A/B (Mac 3)
     |                          |                          |                       |
     |--- (1) DNS Query ------->|                          |                       |
     |    app.teamX.test (A)    |                          |                       |
     |                          |                          |                       |
     |<-- (2) DNS Answer -------|                          |                       |
     |    IP: MAC2_IP           |                          |                       |
     |                                                     |                       |
     |--- (3) TCP SYN ------------------------------------>|                       |
     |<-- (3) TCP SYN-ACK ---------------------------------|                       |
     |--- (3) TCP ACK ------------------------------------>|                       |
     |                                                     |                       |
     |<=> (4) TLS Handshake (ClientHello / ServerHello) <=>|                       |
     |    (Encrypted Session Established)                  |                       |
     |                                                     |                       |
     |--- (5) HTTPS Request (Encrypted GET /) ------------>|                       |
     |                                                     |                       |
     |                                                     |-- (6) Forward HTTP -->|
     |                                                     |   (Round Robin :3001  |
     |                                                     |    or :3002)          |
     |                                                     |                       |
     |                                                     |<- (7) HTTP Response --|
     |                                                     |   (X-Backend: A or B) |
     |                                                     |                       |
     |<-- (8) HTTPS Encrypted Response --------------------|                       |
```

### Detailed Step-by-Step Flow

#### Step 1: DNS Query
The test client (or browser/curl) resolves the hostname `app.teamX.test` (or `api.teamX.test`). The operating system resolver constructs a standard DNS query packet for an `A` (IPv4 address) record and dispatches it to the designated DNS server (`MAC1_IP:53`) over UDP.

#### Step 2: DNS Resolution & Response
The `dnsmasq` service running on Mac 1 matches the query against its configured local domain table:
- `app.teamX.test` $\rightarrow$ `MAC2_IP`
- `api.teamX.test` $\rightarrow$ `MAC2_IP`

The DNS server returns the response containing `MAC2_IP` in the answer section back to the client over UDP port 53.

#### Step 3: TCP Connection Establishment (3-Way Handshake)
Having obtained the target IP (`MAC2_IP`), the client initiates a reliable stream connection to the edge proxy on port `443` (or `8443`):
1. **SYN**: Client sends `SYN` with an initial sequence number ($ISN_c$).
2. **SYN-ACK**: Mac 2 (`nginx`) acknowledges with `ACK = ` $ISN_c + 1$ and sends its own sequence number ($ISN_s$).
3. **ACK**: Client acknowledges with `ACK = ` $ISN_s + 1$. The TCP socket is now in `ESTABLISHED` state.

#### Step 4: TLS Cryptographic Handshake
Over the established TCP stream, client and server negotiate a secure TLS session:
1. **ClientHello**: Client sends supported TLS versions, cipher suites, and SNI (Server Name Indication: `app.teamX.test`).
2. **ServerHello + Certificate + Key Exchange**: `nginx` presents its server certificate (issued for `*.teamX.test` or `app.teamX.test`) and cryptographic parameters.
3. **Verification & Key Derivation**: The client validates the certificate against its local trusted CA/trust store. Symmetric session keys are derived.
4. **Finished**: Both parties verify the handshake integrity and switch to symmetric encryption (AES-GCM / ChaCha20-Poly1305).

#### Step 5: HTTPS Request Delivery
The client issues the application HTTP request over the encrypted TLS tunnel:
```http
GET / HTTP/1.1
Host: app.teamX.test
User-Agent: curl/8.x.x
Accept: */*
```
`nginx` decrypts the request payload at the edge.

#### Step 6: Upstream Load Balancing
`nginx` evaluates its configured `upstream` block. Using a **Round-Robin** algorithm, it alternates between available backend nodes hosted on Mac 3:
- Request $2k + 1 \rightarrow$ `http://MAC3_IP:3001` (Backend A)
- Request $2k + 2 \rightarrow$ `http://MAC3_IP:3002` (Backend B)

`nginx` forwards the plain HTTP request over an internal TCP connection to Mac 3.

#### Step 7: Backend Execution & Response Generation
The selected Node.js backend instance processes the request route (e.g., `GET /` or `GET /api/status`) and generates an HTTP response containing:
- Status line (e.g., `HTTP/1.1 200 OK`)
- Custom tracking header: `X-Backend: A` (or `X-Backend: B`)
- Content headers (`Content-Type: application/json` or `text/plain`, `Cache-Control`, `ETag`)
- Response body

The backend sends the HTTP response over the TCP connection back to `nginx`.

#### Step 8: Edge Response Delivery to Client
`nginx` receives the upstream response, handles edge caching headers if applicable, encapsulates and encrypts the response inside the client's TLS tunnel, and transmits the data over the client TCP socket. The client receives, decrypts, and renders the response.

---

## 2. Protocol Breakdown

| Protocol | OSI Layer | Transport / Underlay | Role in Platform |
| :--- | :--- | :--- | :--- |
| **DNS** (Domain Name System) | Layer 7 (Application) | UDP (Port 53) | Translates human-readable domain names (`app.teamX.test`) into routable IP addresses (`MAC2_IP`). |
| **UDP** (User Datagram Protocol) | Layer 4 (Transport) | IP (Network) | Connectionless, low-latency transport protocol utilized for DNS lookups without handshake overhead. |
| **TCP** (Transmission Control Protocol) | Layer 4 (Transport) | IP (Network) | Connection-oriented, reliable byte-stream protocol providing ordered delivery, flow control, and retransmission for web traffic and proxying. |
| **TLS** (Transport Layer Security) | Layer 5/6 (Session/Presentation) | TCP | Provides encryption, server authentication (via certificates), and data integrity for all client-to-edge traffic. |
| **HTTPS** (HTTP over TLS) | Layer 7 (Application) | TLS / TCP | Standard secure web communication protocol executing HTTP verbs inside an established TLS tunnel. |
| **HTTP** (Hypertext Transfer Protocol) | Layer 7 (Application) | TCP | Plaintext application protocol used between the internal edge proxy (`nginx`) and backend services (Node.js). |
| **Load Balancing** (Reverse Proxy Layer) | Layer 7 (Application Level) | TCP/HTTP | Distribution policy (Round-Robin) executed by `nginx` to balance workloads across multiple backend service instances. |

---

## 3. Port Allocation Summary

| Service | Host | Port | Transport Protocol | Notes / Fallbacks |
| :--- | :--- | :--- | :--- | :--- |
| **DNS Server (`dnsmasq`)** | Mac 1 | `53` | UDP | Standard DNS port; requires root/sudo to bind on macOS. |
| **HTTPS Edge Proxy (`nginx`)** | Mac 2 | `443` | TCP | Standard HTTPS port (or `8443` if unprivileged non-root execution is preferred). |
| **Backend Server A** | Mac 3 | `3001` | TCP | Dedicated Node.js instance A. |
| **Backend Server B** | Mac 3 | `3002` | TCP | Dedicated Node.js instance B. |
