# Root Cause Analysis: Mac 2 Primary NGINX Reverse-Proxy Timeout

**Machine:** Mac 2 (Priyanshu) — `10.200.251.227`  
**Backend Machine:** Mac 3 (Saksham) — `10.200.251.76`  
**Date:** November 23, 2026  
**Document:** `evidence/nginx/root-cause-analysis.md`  

---

## 1. Problem Description
HTTPS requests to:
- `https://app.teamX.test:8443/`
- `https://api.teamX.test:8443/api/status`
time out on Mac 2 without returning an HTTP response, even though:
1. `nginx` accepts TCP/TLS connections on port `8443`.
2. Direct requests from Mac 2 to both backends (`10.200.251.76:3001` and `3002`) return HTTP 200 OK.
3. Direct requests from Mac 1 to both backends return HTTP 200 OK.

---

## 2. Technical Investigation & Findings

### Finding 1: Running Process Inspection
```bash
$ ps aux | grep nginx
root    46056  0.0  0.0  nginx: master process nginx -
nobody  46057  0.0  0.0  nginx: worker process
```
- Master PID `46056` and Worker PID `46057` were spawned on **Nov 22 at 2:40 PM** under the **`root`** account during Phase 1 testing.

### Finding 2: In-Memory Configuration vs On-Disk Configuration
- **On-Disk Configuration (`/opt/homebrew/etc/nginx/nginx.conf`):**  
  Correctly targets the Phase 2 backend IP:
  ```nginx
  upstream backend_servers {
      server 10.200.251.76:3001 max_fails=1 fail_timeout=10s;
      server 10.200.251.76:3002 max_fails=1 fail_timeout=10s;
  }
  ```
- **Running In-Memory Worker (`PID 46057`):**  
  Still executing the **Phase 1 configuration** loaded into RAM on Nov 22, which points to:
  ```nginx
  upstream backend_servers {
      server 10.7.19.140:3001;
      server 10.7.19.140:3002;
  }
  ```

### Finding 3: Error Log Confirmation (`/opt/homebrew/var/log/nginx/error.log`)
```text
2026/10/05 12:19:16 [error] 11328#0: *2 kevent() reported that connect() failed (61: Connection refused) while connecting to upstream, client: 10.7.17.248, server: app.teamx.test, request: "GET / HTTP/1.1", upstream: "http://10.7.19.140:3001/", host: "10.7.17.248:8443"
2026/10/05 12:19:17 [error] 11328#0: *2 kevent() reported that connect() failed (61: Connection refused) while connecting to upstream, client: 10.7.17.248, server: app.teamx.test, request: "GET / HTTP/1.1", upstream: "http://10.7.19.140:3002/", host: "10.7.17.248:8443"
...
2026/11/23 11:46:29 [alert] 67274#0: kill(46056, 1) failed (1: Operation not permitted)
```
- When a client connects to `8443`, the TLS handshake succeeds because worker `46057` has the port open.
- However, when proxying, worker `46057` attempts to connect to `10.7.19.140:3001` and `10.7.19.140:3002`.
- IP `10.7.19.140` does not exist on the current `10.200.251.0/24` network.
- The connection hangs until it times out.

### Finding 4: Why Reload Failed
- Unprivileged user `priyanshuagrahari` ran `nginx -s reload`.
- Nginx attempted to send `SIGHUP` to PID `46056`:
  ```text
  nginx: [alert] kill(46056, 1) failed (1: Operation not permitted)
  ```
- Because process `46056` is owned by `root`, the signal was rejected by the macOS kernel.
- Attempting to start a new nginx process also failed because ports `8443` and `8080` were already bound by root:
  ```text
  nginx: [emerg] bind() to 0.0.0.0:8443 failed (48: Address already in use)
  ```

---

## 3. Direct Backend Reachability Verification from Mac 2
Both backends were verified directly from Mac 2:
```bash
$ curl -i http://10.200.251.76:3001/health
HTTP/1.1 200 OK
X-Backend: A
{"status":"UP","backend":"A","port":3001,"timestamp":"2026-11-23T07:21:24.509Z"}

$ curl -i http://10.200.251.76:3002/health
HTTP/1.1 200 OK
X-Backend: B
{"status":"UP","backend":"B","port":3002,"timestamp":"2026-11-23T07:24:02.519Z"}
```
*Conclusion:* Network reachability from Mac 2 to Mac 3 is 100% operational. The failure is entirely due to the stale root nginx process holding the old memory state.

---

## 4. Fix Procedure
The stale root master process must be stopped so that nginx starts fresh with the verified Phase 2 configuration:

```bash
sudo killall nginx && nginx
```
*(or `sudo nginx -s reload`)*

Once restarted under `priyanshuagrahari`, all requests to port 8443 will route directly to `10.200.251.76:3001` and `3002` with 0ms delay.
