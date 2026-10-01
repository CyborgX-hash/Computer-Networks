# IP & Service Allocation Table

> **CRITICAL NOTICE ON NETWORK VALUES:**
> All IP addresses, MAC addresses, network interfaces, subnets, and gateways listed in this document are **explicit placeholders**.
> Actual values must be populated by the team once all 3 macOS laptops are connected to the shared test LAN.
> **Do not invent or assume static IP addresses.**

---

## 1. Core Service Mapping Table

| Machine | Role | IP Address (Placeholder) | Service | Port | Protocol | Scope / Visibility |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Mac 1** | DNS Server + Test Client | `MAC1_IP` | `dnsmasq` | `53` | UDP | LAN-wide DNS resolution for `.test` domain |
| **Mac 2** | Edge Proxy / Load Balancer | `MAC2_IP` | `nginx` (HTTPS) | `443` / `8443` | TCP | Public LAN ingress & TLS termination |
| **Mac 3** | Backend Instance A | `MAC3_IP` | Node.js Service A | `3001` | TCP | Internal upstream target A |
| **Mac 3** | Backend Instance B | `MAC3_IP` | Node.js Service B | `3002` | TCP | Internal upstream target B |

---

## 2. Host Network Configuration Template

When connecting to the test network, run `ifconfig` and `netstat -nr` (or `ipconfig getifaddr en0`) on each macOS laptop to record the active network parameters below.

### Shared Network Environment

| Parameter | Placeholder / Field | Populated Actual Value | Notes |
| :--- | :--- | :--- | :--- |
| **Subnet CIDR / Prefix** | `SUBNET_PREFIX` | *(To be recorded e.g. /24)* | All 3 Macs must reside on the same broadcast domain |
| **Subnet Mask** | `SUBNET_MASK` | *(To be recorded e.g. 255.255.255.0)* | Derived from prefix |
| **Default Gateway** | `DEFAULT_GATEWAY_IP` | *(To be recorded)* | Router / Gateway IP for the shared LAN |

---

### Per-Machine Network Interface Data

#### Mac 1 (DNS Server & Test Client)
- **Hostname / Identifier:** `Mac-1`
- **Active Interface:** `MAC1_INTERFACE` *(e.g., en0 for Wi-Fi / en7 for Ethernet)*
- **IPv4 Address:** `MAC1_IP`
- **MAC (Hardware) Address:** `MAC1_MAC_ADDR` *(e.g., xx:xx:xx:xx:xx:xx)*
- **Assigned DNS Server for OS:** `127.0.0.1` / `MAC1_IP`

#### Mac 2 (Edge Proxy / Load Balancer)
- **Hostname / Identifier:** `Mac-2`
- **Active Interface:** `MAC2_INTERFACE` *(e.g., en0 / en7)*
- **IPv4 Address:** `MAC2_IP`
- **MAC (Hardware) Address:** `MAC2_MAC_ADDR`
- **Assigned DNS Server for OS:** `MAC1_IP`

#### Mac 3 (Backend Application Host)
- **Hostname / Identifier:** `Mac-3`
- **Active Interface:** `MAC3_INTERFACE` *(e.g., en0 / en7)*
- **IPv4 Address:** `MAC3_IP`
- **MAC (Hardware) Address:** `MAC3_MAC_ADDR`
- **Assigned DNS Server for OS:** `MAC1_IP`

---

## 3. Domain Name to IP Mappings (`dnsmasq`)

| Fully Qualified Domain Name (FQDN) | Target IP Address | Destination Host / Service |
| :--- | :--- | :--- |
| `app.teamX.test` | `MAC2_IP` | Mac 2 — nginx Edge / Load Balancer |
| `api.teamX.test` | `MAC2_IP` | Mac 2 — nginx Edge / Load Balancer |

> **Requirement:** All domains use the `.test` reserved TLD. The `.local` mDNS namespace is strictly avoided to prevent multicast collisions and OS-level resolver interference.
