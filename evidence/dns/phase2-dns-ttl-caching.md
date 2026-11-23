# Phase 2 — DNS TTL Caching & Expiration Experiment Report

**Machine:** Mac 3 — Saksham (`10.200.251.76`)  
**Authoritative Upstream DNS:** Mac 2 — Priyanshu (`10.200.251.227:53`)  
**Caching Resolver:** Mac 3 Local Resolver (`127.0.0.1:5353`)  
**Test Domain Record:** `ttl-test.teamX.test`  
**Configured TTL:** 30 seconds  
**Execution Date:** 2026-11-23  
**Status:** **VERIFIED (PASS)**

---

## 1. Objective

To empirically demonstrate **Requirement B (DNS TTL and Caching)** in an isolated, reproducible environment:
1. Validate that an authoritative DNS record with a Time-To-Live (TTL) of 30 seconds is cached by a downstream resolver upon first query.
2. Demonstrate that subsequent queries within the 30-second TTL window are answered directly from the local cache with a decreasing TTL countdown, without contacting the upstream authoritative server.
3. Demonstrate that once the TTL expires (>30 seconds), a subsequent query causes the resolver to purge the stale cache entry and re-query the authoritative upstream server, fetching the updated IP address.

---

## 2. Architecture & Configuration

```
                     +---------------------------------------+
                     |        Authoritative DNS Server       |
                     |         Mac 2 (10.200.251.227)        |
                     |              dnsmasq :53              |
                     +---------------------------------------+
                                        ^
                                        | (UDP :53 / Upstream Forwarding)
                                        v
+---------------------------------------------------------------------------------+
| Mac 3 (10.200.251.76)                                                           |
|                                                                                 |
|   +----------------------------+             +-------------------------------+  |
|   |   Test Client (dig)        | <---------> | Local Caching Resolver        |  |
|   |   dig -p 5353 @127.0.0.1   |  (UDP 5353) | dnsmasq (127.0.0.1:5353)      |  |
|   +----------------------------+             | Cache Size: 100 entries       |  |
|                                              +-------------------------------+  |
+---------------------------------------------------------------------------------+
```

### Resolver Configuration (`/tmp/phase2-ttl-cache.conf`)
An isolated `dnsmasq` instance was configured and run strictly on localhost port 5353:
```conf
port=5353
listen-address=127.0.0.1
bind-interfaces
no-resolv
no-hosts
server=10.200.251.227
cache-size=100
log-queries
log-facility=/tmp/phase2-ttl-cache.log
```

---

## 3. Test Procedure

1. **Initial Resolution (Cache Miss):**
   - Query `ttl-test.teamX.test` via `dig -p 5353 @127.0.0.1 ttl-test.teamX.test`.
   - Observe packet forwarding to upstream Mac 2 (`10.200.251.227:53`).
   - Observe initial TTL = 30 seconds and IP = `192.0.2.10`.
2. **Intermediate Query within TTL Window (Cache Hit):**
   - Query `ttl-test.teamX.test` 8 seconds later (at t = 8s).
   - Verify that the query is answered locally from cache without forwarding to Mac 2.
   - Verify the remaining TTL has decreased to 22 seconds (30s - 8s).
3. **Upstream Record Modification:**
   - On Mac 2, Priyanshu updated the DNS record for `ttl-test.teamX.test` from `192.0.2.10` to `192.0.2.20` and reloaded `dnsmasq`.
4. **Post-Expiry Resolution (Cache Expiry & Re-fetch):**
   - Wait for the remaining TTL to expire (> 30 seconds elapsed).
   - Issue query at 15:47:14 (> 2.5 minutes later).
   - Verify that Mac 3's resolver recognizes cache expiration, forwards the request to Mac 2, and caches the new IP `192.0.2.20` with a fresh TTL of 30 seconds.
5. **Confirmation Query:**
   - Confirm persistent resolution of the updated record at 15:47:48.

---

## 4. Actual Observed Results & Terminal Timestamps

### Timeline of Captured Events

| Step | Timestamp | Query / Event | Action Taken by Resolver | Returned IP | TTL | Notes / Log Proof |
| :---: | :---: | :--- | :--- | :---: | :---: | :--- |
| **1** | **15:44:36** | `dig -p 5353 @127.0.0.1 ttl-test.teamX.test` | Forwarded query to Mac 2 (`10.200.251.227#53`) | `192.0.2.10` | `30` | **Cache Miss:** Initial query populated resolver cache. |
| **2** | **15:44:44** | `dig -p 5353 @127.0.0.1 ttl-test.teamX.test` | Answered directly from local cache (0ms query time) | `192.0.2.10` | `22` | **Cache Hit:** Exact 8s elapsed; TTL decremented 30 $\rightarrow$ 22. |
| **—** | **~15:45:06** | *TTL Expiry Window* | *Cache entry reaches TTL 0 and is invalidated* | — | — | Upstream Mac 2 updated record to `192.0.2.20`. |
| **3** | **15:47:14** | `dig -p 5353 @127.0.0.1 ttl-test.teamX.test` | Forwarded query to Mac 2 (`10.200.251.227#53`) | `192.0.2.20` | `30` | **Cache Expired & Refreshed:** Fetched updated IP with fresh TTL. |
| **4** | **15:47:48** | `dig -p 5353 @127.0.0.1 ttl-test.teamX.test` | Forwarded/Refreshed query | `192.0.2.20` | `30` | **Confirmed Resolution:** New address stably served. |

---

## 5. Actual Log Evidence (`/tmp/phase2-ttl-cache.log`)

The log entries captured from `dnsmasq[71724]` provide conclusive, timestamped verification:

```text
Nov 23 15:44:36 dnsmasq[71724]: query[A] ttl-test.teamx.test from 127.0.0.1
Nov 23 15:44:36 dnsmasq[71724]: forwarded ttl-test.teamx.test to 10.200.251.227
Nov 23 15:44:36 dnsmasq[71724]: reply ttl-test.teamx.test is 192.0.2.10

Nov 23 15:44:44 dnsmasq[71724]: query[A] ttl-test.teamx.test from 127.0.0.1
Nov 23 15:44:44 dnsmasq[71724]: cached ttl-test.teamx.test is 192.0.2.10

Nov 23 15:47:14 dnsmasq[71724]: query[A] ttl-test.teamx.test from 127.0.0.1
Nov 23 15:47:14 dnsmasq[71724]: forwarded ttl-test.teamx.test to 10.200.251.227
Nov 23 15:47:14 dnsmasq[71724]: reply ttl-test.teamx.test is 192.0.2.20

Nov 23 15:47:48 dnsmasq[71724]: query[A] ttl-test.teamx.test from 127.0.0.1
Nov 23 15:47:48 dnsmasq[71724]: forwarded ttl-test.teamx.test to 10.200.251.227
Nov 23 15:47:48 dnsmasq[71724]: reply ttl-test.teamx.test is 192.0.2.20
```

---

## 6. Technical Analysis: TTL Countdown & Cache Expiration

1. **TTL Countdown Mechanism:**
   When `dnsmasq` receives an authoritative DNS reply with `TTL = 30`, it records the timestamp of arrival. For any subsequent query arriving at $\Delta t$ seconds later (where $\Delta t < 30$), the resolver computes:
   $$\text{Remaining TTL} = \text{Original TTL} - \Delta t$$
   At `15:44:44` ($\Delta t = 8\text{ seconds}$), the resolver correctly replied with `TTL = 22` and logged:
   `cached ttl-test.teamx.test is 192.0.2.10`.
   No network packet was transmitted across the LAN to Mac 2.

2. **Cache Eviction upon Expiry:**
   Once $\Delta t \ge 30\text{ seconds}$, the cache entry becomes stale and invalid. When the next query arrived at `15:47:14` ($\Delta t \approx 158\text{ seconds}$), `dnsmasq` purged the expired record and forwarded the query upstream to Mac 2 (`10.200.251.227`), immediately obtaining the new IP `192.0.2.20` with a fresh 30-second TTL.

---

## 7. Limitations & Scope

* **Isolated Application-Level Resolver:** This experiment was conducted using an isolated user-space `dnsmasq` instance running on `127.0.0.1:5353`.
* **Not macOS System mDNSResponder:** This test did not modify or query macOS system-wide DNS (`mDNSResponder`), `/etc/resolv.conf`, or `/etc/resolver/test`. This ensured zero disruption to ongoing project services, edge proxies, or system internet connectivity.

---

## 8. Conclusion

**Requirement B (DNS TTL and Caching) is fully verified and documented.**
The experiment successfully proved:
- Authoritative TTL propagation (30s).
- Accurate local cache retention and TTL countdown (30s $\rightarrow$ 22s).
- Automatic eviction of stale cache entries upon TTL expiry.
- Fresh resolution of updated upstream records without requiring manual resolver reboots.
