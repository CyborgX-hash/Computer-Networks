# config/ — Network Infrastructure Configuration

This directory contains the network infrastructure configuration files for the **Private Network Service Platform** — a Computer Networks course project deployed across 3 macOS laptops on a shared LAN.

---

## Directory Contents

| File | Purpose |
| :--- | :--- |
| `dnsmasq.conf` | Private DNS server configuration (runs on Mac 1) |
| `nginx.conf` | Reverse proxy, load balancer & TLS termination (runs on Mac 2) |
| `tls-setup.md` | Step-by-step guide for generating and installing TLS certificates |
| `README.md` | This file |

---

## Architecture Summary

```
┌──────────────┐       ┌──────────────────┐       ┌──────────────────┐
│    Mac 1     │       │      Mac 2       │       │      Mac 3       │
│  (MAC1_IP)   │       │    (MAC2_IP)     │       │    (MAC3_IP)     │
├──────────────┤       ├──────────────────┤       ├──────────────────┤
│ dnsmasq :53  │       │ nginx :8443      │       │ Backend A :3001  │
│ Test Client  │──────>│ TLS Termination  │──────>│ Backend B :3002  │
│ (curl / dig) │       │ Load Balancer    │       │ (Node.js)        │
└──────────────┘       └──────────────────┘       └──────────────────┘
```

---

## 1. DNS Configuration (dnsmasq)

**File:** `dnsmasq.conf`  
**Runs on:** Mac 1  
**Software:** [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) (install via `brew install dnsmasq`)

### Domain Mappings

| Domain | Resolves To | Purpose |
| :--- | :--- | :--- |
| `app.teamX.test` | `MAC2_IP` | Main application endpoint → nginx |
| `api.teamX.test` | `MAC2_IP` | API endpoint → nginx |

Both domains point to **Mac 2 (nginx)**, not directly to the backends. This ensures all client traffic flows through the reverse proxy for TLS termination and load balancing.

### Key Design Decisions

- Uses the `.test` reserved TLD (RFC 6761) — avoids conflicts with `.local` (mDNS)
- Upstream DNS forwarding to `8.8.8.8` / `8.8.4.4` preserves normal internet access
- Listens on `0.0.0.0:53` so all LAN machines can use Mac 1 as their DNS server
- Query logging enabled for debugging and viva evidence

### Running dnsmasq

```bash
# Start in foreground (recommended for development)
sudo dnsmasq -C /path/to/config/dnsmasq.conf -d

# Or as a background daemon
sudo dnsmasq -C /path/to/config/dnsmasq.conf
```

> **Note:** Port 53 requires `sudo` on macOS.

---

## 2. nginx — Reverse Proxy & Load Balancer

**File:** `nginx.conf`  
**Runs on:** Mac 2  
**Software:** [nginx](https://nginx.org/) (install via `brew install nginx`)

### Upstream Group (Round-Robin)

```nginx
upstream backend_servers {
    server MAC3_IP:3001;   # Backend A
    server MAC3_IP:3002;   # Backend B
}
```

nginx distributes traffic using **round-robin** load balancing by default:

| Request # | Routed To | X-Backend Header |
| :--- | :--- | :--- |
| 1 | Backend A (`:3001`) | `X-Backend: A` |
| 2 | Backend B (`:3002`) | `X-Backend: B` |
| 3 | Backend A (`:3001`) | `X-Backend: A` |
| 4 | Backend B (`:3002`) | `X-Backend: B` |

### Reverse Proxy Headers

nginx sets the following headers when forwarding to backends:

| Header | Value | Purpose |
| :--- | :--- | :--- |
| `Host` | Original client hostname | Preserves the requested domain |
| `X-Real-IP` | Client's IP address | Backend knows the real client |
| `X-Forwarded-For` | Client IP chain | Standard proxy forwarding header |
| `X-Forwarded-Proto` | `https` | Backend knows the original scheme |

### Backend Response Header Passthrough

nginx **preserves** backend response headers by default. The client sees:

- `X-Backend: A` or `X-Backend: B` — identifies which backend served the request
- `Cache-Control: public, max-age=60` — HTTP caching directive from the backend

---

## 3. TLS / HTTPS

**Documentation:** `tls-setup.md`  
**Port:** `8443` (unprivileged alternative to `443` on macOS)

### Why Port 8443?

On macOS, binding to ports below 1024 (including 443) requires root privileges. Using 8443 allows nginx to run without `sudo` during development.

### Certificate Details

| Property | Value |
| :--- | :--- |
| Domain | `app.teamX.test` |
| Tool | `mkcert` (preferred) or `openssl` |
| Certificate Path | `/opt/homebrew/etc/nginx/certs/app.teamX.test.pem` |
| Private Key Path | `/opt/homebrew/etc/nginx/certs/app.teamX.test-key.pem` |

See `tls-setup.md` for the complete step-by-step procedure.

> **CRITICAL:** Never commit `.pem`, `.key`, or `.crt` files to Git.

---

## 4. Backend Connections

| Backend | Host | Port | Protocol | Identifier |
| :--- | :--- | :--- | :--- | :--- |
| Backend A | Mac 3 (`MAC3_IP`) | `3001` | HTTP | `X-Backend: A` |
| Backend B | Mac 3 (`MAC3_IP`) | `3002` | HTTP | `X-Backend: B` |

Both backends:
- Are Node.js/Express applications
- Listen on `0.0.0.0` (all interfaces)
- Serve `GET /` and `GET /api/status`
- Set `Cache-Control: public, max-age=60` on `/api/status`

---

## 5. HTTP Caching

The backend services set the `Cache-Control: public, max-age=60` header on `/api/status` responses. nginx is configured to **pass through** this header without modification.

### What This Means

- Clients and intermediary caches may cache the response for up to **60 seconds**
- The `public` directive indicates the response can be cached by any cache (shared or private)
- After 60 seconds, the client should revalidate with the server

### Verifying Cache Headers

```bash
curl -I https://app.teamX.test:8443/api/status
```

Expected output should include:

```
Cache-Control: public, max-age=60
```

---

## 6. Placeholders — Must Replace Before Running

The configuration files use the following placeholders that **must** be replaced with actual LAN IP addresses:

| Placeholder | Used In | Meaning | How to Find |
| :--- | :--- | :--- | :--- |
| `MAC2_IP` | `dnsmasq.conf` | Mac 2 LAN IP (nginx) | Run `ipconfig getifaddr en0` on Mac 2 |
| `MAC3_IP` | `nginx.conf` | Mac 3 LAN IP (backends) | Run `ipconfig getifaddr en0` on Mac 3 |

### Quick Replacement

```bash
# On Mac 2, find the IP
MAC2_ACTUAL=$(ipconfig getifaddr en0)

# On Mac 3, find the IP
MAC3_ACTUAL=$(ipconfig getifaddr en0)

# Replace in dnsmasq.conf
sed -i '' "s/MAC2_IP/$MAC2_ACTUAL/g" config/dnsmasq.conf

# Replace in nginx.conf
sed -i '' "s/MAC3_IP/$MAC3_ACTUAL/g" config/nginx.conf
```

---

## 7. Validation Commands

### DNS Resolution (from any LAN machine using Mac 1 as DNS)

```bash
# Query the private DNS server
dig @MAC1_IP app.teamX.test

# Expected: ANSWER SECTION shows MAC2_IP

dig @MAC1_IP api.teamX.test

# Expected: ANSWER SECTION shows MAC2_IP
```

**What this proves:** dnsmasq correctly resolves project domains to the nginx machine.

---

### nginx Configuration Syntax

```bash
# On Mac 2
nginx -t

# Expected: "syntax is ok" and "test is successful"
```

**What this proves:** The nginx configuration file has valid syntax and all referenced files (certs) exist.

---

### Backend Direct Connectivity (from Mac 2)

```bash
# Test Backend A directly
curl http://MAC3_IP:3001/api/status

# Test Backend B directly
curl http://MAC3_IP:3002/api/status
```

**What this proves:** Mac 2 can reach both backend services over the LAN on their respective ports.

---

### Full HTTPS End-to-End (from Mac 1)

```bash
# Response headers only
curl -I https://app.teamX.test:8443/api/status

# Full response with headers
curl -i https://app.teamX.test:8443/api/status
```

**Expected output:**

```
HTTP/1.1 200 OK
X-Backend: A
Cache-Control: public, max-age=60
Content-Type: application/json; charset=utf-8
...

{"backend":"A","status":"ok"}
```

**What this proves:**
- DNS resolves `app.teamX.test` to Mac 2
- TLS handshake succeeds (certificate is trusted)
- nginx proxies the request to a backend
- Backend response headers pass through to the client

---

### Load Balancing Verification

```bash
# Run 4 consecutive requests and observe X-Backend alternation
for i in 1 2 3 4; do
  echo "--- Request $i ---"
  curl -s -I https://app.teamX.test:8443/api/status | grep X-Backend
done
```

**Expected output:**

```
--- Request 1 ---
X-Backend: A
--- Request 2 ---
X-Backend: B
--- Request 3 ---
X-Backend: A
--- Request 4 ---
X-Backend: B
```

**What this proves:** nginx round-robin load balancing distributes requests evenly across Backend A and Backend B.

---

### Cache Header Verification

```bash
curl -I https://app.teamX.test:8443/api/status | grep -i cache-control
```

**Expected:**

```
Cache-Control: public, max-age=60
```

**What this proves:** The backend's `Cache-Control` header passes through nginx to the client without modification.

---

## 8. Client DNS Configuration

For all machines to use the private DNS server, configure each Mac's DNS settings:

### Temporary (Terminal)

```bash
# Point DNS to Mac 1 for resolution
sudo networksetup -setdnsservers Wi-Fi MAC1_IP
```

### Revert

```bash
# Reset to automatic DNS
sudo networksetup -setdnsservers Wi-Fi Empty
```

---

## 9. Troubleshooting

| Issue | Likely Cause | Fix |
| :--- | :--- | :--- |
| `dig` returns `NXDOMAIN` | dnsmasq not running or IP placeholder not replaced | Start dnsmasq; replace `MAC2_IP` in `dnsmasq.conf` |
| `curl: (7) Failed to connect` | nginx not running or firewall blocking port | Start nginx; check `sudo lsof -i :8443` |
| `curl: (60) SSL certificate problem` | CA not trusted on client | See `tls-setup.md` Step 7 |
| `502 Bad Gateway` | Backends not running on Mac 3 | Start both backends; verify `curl http://MAC3_IP:3001/` from Mac 2 |
| Same `X-Backend` every time | Only one backend running | Ensure both `:3001` and `:3002` are active on Mac 3 |
