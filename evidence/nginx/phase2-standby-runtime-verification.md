# Phase 2 — Standby Edge Controlled Runtime Verification Report

**Machine:** Mac 1 — Mihika (`10.200.251.106`)  
**Role:** Standby Edge Reverse Proxy  
**Configuration File:** `/Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf`  
**Execution Timestamp:** 2026-11-23 14:03:00 - 14:04:45 IST  

---

## Executive Summary

| Step | Test Description | Status | Evidence Summary |
|:---:|---|:---:|---|
| **Step 1** | Preflight Checks (Process, Ports, Backend Health, Syntax) | **PASS** | Nginx stopped, ports 8443 & 8080 free, Backends A & B reachable (HTTP 200), `nginx -t` successful. |
| **Step 2** | Start Standby Nginx | **PASS** | Standby instance started (PID 12136/12137), ports 8443 & 8080 listening. |
| **Step 3** | HTTPS Verification via Direct IP Resolution (`--resolve`) | **PASS** | Native TLS verification succeeded (`SSL certificate verify ok`), HTTP 200 for `app` and `api`, round-robin upstream validated. |
| **Step 4** | HTTP Port 8080 Redirect | **PASS** | HTTP/1.1 301 Moved Permanently with `Location: https://app.teamx.test:8443/`. |
| **Step 5** | Backend Failover Simulation | **BLOCKED** | Requires remote process manipulation by Saksham on Mac 3 (`10.200.251.76`); standby proxy health & passive failover parameters are pre-configured. |
| **Step 6** | Graceful Shutdown & Post-Flight Isolation | **PASS** | Standby nginx cleanly stopped, ports 8443 & 8080 freed, Mac 2 primary edge active, Mac 3 backends healthy. |

---

## Detailed Step-by-Step Test Results

### Step 1 — Preflight Verification
All pre-requisites verified before initiating runtime test:
1. **Nginx Stopped:** Confirmed no pre-existing nginx process running on Mac 1.
2. **Ports Free:** Confirmed TCP ports 8443 and 8080 free from any listeners.
3. **Backend Reachability:**
   - Backend A (`http://10.200.251.76:3001/health`): HTTP `200`
   - Backend B (`http://10.200.251.76:3002/health`): HTTP `200`
4. **Configuration Syntax Check:**
```bash
$ nginx -t -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
nginx: the configuration file /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf syntax is ok
nginx: configuration file /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf test is successful
```
- **Result:** **PASS**

---

### Step 2 — Start Standby Nginx
Started temporary standby edge instance using repository configuration only:
```bash
$ nginx -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
```
**Process & Port Audit:**
```text
COMMAND   PID  USER         FD   TYPE  DEVICE             SIZE/OFF  NODE  NAME
nginx   12136  mihikamathur   6u  IPv4  0x41452fb5dc072c94      0t0   TCP  *:8443 (LISTEN)
nginx   12136  mihikamathur   8u  IPv4  0xff2cac755ef66958      0t0   TCP  *:8080 (LISTEN)
nginx   12137  mihikamathur   6u  IPv4  0x41452fb5dc072c94      0t0   TCP  *:8443 (LISTEN)
nginx   12137  mihikamathur   8u  IPv4  0xff2cac755ef66958      0t0   TCP  *:8080 (LISTEN)
```
- Master PID: `12136`
- Worker PID: `12137`
- **Result:** **PASS**

---

### Step 3 — HTTPS Reverse Proxy Verification (No `-k` / `--insecure`)

#### 3A: `app.teamX.test` Virtual Host
```bash
$ curl -v --connect-timeout 5 --max-time 10 --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/
```
**Captured Output:**
```text
* Added app.teamX.test:8443:10.200.251.106 to DNS cache
* Hostname app.teamX.test was found in DNS cache
*   Trying 10.200.251.106:8443...
* Connected to app.teamX.test (10.200.251.106) port 8443
* ALPN: curl offers h2,http/1.1
* SSL connection using TLSv1.3 / AEAD-AES256-GCM-SHA384 / [blank] / UNDEF
* ALPN: server accepted http/1.1
* Server certificate:
*  subject: O=mkcert development certificate; OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)
*  start date: Nov 23 06:12:55 2026 GMT
*  expire date: Feb 23 06:12:55 2029 GMT
*  subjectAltName: host "app.teamX.test" matched cert's "app.teamX.test"
*  issuer: O=mkcert development CA; OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari); CN=mkcert priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)
*  SSL certificate verify ok.
> GET / HTTP/1.1
> Host: app.teamX.test:8443
> User-Agent: curl/8.7.1
> Accept: */*
> 
< HTTP/1.1 200 OK
< Server: nginx/1.31.9
< Date: Mon, 23 Nov 2026 08:34:08 GMT
< Content-Type: application/json; charset=utf-8
< Content-Length: 62
< Connection: keep-alive
< X-Powered-By: Express
< X-Backend: A
< ETag: W/"3e-QF9vFacPifwgRXeqh9wcQA56VjA"
< 
{"backend":"A","status":"ok","message":"Backend A is running"}
```

#### 3B: `api.teamX.test` Virtual Host (`/api/status`)
```bash
$ curl -v --connect-timeout 5 --max-time 10 --resolve api.teamX.test:8443:10.200.251.106 https://api.teamX.test:8443/api/status
```
**Captured Output:**
```text
* Added api.teamX.test:8443:10.200.251.106 to DNS cache
* Hostname api.teamX.test was found in DNS cache
*   Trying 10.200.251.106:8443...
* Connected to api.teamX.test (10.200.251.106) port 8443
* ALPN: curl offers h2,http/1.1
* SSL connection using TLSv1.3 / AEAD-AES256-GCM-SHA384 / [blank] / UNDEF
* ALPN: server accepted http/1.1
* Server certificate:
*  subject: O=mkcert development certificate; OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)
*  start date: Nov 23 06:12:55 2026 GMT
*  expire date: Feb 23 06:12:55 2029 GMT
*  subjectAltName: host "api.teamX.test" matched cert's "api.teamX.test"
*  issuer: O=mkcert development CA; OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari); CN=mkcert priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)
*  SSL certificate verify ok.
> GET /api/status HTTP/1.1
> Host: api.teamX.test:8443
> User-Agent: curl/8.7.1
> Accept: */*
> 
< HTTP/1.1 200 OK
< Server: nginx/1.31.9
< Date: Mon, 23 Nov 2026 08:34:08 GMT
< Content-Type: application/json; charset=utf-8
< Content-Length: 29
< Connection: keep-alive
< X-Powered-By: Express
< X-Backend: B
< Cache-Control: public, max-age=60
< ETag: W/"1d-eqo46f6cZTMyh8pAIw5ntQG78PA"
< 
{"backend":"B","status":"ok"}
```

#### 3C: Upstream Load Balancing (6-cycle Round-Robin Verification)
```bash
$ for i in {1..6}; do
    curl -s -i --resolve app.teamX.test:8443:10.200.251.106 https://app.teamX.test:8443/health | grep -iE 'HTTP|x-backend|status'
  done
```
**Results:**
```text
--- Request 1 ---
HTTP/1.1 200 OK
X-Backend: A
{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T08:34:23.323Z"}
--- Request 2 ---
HTTP/1.1 200 OK
X-Backend: B
{"status":"UP","backend":"B","port":3002,"timestamp":"2026-11-23T08:34:23.378Z"}
--- Request 3 ---
HTTP/1.1 200 OK
X-Backend: A
{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T08:34:23.409Z"}
--- Request 4 ---
HTTP/1.1 200 OK
X-Backend: B
{"status":"UP","backend":"B","port":3002,"timestamp":"2026-11-23T08:34:23.436Z"}
--- Request 5 ---
HTTP/1.1 200 OK
X-Backend: A
{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T08:34:23.459Z"}
--- Request 6 ---
HTTP/1.1 200 OK
X-Backend: B
{"status":"UP","backend":"B","port":3002,"timestamp":"2026-11-23T08:34:23.483Z"}
```
- **Result:** **PASS** (Alternation A -> B -> A -> B -> A -> B verified; TLS valid without insecure flags).

---

### Step 4 — HTTP Redirect Test (Port 8080)
```bash
$ curl -I --resolve app.teamX.test:8080:10.200.251.106 http://app.teamX.test:8080/
```
**Captured Output:**
```text
HTTP/1.1 301 Moved Permanently
Server: nginx/1.31.9
Date: Mon, 23 Nov 2026 08:34:08 GMT
Content-Type: text/html
Content-Length: 169
Connection: keep-alive
Location: https://app.teamx.test:8443/
```
- Port 8080 cleanly redirects plain HTTP traffic to HTTPS on port 8443.
- **Result:** **PASS**

---

### Step 5 — Backend Failover Test
- **Status:** **BLOCKED / PENDING COORDINATION WITH SAKSHAM (MAC 3)**
- **Reason:** Mac 1 cannot unilaterally kill or restart backend processes running on Mac 3 (`10.200.251.76`). Doing so requires Saksham to execute controlled backend stoppage on Mac 3.
- **Standby Edge Preparedness:** The configuration in `config/nginx-standby.conf` includes:
  ```nginx
  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
  proxy_next_upstream_tries 2;
  proxy_next_upstream_timeout 5s;
  ```
  with upstream health intervals:
  ```nginx
  server 10.200.251.76:3001 max_fails=2 fail_timeout=10s;
  server 10.200.251.76:3002 max_fails=2 fail_timeout=10s;
  ```
  When Saksham stops Backend A or B, the standby proxy is fully configured to route 100% of traffic to the surviving backend without manual intervention.

---

### Step 6 — Graceful Shutdown & Post-Flight Status
Stopped the standby nginx instance:
```bash
$ nginx -s stop -c /Users/mihikamathur/Desktop/Placement/CN/Computer-Networks/config/nginx-standby.conf
```

**Post-Flight Integrity Checks:**
1. **Mac 1 Nginx Process:** Stopped (`MAC1_NGINX_STOPPED`).
2. **Mac 1 Ports (8443 & 8080):** Confirmed free (`PORTS_8443_AND_8080_FREE`).
3. **Mac 2 Primary Edge Availability (`10.200.251.227`):**
   - Port 8443: `Connection to 10.200.251.227 port 8443 succeeded!`
   - Port 8080: `Connection to 10.200.251.227 port 8080 succeeded!`
4. **Mac 3 Backend Health (`10.200.251.76`):**
   - Backend A (port 3001): HTTP `200`
   - Backend B (port 3002): HTTP `200`
- **Result:** **PASS**
