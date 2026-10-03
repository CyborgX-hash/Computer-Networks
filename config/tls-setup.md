# TLS / HTTPS Setup Guide — Private Network Service Platform

This document provides step-by-step instructions for generating, installing, and verifying a local TLS certificate for the project domain `app.teamX.test`.

> **IMPORTANT:** Do NOT commit private keys (`.key`, `.pem` key files) or generated certificates to Git.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Install mkcert](#2-install-mkcert)
3. [Install the Local CA](#3-install-the-local-ca)
4. [Generate the Certificate](#4-generate-the-certificate)
5. [Place Certificates for nginx](#5-place-certificates-for-nginx)
6. [Configure nginx to Use the Certificate](#6-configure-nginx-to-use-the-certificate)
7. [Trust the CA on Client Machines](#7-trust-the-ca-on-client-machines)
8. [Restart / Reload nginx](#8-restart--reload-nginx)
9. [Test HTTPS Without `-k`](#9-test-https-without--k)
10. [Why `curl -k` Is Forbidden](#10-why-curl--k-is-forbidden)
11. [TLS Handshake — Conceptual Explanation](#11-tls-handshake--conceptual-explanation)
12. [Alternative: OpenSSL Manual Approach](#12-alternative-openssl-manual-approach)

---

## 1. Overview

| Component         | Detail                                       |
| :---------------- | :------------------------------------------- |
| Domain            | `app.teamX.test`                             |
| TLS Termination   | nginx on Mac 2, port `8443` (or `443`)       |
| Certificate Tool  | [mkcert](https://github.com/FiloSottile/mkcert) |
| Certificate Type  | Locally-trusted development certificate      |

Traffic between the client (Mac 1) and nginx (Mac 2) is encrypted via HTTPS.  
Traffic between nginx (Mac 2) and the backends (Mac 3) remains plain HTTP over the private LAN.

---

## 2. Install mkcert

Run on **Mac 2** (the nginx machine):

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install mkcert and its dependency (NSS, for Firefox trust)
brew install mkcert nss
```

Verify installation:

```bash
mkcert --version
# Expected output: v1.x.x
```

---

## 3. Install the Local CA

This creates a local Certificate Authority (CA) and adds it to the macOS system trust store.

```bash
mkcert -install
```

What this does:
- Creates a root CA key pair in `$(mkcert -CAROOT)/`
- Adds the CA certificate to the macOS Keychain (`System` or `login` keychain) as a trusted root
- If NSS is installed, also trusts the CA in Firefox

You can verify the CA root directory:

```bash
mkcert -CAROOT
# Typically: /Users/<username>/Library/Application Support/mkcert
```

---

## 4. Generate the Certificate

Still on **Mac 2**, generate a certificate valid for the project domain:

```bash
mkcert app.teamX.test
```

This produces two files in the current directory:

| File                        | Contents             |
| :-------------------------- | :------------------- |
| `app.teamX.test.pem`       | Server certificate   |
| `app.teamX.test-key.pem`   | Private key          |

### Optional: Multi-Domain Certificate

If you also need `api.teamX.test`:

```bash
mkcert app.teamX.test api.teamX.test
```

This creates a single certificate valid for both Subject Alternative Names.

---

## 5. Place Certificates for nginx

Create a `certs/` directory inside the nginx configuration directory and move the certificate files there:

```bash
# For Apple Silicon Macs (Homebrew default prefix)
mkdir -p /opt/homebrew/etc/nginx/certs

# Move the generated files
mv app.teamX.test.pem     /opt/homebrew/etc/nginx/certs/
mv app.teamX.test-key.pem /opt/homebrew/etc/nginx/certs/

# Restrict permissions on the private key
chmod 600 /opt/homebrew/etc/nginx/certs/app.teamX.test-key.pem
chmod 644 /opt/homebrew/etc/nginx/certs/app.teamX.test.pem
```

> **Intel Mac users:** Replace `/opt/homebrew/` with `/usr/local/` throughout.

---

## 6. Configure nginx to Use the Certificate

The project's `nginx.conf` already references the certificate paths:

```nginx
ssl_certificate      /opt/homebrew/etc/nginx/certs/app.teamX.test.pem;
ssl_certificate_key  /opt/homebrew/etc/nginx/certs/app.teamX.test-key.pem;
```

Ensure these paths match where you placed the files in Step 5.

---

## 7. Trust the CA on Client Machines

For HTTPS to work **without `-k`**, every client machine (especially Mac 1, the test client) must trust the mkcert CA.

### Option A: Install mkcert on the Client and Run `-install`

1. On **Mac 1** (client), install mkcert:
   ```bash
   brew install mkcert
   ```

2. Copy the CA certificate from Mac 2:
   ```bash
   # On Mac 2, find the CA root
   mkcert -CAROOT
   # Copy the rootCA.pem file to Mac 1 (via AirDrop, scp, USB, etc.)
   ```

3. On **Mac 1**, place the `rootCA.pem` in the mkcert CA directory and install:
   ```bash
   # Create the mkcert CAROOT directory if it doesn't exist
   mkdir -p "$(mkcert -CAROOT)"

   # Copy the rootCA.pem (and rootCA-key.pem if available) into CAROOT
   cp /path/to/transferred/rootCA.pem "$(mkcert -CAROOT)/rootCA.pem"

   # Install the CA into the system trust store
   mkcert -install
   ```

### Option B: Manual Keychain Import (No mkcert on Client)

1. Transfer the `rootCA.pem` file from Mac 2 to Mac 1.

2. Double-click `rootCA.pem` to open it in Keychain Access, or use the command line:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain \
     /path/to/rootCA.pem
   ```

3. In Keychain Access, find the mkcert root CA → Get Info → Trust → set **"When using this certificate"** to **"Always Trust"**.

---

## 8. Restart / Reload nginx

After placing the certificates and updating the configuration:

```bash
# Test configuration syntax
nginx -t

# If nginx is already running, reload
nginx -s reload

# If nginx is not running, start it
nginx
```

---

## 9. Test HTTPS Without `-k`

From **Mac 1** (the test client), after DNS and CA trust are configured:

```bash
# Basic connectivity test
curl https://app.teamX.test:8443/

# API status endpoint with headers
curl -I https://app.teamX.test:8443/api/status

# Full response with headers
curl -i https://app.teamX.test:8443/api/status
```

**Expected successful output (no TLS errors):**

```
HTTP/2 200
x-backend: A
cache-control: public, max-age=60
content-type: application/json; charset=utf-8
...

{"backend":"A","status":"ok"}
```

If you see `curl: (60) SSL certificate problem: unable to get local issuer certificate`, the CA is not yet trusted on the client machine. Revisit Step 7.

---

## 10. Why `curl -k` Is Forbidden

The `-k` / `--insecure` flag tells curl to **skip all certificate verification**. This means:

- The server's identity is **not authenticated**
- A man-in-the-middle (MITM) attacker could intercept the connection
- The TLS handshake still occurs, but the client **blindly trusts any certificate**

For the Computer Networks viva, the project must demonstrate that:

1. The TLS certificate chain is **valid and complete**
2. The client **trusts the CA** that signed the server certificate
3. The `server_name` in nginx matches the certificate's Subject Alternative Name
4. The entire PKI (Public Key Infrastructure) chain works end-to-end

Using `-k` would bypass all of these validations and defeat the purpose of demonstrating TLS.

---

## 11. TLS Handshake — Conceptual Explanation

When a client connects to `https://app.teamX.test:8443`, the following handshake occurs **before** any HTTP data is exchanged:

```
Client (Mac 1)                              Server / nginx (Mac 2)
      |                                              |
      |──── (1) ClientHello ────────────────────────>|
      |      • Supported TLS versions (1.2, 1.3)    |
      |      • Supported cipher suites              |
      |      • Random number (client_random)         |
      |      • SNI: app.teamX.test                   |
      |                                              |
      |<──── (2) ServerHello ────────────────────────|
      |      • Selected TLS version                  |
      |      • Selected cipher suite                 |
      |      • Random number (server_random)         |
      |                                              |
      |<──── (3) Certificate ────────────────────────|
      |      • Server's X.509 certificate            |
      |      • Contains public key                   |
      |      • Signed by the mkcert local CA         |
      |                                              |
      |      Client verifies:                        |
      |        ✓ Certificate not expired             |
      |        ✓ SAN matches app.teamX.test          |
      |        ✓ CA signature is valid               |
      |        ✓ CA is in local trust store          |
      |                                              |
      |<──── (4) Key Exchange ───────────────────────|
      |      • Server Key Exchange parameters        |
      |      • (ECDHE for forward secrecy)           |
      |                                              |
      |──── Client Key Exchange ────────────────────>|
      |      • Client's key exchange parameters      |
      |                                              |
      |      Both sides derive:                      |
      |        • Pre-master secret                   |
      |        • Master secret                       |
      |        • Session keys (symmetric)            |
      |                                              |
      |<═══ (5) Finished ═══════════════════════════>|
      |      • Both sides send Finished message      |
      |      • Verify handshake integrity (MAC)      |
      |      • Switch to symmetric encryption        |
      |        (AES-GCM / ChaCha20-Poly1305)         |
      |                                              |
      |<═══════ Encrypted Application Data ═════════>|
      |      • HTTP request & response flow inside   |
      |        the encrypted TLS tunnel              |
```

### Summary of Each Step

| Step | Message | Purpose |
| :--- | :--- | :--- |
| 1 | **ClientHello** | Client proposes supported TLS versions, cipher suites, and sends SNI (Server Name Indication) so the server knows which certificate to present. |
| 2 | **ServerHello** | Server selects the TLS version and cipher suite from the client's proposals. |
| 3 | **Certificate** | Server sends its X.509 certificate. The client verifies the certificate chain against its local trust store (the mkcert CA). |
| 4 | **Key Exchange** | Both parties exchange cryptographic parameters (e.g., ECDHE public values) to derive a shared secret. This provides **forward secrecy** — even if the server's private key is later compromised, past sessions remain secure. |
| 5 | **Finished** | Both parties confirm the handshake was not tampered with. From this point, all data is encrypted with symmetric keys derived from the shared secret. |

### TLS 1.3 Note

TLS 1.3 combines several of these messages into fewer round trips (1-RTT handshake), but the conceptual steps remain the same: negotiate → authenticate → derive keys → encrypt.

---

## 12. Alternative: OpenSSL Manual Approach

If mkcert is unavailable, you can generate a self-signed certificate using OpenSSL:

```bash
# 1. Generate a private CA key
openssl genrsa -out rootCA-key.pem 4096

# 2. Create a self-signed CA certificate (valid 10 years)
openssl req -x509 -new -nodes -key rootCA-key.pem -sha256 -days 3650 \
  -out rootCA.pem \
  -subj "/C=IN/ST=State/O=TeamX Private CA/CN=TeamX Root CA"

# 3. Generate a private key for the server
openssl genrsa -out app.teamX.test-key.pem 2048

# 4. Create a Certificate Signing Request (CSR)
openssl req -new -key app.teamX.test-key.pem \
  -out app.teamX.test.csr \
  -subj "/C=IN/ST=State/O=TeamX/CN=app.teamX.test"

# 5. Create a SAN extension file
cat > san.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = app.teamX.test
DNS.2 = api.teamX.test
EOF

# 6. Sign the certificate with the CA
openssl x509 -req -in app.teamX.test.csr \
  -CA rootCA.pem -CAkey rootCA-key.pem -CAcreateserial \
  -out app.teamX.test.pem -days 365 -sha256 -extfile san.ext

# 7. Install the CA into macOS trust store
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain rootCA.pem

# 8. Move server cert and key to nginx certs directory
mkdir -p /opt/homebrew/etc/nginx/certs
mv app.teamX.test.pem     /opt/homebrew/etc/nginx/certs/
mv app.teamX.test-key.pem /opt/homebrew/etc/nginx/certs/

# 9. Clean up intermediate files (do NOT commit these)
rm app.teamX.test.csr san.ext rootCA.srl
# Keep rootCA.pem if you need to distribute it to client machines
# NEVER commit rootCA-key.pem to Git
```

Then trust `rootCA.pem` on each client machine as described in Step 7 above.
