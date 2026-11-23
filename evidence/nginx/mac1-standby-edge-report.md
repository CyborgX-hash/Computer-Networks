# Mac 1 (Mihika) — Standby Nginx Edge Implementation & Verification Report

**Machine:** Mac 1 — Mihika  
**Assigned Role:** Standby Edge Proxy & Primary DNS  
**Local IP:** `10.200.251.106`  
**Primary Edge Machine:** Mac 2 — Priyanshu (`10.200.251.227`)  
**Backend Machine:** Mac 3 — Saksham (`10.200.251.76`)  
**Backend A:** `10.200.251.76:3001`  
**Backend B:** `10.200.251.76:3002`  
**Date:** Mon Nov 23 12:13 IST 2026  
**Git Branch:** `architecture&DNS` (synchronized with `origin/main` @ `ddf3393`)  

---

## 1. Executive Summary

This report documents the implementation of the **Standby Nginx Edge Reverse Proxy** on Mac 1. The standby edge provides high-availability failover for the platform: if the primary edge on Mac 2 becomes unreachable or requires maintenance, client traffic can be migrated to Mac 1 via DNS.

### Key Milestones Completed:
1. **Git Synchronization:** Verified branch `architecture&DNS`, cleanly synchronized with latest `main` (`ddf3393`), preserving history and Phase 1 evidence.
2. **Primary Edge Inspection:** Inspected Mac 2's merged primary nginx configuration (`c0f2885` in `config/nginx.conf`), extracting all upstream parameters, failover behaviors, header forwarding directives, and TLS port settings.
3. **Nginx Installation:** Verified nginx was absent on Mac 1; installed open-source Nginx `1.31.9` via Homebrew (`/opt/homebrew/bin/nginx`). Confirmed ports `8443` and `8080` are completely free.
4. **Standby Configuration Authored:** Created `config/nginx-standby.conf` targeting Backend A (`:3001`) and Backend B (`:3002`) with identical passive health checks (`max_fails=1`, `fail_timeout=10s`) and seamless failover (`proxy_next_upstream`).
5. **TLS Certificate Gate (Phase 5 Enforced):** Inspected primary certificate on Mac 2 (`10.200.251.227:8443`). Verified that certificate files do not exist locally on Mac 1. In strict compliance with Phase 5 instructions, stopped TLS activation and documented the exact missing requirements rather than generating an incompatible self-signed certificate.
6. **Backend Verification from Mac 1:** Verified direct connectivity to both backend services on Mac 3 (`:3001` and `:3002`), confirming valid HTTP 200 responses and identifying headers (`X-Backend: A` and `X-Backend: B`).
7. **Primary Config Untouched:** Confirmed `config/nginx.conf` has zero modifications.

---

## 2. Git Synchronization Status

- **Current Local Branch:** `architecture&DNS`
- **Tracking / Base:** `origin/main` (`ddf3393 Merge pull request #8 from CyborgX-hash/Configuration`)
- **Status:** Clean working tree. No local unstaged changes or untracked binary artifacts.
- **Rules Adherence:** No commits made directly to `main`. No private keys or runtime logs committed.

---

## 3. Primary Nginx Implementation Inspection (Mac 2 Reference)

The reference architecture merged from Mac 2 (`c0f2885`) was audited:

| Component | Specification in `config/nginx.conf` | Standby Implementation Alignment |
|---|---|---|
| **Upstream Group** | `backend_servers` | Identical (`backend_servers`) |
| **Backend A Target** | `10.200.251.76:3001` | Identical |
| **Backend B Target** | `10.200.251.76:3002` | Identical |
| **Load Balancing** | Default Round-Robin | Identical |
| **Passive Failure Detection** | `max_fails=1 fail_timeout=10s` | Identical |
| **Automatic Failover** | `proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;` | Identical |
| **Upstream Retries** | `proxy_next_upstream_tries 2;` | Identical |
| **Upstream Timeouts** | `proxy_connect_timeout 2s; proxy_read_timeout 5s;` | Identical |
| **TLS Listener** | Port `8443 ssl` | Identical (`8443 ssl`) |
| **Virtual Hosts** | `app.teamX.test api.teamX.test` | Identical |
| **Protocols & Ciphers** | `TLSv1.2 TLSv1.3`, `HIGH:!aNULL:!MD5` | Identical |
| **Forwarding Headers** | `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto` | Identical |
| **Header Preservation** | `X-Backend`, `Cache-Control` passthrough | Identical |
| **HTTP Redirect** | Port `8080` $\rightarrow$ `https://$host:8443$request_uri` | Identical |

---

## 4. Nginx Installation on Mac 1

### Installation Command
```bash
brew install nginx
```

### Installation Verification
```bash
$ which nginx
/opt/homebrew/bin/nginx

$ nginx -v
nginx version: nginx/1.31.9

$ lsof -iTCP:8443 -iTCP:8080 -sTCP:LISTEN -P
(No output — ports 8443 and 8080 are free and ready for binding)
```

### Configuration Backup
The default Homebrew configuration was safely preserved prior to custom deployment:
```bash
cp /opt/homebrew/etc/nginx/nginx.conf /opt/homebrew/etc/nginx/nginx.conf.backup
```

---

## 5. Standby Nginx Configuration (`config/nginx-standby.conf`)

The complete standby reverse proxy configuration was deployed to `config/nginx-standby.conf`:

```nginx
worker_processes 1;
pid /opt/homebrew/var/run/nginx_standby_edge.pid;

events {
    worker_connections 128;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    upstream backend_servers {
        server 10.200.251.76:3001 max_fails=1 fail_timeout=10s;
        server 10.200.251.76:3002 max_fails=1 fail_timeout=10s;
    }

    server {
        listen       8443 ssl;
        server_name  app.teamX.test api.teamX.test;

        ssl_certificate      /opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem;
        ssl_certificate_key  /opt/homebrew/etc/nginx/certs/app-and-api.teamX.test-key.pem;

        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        proxy_connect_timeout     2s;
        proxy_read_timeout        5s;
        proxy_next_upstream       error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries 2;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        location / {
            proxy_pass http://backend_servers;
        }

        location /api/ {
            proxy_pass http://backend_servers;
        }
    }

    server {
        listen       8080;
        server_name  app.teamX.test api.teamX.test;

        return 301 https://$host:8443$request_uri;
    }
}
```

---

## 6. TLS Certificate Audit & Security Gate (Phase 5)

### 6.1 Primary Certificate Inspection (Remote probe to Mac 2)
A live probe was conducted from Mac 1 to Mac 2's primary listener:
```bash
echo | openssl s_client -connect 10.200.251.227:8443 -servername app.teamX.test | openssl x509 -text -noout
```

**Captured Attributes:**
- **Issuer:** `O=mkcert development CA, OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local (Priyanshu Agrahari)`
- **Subject:** `O=mkcert development certificate, OU=priyanshuagrahari@Priyanshus-MacBook-Pro-2.local`
- **Validity:** Oct 3, 2026 to Jan 3, 2029
- **SANs:** `X509v3 Subject Alternative Name: DNS:app.teamX.test` *(Note: `api.teamX.test` is not yet present on the currently active certificate on Mac 2)*.

### 6.2 Mac 1 Local Certificate Audit
An exhaustive search of Mac 1's filesystem and Keychain revealed:
- `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem`: **MISSING**
- `/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test-key.pem`: **MISSING**
- Priyanshu's root CA in macOS Keychain: **NOT FOUND**

### 6.3 Syntax Test & Phase 5 Gate Enforcement
Running `nginx -t` against the standby configuration:
```bash
$ nginx -t -c /opt/homebrew/etc/nginx/nginx-standby.conf
nginx: [emerg] cannot load certificate "/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem": BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory)
nginx: configuration file /opt/homebrew/etc/nginx/nginx-standby.conf test failed
```

> [!IMPORTANT]
> **Phase 5 Gate Active:** In accordance with the mandatory requirement:
> *"If the required certificate and private key are not securely available on Mac 1, stop TLS activation and report the exact missing requirements. Do not create an incompatible certificate merely to make nginx -t pass."*
> TLS daemon activation on Mac 1 is **paused** until the shared certificate bundle is securely copied to Mac 1.

### 6.4 Requirements for Final TLS Activation on Mac 1
Priyanshu (Mac 2) must securely transfer the dual-SAN certificate bundle to Mac 1:
1. Create directory on Mac 1:
   ```bash
   mkdir -p /opt/homebrew/etc/nginx/certs
   ```
2. Copy files from Mac 2 to Mac 1:
   ```bash
   scp priyanshu@10.200.251.227:/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test.pem /opt/homebrew/etc/nginx/certs/
   scp priyanshu@10.200.251.227:/opt/homebrew/etc/nginx/certs/app-and-api.teamX.test-key.pem /opt/homebrew/etc/nginx/certs/
   ```
3. Import and trust Priyanshu's root CA on Mac 1 (so curl succeeds without `-k`):
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain rootCA.pem
   ```
4. Start Standby Nginx:
   ```bash
   nginx -c /opt/homebrew/etc/nginx/nginx-standby.conf
   ```

---

## 7. Direct Backend Verification from Mac 1

To confirm that the standby reverse proxy upstream targets are operational, live requests were made directly from Mac 1 (`10.200.251.106`) to Mac 3 (`10.200.251.76`):

### 7.1 Backend A (`10.200.251.76:3001`)
```http
GET /health HTTP/1.1
Host: 10.200.251.76:3001

HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: A
Content-Type: application/json; charset=utf-8
Content-Length: 80

{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T06:43:08.007Z"}
```

```http
GET / HTTP/1.1
Host: 10.200.251.76:3001

HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: A
Content-Type: application/json; charset=utf-8
Content-Length: 62

{"backend":"A","status":"ok","message":"Backend A is running"}
```

### 7.2 Backend B (`10.200.251.76:3002`)
```http
GET /health HTTP/1.1
Host: 10.200.251.76:3002

HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: B
Content-Type: application/json; charset=utf-8
Content-Length: 80

{"status":"UP","backend":"B","port":3002,"timestamp":"2026-11-23T06:43:08.070Z"}
```

```http
GET / HTTP/1.1
Host: 10.200.251.76:3002

HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: B
Content-Type: application/json; charset=utf-8
Content-Length: 62

{"backend":"B","status":"ok","message":"Backend B is running"}
```

✅ **Verification Result:** Both backend instances are active, healthy, and accessible from Mac 1's network stack.

---

## 8. Verification Matrix

| Checkpoint | Target | Expected | Observed | Status |
|---|---|---|---|---|
| Git synchronization | Branch `architecture&DNS` | In sync with `main` (`ddf3393`) | Fast-forwarded, clean tree | ✅ PASS |
| Primary config inspection | `config/nginx.conf` | Analyzed upstreams & failover | Upstreams `:3001` & `:3002` verified | ✅ PASS |
| Nginx installation | Mac 1 | Nginx 1.31.9 installed via brew | Installed (`/opt/homebrew/bin/nginx`) | ✅ PASS |
| Port 8443 availability | Mac 1 | Free for binding | Verified free (`lsof`) | ✅ PASS |
| Standby config authoring | `config/nginx-standby.conf` | Mirror of Mac 2 architecture | Authored with matching directives | ✅ PASS |
| Primary config integrity | `config/nginx.conf` | Zero changes | Untouched (`git status`) | ✅ PASS |
| TLS certificate check | `/opt/homebrew/etc/nginx/certs` | File existence audit | Missing — halted per Phase 5 | ⏸️ GATED |
| Backend A direct reachability | `10.200.251.76:3001` | HTTP 200, `X-Backend: A` | HTTP 200, `X-Backend: A` | ✅ PASS |
| Backend B direct reachability | `10.200.251.76:3002` | HTTP 200, `X-Backend: B` | HTTP 200, `X-Backend: B` | ✅ PASS |
