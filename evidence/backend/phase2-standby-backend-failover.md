# Phase 2 — Coordinated Standby Backend Failover Verification

**Machine:** Mac 3 — Saksham (`10.200.251.76`)  
**Backend A:** Port `3001`  
**Backend B:** Port `3002`  
**Standby Edge Node:** Mac 1 — Mihika (`10.200.251.106:8443`)  
**Primary Edge Node:** Mac 2 — Priyanshu (`10.200.251.227:8443`)  
**Execution Timestamp:** 2026-11-23T14:44:11+05:30  
**Overall Result:** **PASS** (Zero failed requests during single backend outages)

---

## 1. Preflight Validation

All preflight gates were executed and confirmed before beginning failure simulations:

| Target / Component | Expected State | Actual Observed State | Result |
| :--- | :--- | :--- | :--- |
| **Backend A Local** | `http://127.0.0.1:3001/health` = `200` | HTTP `200 OK` | **PASS** |
| **Backend B Local** | `http://127.0.0.1:3002/health` = `200` | HTTP `200 OK` | **PASS** |
| **Mac 1 Standby Edge** | `10.200.251.106:8443` listening | TCP Handshake succeeded (`[tcp/pcsync-https] succeeded!`) | **PASS** |
| **Mac 2 Primary Edge** | `10.200.251.227:8443` listening | TCP Handshake succeeded (`[tcp/pcsync-https] succeeded!`) | **PASS** |

### Baseline Load Balancing Check (Both Backends Running)
```text
--- Baseline Request 1 --- Status: HTTP/1.1 200 OK | X-Backend: B | Body: {"backend":"B","status":"ok","message":"Backend B is running"}
--- Baseline Request 2 --- Status: HTTP/1.1 200 OK | X-Backend: A | Body: {"backend":"A","status":"ok","message":"Backend A is running"}
--- Baseline Request 3 --- Status: HTTP/1.1 200 OK | X-Backend: B | Body: {"backend":"B","status":"ok","message":"Backend B is running"}
--- Baseline Request 4 --- Status: HTTP/1.1 200 OK | X-Backend: A | Body: {"backend":"A","status":"ok","message":"Backend A is running"}
```

---

## 2. Test A — Backend A Outage & Automatic Failover

### Step 1: Backend A Teardown
- **Command:** `./backend/stop-a.sh`
- **Listener Verification:** `lsof -iTCP:3001 -sTCP:LISTEN -P -n` returned no process.
- **Port 3001 State:** `CONFIRMED: Port 3001 is closed and stopped.`

### Step 2: Ingress Requests via Mac 1 Standby Edge (`10.200.251.106:8443`)
12 consecutive requests were issued to Mac 1 standby nginx while Backend A was offline:

| Request # | Timestamp | HTTP Status | X-Backend Header | Response Payload |
| :---: | :---: | :---: | :---: | :--- |
| 1 | 14:44:15 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 2 | 14:44:16 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 3 | 14:44:17 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 4 | 14:44:17 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 5 | 14:44:18 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 6 | 14:44:18 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 7 | 14:44:19 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 8 | 14:44:19 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 9 | 14:44:20 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 10 | 14:44:20 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 11 | 14:44:20 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |
| 12 | 14:44:21 | `HTTP/1.1 200 OK` | `X-Backend: B` | `{"backend":"B","status":"ok","message":"Backend B is running"}` |

* **Total Requests:** 12
* **Successful Requests:** 12 (100%)
* **Failed Requests:** 0 (0%)
* **Evaluation:** Standby nginx detected the connection refusal on port 3001 and seamlessly routed 100% of client traffic to healthy Backend B without dropping any connections.

---

## 3. Recovery A — Backend A Restoration

- **Command:** `./backend/start-a.sh`
- **PID:** `63399`
- **Health Verification:** `curl -s http://127.0.0.1:3001/health` -> `HTTP 200 OK` (`HEALTHY`)
- **Traffic Resumption:** Upon recovery, Mac 1 standby edge automatically reintegrated Backend A into the active upstream pool.

---

## 4. Test B — Backend B Outage & Automatic Failover

### Step 1: Backend B Teardown
- **Command:** `./backend/stop-b.sh`
- **Listener Verification:** `lsof -iTCP:3002 -sTCP:LISTEN -P -n` returned no process.
- **Port 3002 State:** `CONFIRMED: Port 3002 is closed and stopped.`

### Step 2: Ingress Requests via Mac 1 Standby Edge (`10.200.251.106:8443`)
12 consecutive requests were issued to Mac 1 standby nginx while Backend B was offline:

| Request # | Timestamp | HTTP Status | X-Backend Header | Response Payload |
| :---: | :---: | :---: | :---: | :--- |
| 1 | 14:44:29 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 2 | 14:44:30 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 3 | 14:44:30 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 4 | 14:44:31 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 5 | 14:44:31 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 6 | 14:44:31 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 7 | 14:44:32 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 8 | 14:44:32 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 9 | 14:44:33 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 10 | 14:44:33 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 11 | 14:44:34 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |
| 12 | 14:44:34 | `HTTP/1.1 200 OK` | `X-Backend: A` | `{"backend":"A","status":"ok","message":"Backend A is running"}` |

* **Total Requests:** 12
* **Successful Requests:** 12 (100%)
* **Failed Requests:** 0 (0%)
* **Evaluation:** Standby nginx detected the connection refusal on port 3002 and immediately redirected 100% of client traffic to healthy Backend A with zero dropped requests.

---

## 5. Recovery B — Backend B Restoration & Final State

- **Command:** `./backend/start-b.sh`
- **PID:** `63766`
- **Health Verification:** `curl -s http://127.0.0.1:3002/health` -> `HTTP 200 OK` (`HEALTHY`)
- **Traffic Resumption:** Upon recovery, requests through Mac 1 standby edge resumed alternating between Backend A and Backend B:
  ```text
  [Recovery Request 7] -> HTTP/1.1 200 OK | X-Backend: A
  [Recovery Request 8] -> HTTP/1.1 200 OK | X-Backend: B
  ```

---

## 6. Final Health Summary

Inspected at Mon Nov 23 14:44:41 IST 2026:

* **Backend A (`:3001`):** `HEALTHY (HTTP 200)` — PID: `63399`
* **Backend B (`:3002`):** `HEALTHY (HTTP 200)` — PID: `63766`
* **Mac 1 Standby Edge (`10.200.251.106:8443`):** `Connection succeeded`
* **Mac 2 Primary Edge (`10.200.251.227:8443`):** `Connection succeeded`

**Verification Status:** **COMPLETE & VERIFIED (PASS)**.
