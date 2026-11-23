# Phase 2 — Primary Edge NGINX Verification Report (Mac 2 — Priyanshu)

**Machine:** Mac 2 (Priyanshu) — `10.200.251.227`  
**Role:** Primary Edge Reverse Proxy, TLS Terminator, and Load Balancer  
**Remote Backend Host:** Mac 3 (Saksham) — `10.200.251.76` (`:3001` Backend A, `:3002` Backend B)  
**Configuration File:** [config/nginx.conf](file:///Users/priyanshuagrahari/Desktop/Computer-Networks/config/nginx.conf) (mirrored to `/opt/homebrew/etc/nginx/nginx.conf`)  
**Execution Timestamp:** 2026-11-23T22:40:00+05:30  

---

## 1. Architecture & Design Principles

```
  Clients (Mac 1, Mac 2, Mac 3)
           │
           │ HTTPS (:8443) / HTTP (:8080 redirect)
           ▼
┌──────────────────────────────────────────────┐
│  MAC 2 — PRIMARY EDGE (10.200.251.227)        │
│  • NGINX 1.31.6                              │
│  • Master PID: 70698, Worker PID: 71212       │
│  • TLS Termination (Dual-SAN local cert)     │
│  • Round-Robin Upstream Load Balancer        │
│  • Passive Health Checks (max_fails=1)       │
└──────────────────────┬───────────────────────┘
                       │
         ┌─────────────┴─────────────┐
         ▼                           ▼
┌─────────────────┐         ┌─────────────────┐
│   BACKEND A     │         │   BACKEND B     │
│ 10.200.251.76   │         │ 10.200.251.76   │
│ Port 3001       │         │ Port 3002       │
└─────────────────┘         └─────────────────┘
```

---

## 2. Process & Listening State

NGINX runs under unprivileged user account `priyanshuagrahari`, completely decoupled from root and separate from `dnsmasq`:

```bash
$ ps aux | grep -E "nginx|dnsmasq" | grep -v grep
nobody           78501   0.0  0.0 488786176    288   ??  S     3:47PM   0:01.03 /opt/homebrew/sbin/dnsmasq -C /Users/priyanshuagrahari/Desktop/Computer-Networks/config/dnsmasq-backup.conf
priyanshuagrahari 71212   0.0  0.0 488794256    256   ??  S     1:19PM   0:00.06 nginx: worker process
priyanshuagrahari 70698   0.0  0.0 488794256    320   ??  Ss    1:16PM   0:00.01 nginx: master process nginx
```

Active listening sockets:
```bash
$ netstat -an | grep -E '\.(8443|8080) '
tcp4       0      0  *.8080                 *.*                    LISTEN     
tcp4       0      0  *.8443                 *.*                    LISTEN     
```

---

## 3. Configuration Audit

### A. Upstream Pool & Passive Health Checks
```nginx
upstream backend_servers {
    server 10.200.251.76:3001 max_fails=1 fail_timeout=10s;
    server 10.200.251.76:3002 max_fails=1 fail_timeout=10s;
}
```
- Open-source passive monitoring: If a backend fails or times out, NGINX marks it unavailable for 10 seconds.
- Failover directives:
  ```nginx
  proxy_connect_timeout     2s;
  proxy_read_timeout        5s;
  proxy_next_upstream       error timeout invalid_header http_500 http_502 http_503 http_504;
  proxy_next_upstream_tries 2;
  ```

### B. Virtual Hosts & TLS Termination
- Virtual hosts: `app.teamX.test` and `api.teamX.test`
- SSL Certificate: `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem`
- Private Key: `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test-key.pem`
- Protocols: `TLSv1.2 TLSv1.3`
- Ciphers: `HIGH:!aNULL:!MD5; ssl_prefer_server_ciphers on;`

### C. HTTP to HTTPS Redirection
```nginx
server {
    listen       8080;
    server_name  app.teamX.test api.teamX.test;
    return 301 https://$host:8443$request_uri;
}
```

---

## 4. Verification Evidence & Test Results

### Test 1: TLS Certificate Validation
```bash
$ openssl x509 -in /opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem -noout -subject -issuer -dates -ext subjectAltName
subject=O=mkcert development certificate, OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)
issuer=O=mkcert development CA, OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari), CN=mkcert priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)
notBefore=Nov 23 06:12:55 2026 GMT
notAfter=Feb 23 06:12:55 2029 GMT
X509v3 Subject Alternative Name: 
    DNS:app.teamX.test, DNS:api.teamX.test
```
Certificate and private key modulus match confirmed (`MD5: ec8a566434c3064c4c3e472cde29a29e`).

### Test 2: Native HTTPS Verification (`app.teamX.test:8443`)
```bash
$ curl -i --cacert "$MKCERT_CA" --resolve app.teamX.test:8443:10.200.251.227 https://app.teamX.test:8443/
HTTP/1.1 200 OK
Server: nginx/1.31.6
Content-Type: application/json; charset=utf-8
Content-Length: 62
Connection: keep-alive
X-Powered-By: Express
X-Backend: A
ETag: W/"3e-QF9vFacPifwgRXeqh9wcQA56VjA"

{"backend":"A","status":"ok","message":"Backend A is running"}
```

### Test 3: API Endpoint Verification (`api.teamX.test:8443/api/status`)
```bash
$ curl -i --cacert "$MKCERT_CA" --resolve api.teamX.test:8443:10.200.251.227 https://api.teamX.test:8443/api/status
HTTP/1.1 200 OK
Server: nginx/1.31.6
Content-Type: application/json; charset=utf-8
Content-Length: 29
Connection: keep-alive
X-Powered-By: Express
X-Backend: B
Cache-Control: public, max-age=60
ETag: W/"1d-/mMMZex8nvIDi44lSUobi0vFg/M"

{"backend":"B","status":"ok"}
```
Confirmed: `Cache-Control: public, max-age=60` and `X-Backend: B` headers passed through intact.

### Test 4: HTTP 8080 Permanent Redirect
```bash
$ curl -i --resolve app.teamX.test:8080:10.200.251.227 http://app.teamX.test:8080/
HTTP/1.1 301 Moved Permanently
Server: nginx/1.31.6
Location: https://app.teamx.test:8443/
Content-Type: text/html
Content-Length: 169
```

### Test 5: Round-Robin Load-Balancing (10 Consecutive Requests)
```bash
Request #1  -> HTTP/1.1 200 OK | X-Backend: A
Request #2  -> HTTP/1.1 200 OK | X-Backend: B
Request #3  -> HTTP/1.1 200 OK | X-Backend: A
Request #4  -> HTTP/1.1 200 OK | X-Backend: B
Request #5  -> HTTP/1.1 200 OK | X-Backend: A
Request #6  -> HTTP/1.1 200 OK | X-Backend: B
Request #7  -> HTTP/1.1 200 OK | X-Backend: A
Request #8  -> HTTP/1.1 200 OK | X-Backend: B
Request #9  -> HTTP/1.1 200 OK | X-Backend: A
Request #10 -> HTTP/1.1 200 OK | X-Backend: B
```
Distribution: Exactly 50% Backend A, 50% Backend B in strict alternating sequence.

### Test 6: Backend Failover
- When Backend A was taken offline: 100% of requests routed to Backend B with zero client-facing errors.
- When Backend B was taken offline: 100% of requests routed to Backend A with zero client-facing errors.
- When both recovered: Automatic restoration of 50/50 round-robin alternation.
