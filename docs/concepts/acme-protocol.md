# ACME Protocol

**Automatic Certificate Management Environment (ACME)** is the protocol behind Let's Encrypt and modern certificate automation.

## What is ACME?

ACME is a standardized protocol (RFC 8555) for automating certificate issuance and renewal. It eliminates manual certificate management by allowing servers to prove domain ownership and receive certificates automatically.

## How ACME Works

```
┌──────────┐                    ┌──────────┐
│  Server  │                    │ ACME CA  │
│ (Client) │                    │(step-ca) │
└────┬─────┘                    └────┬─────┘
     │                               │
     │ 1. Request certificate        │
     ├──────────────────────────────>│
     │                               │
     │ 2. Challenge (prove identity) │
     │<──────────────────────────────┤
     │                               │
     │ 3. Complete challenge         │
     ├──────────────────────────────>│
     │                               │
     │ 4. Verify challenge           │
     │<──────────────────────────────┤
     │                               │
     │ 5. Issue certificate          │
     │<──────────────────────────────┤
     └───────────────────────────────┘
```

## Challenge Types

ACME supports several challenge types to prove domain/IP ownership:

### HTTP-01 Challenge
- Server proves it controls a domain by serving a specific file at a well-known URL
- Example: `http://example.com/.well-known/acme-challenge/token`
- **Limitation**: Requires port 80, doesn't work for IP addresses

### DNS-01 Challenge
- Server proves domain control by creating a DNS TXT record
- Works for wildcards
- **Limitation**: Requires DNS API access

### TLS-ALPN-01 Challenge
- Uses TLS handshake with ALPN extension
- Works without HTTP
- **Limitation**: Complex to implement

### For Internal PKI

With internal PKI and **private IP addresses**, the standard ACME challenges don't work well because:
- You can't create public DNS records for `192.168.1.50`
- You may not want to open port 80 externally

**auto-ssl's approach:**
- Uses step CLI with provisioner authentication (not ACME challenges)
- Or uses step-ca's internal ACME provisioner which trusts the internal network
- Servers authenticate with provisioner passwords or tokens

## ACME Components

### Account
Every client needs an account with the ACME CA:
```bash
# step ca bootstrap creates the account
step ca bootstrap --ca-url https://ca.internal:9000 --fingerprint abc123
```

### Order
A request for one or more certificates:
```json
{
  "identifiers": [
    {"type": "ip", "value": "192.168.1.50"},
    {"type": "dns", "value": "myserver.local"}
  ]
}
```

### Authorization
Proof that you control each identifier:
- One authorization per identifier
- Contains one or more challenges

### Challenge
A specific method to prove control:
- HTTP-01, DNS-01, TLS-ALPN-01
- Client completes challenge
- CA verifies it

### Certificate
Once all authorizations are valid:
- CA issues the certificate
- Client downloads it
- Certificate is ready to use

## ACME vs Step CLI

auto-ssl supports two methods:

### Method 1: Step CLI (Recommended for Internal)
```bash
step ca certificate 192.168.1.50 server.crt server.key \
  --provisioner admin \
  --password-file /etc/step/password
```

**Pros:**
- Works with IP addresses
- Simpler for internal networks
- No challenge complexity

**Cons:**
- Requires provisioner credentials
- Not standard ACME

### Method 2: ACME with Caddy
```caddyfile
{
    acme_ca https://ca.internal:9000/acme/acme/directory
    acme_ca_root /etc/ssl/auto-ssl/root_ca.crt
}

192.168.1.50 {
    reverse_proxy localhost:8080
}
```

**Pros:**
- Standard ACME protocol
- Automatic renewal built into Caddy
- No credential management

**Cons:**
- Limited to software with ACME support
- More complex to debug

## Certificate Renewal

ACME certificates can be renewed using the existing certificate to prove identity:

```bash
# Automatic renewal
step ca renew server.crt server.key --force
```

This is safer than re-authenticating because:
- No need to store provisioner passwords
- Certificate itself proves identity
- Can be run as limited-privilege user

## ACME Directory

The ACME CA exposes a directory endpoint:

```bash
curl https://ca.internal:9000/acme/acme/directory
```

Returns:
```json
{
  "newNonce": "https://ca.internal:9000/acme/acme/new-nonce",
  "newAccount": "https://ca.internal:9000/acme/acme/new-account",
  "newOrder": "https://ca.internal:9000/acme/acme/new-order",
  "revokeCert": "https://ca.internal:9000/acme/acme/revoke-cert"
}
```

This tells ACME clients how to interact with the CA.

## Security Considerations

1. **Account Key Protection**: The ACME account private key is valuable
2. **Challenge Validation**: Ensure only authorized systems can complete challenges
3. **Rate Limiting**: ACME CAs typically rate-limit to prevent abuse
4. **Replay Protection**: Nonces prevent replay attacks

## Next Steps

- **[Quick Start](../guides/quickstart.md)** — Get started with auto-ssl
- **[Caddy Integration](../guides/caddy-integration.md)** — Use ACME with Caddy
- **[Server Enrollment](../guides/server-enrollment.md)** — Manual certificate issuance
