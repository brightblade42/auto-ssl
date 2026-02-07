# PKI Fundamentals

This document explains the core concepts of Public Key Infrastructure (PKI) — the foundation of how HTTPS and digital certificates work.

## The Trust Problem

When you connect to `https://example.com`, how does your browser know it's actually talking to example.com and not an imposter?

The answer: **digital certificates** and **certificate authorities**.

## Public Key Cryptography (30-Second Version)

Every entity in PKI has a **key pair**:

- **Private key** — Secret, never shared, used to sign things
- **Public key** — Shared freely, used to verify signatures

If someone signs a message with their private key, anyone with their public key can verify:
1. The message came from them (authentication)
2. The message wasn't altered (integrity)

## What's a Certificate?

A certificate is a signed document that says:

> "I, [Authority], certify that this public key belongs to [Subject]"

It contains:
- **Subject** — Who the cert is for (e.g., `example.com` or `192.168.1.50`)
- **Public key** — The subject's public key
- **Issuer** — Who issued/signed the cert
- **Validity period** — When the cert is valid
- **Signature** — The issuer's cryptographic signature

```
┌──────────────────────────────────────┐
│           CERTIFICATE                │
├──────────────────────────────────────┤
│ Subject: example.com                 │
│ Public Key: [base64 encoded key]     │
│ Issuer: DigiCert                     │
│ Valid: 2024-01-01 to 2025-01-01      │
│ SANs: example.com, www.example.com   │
│                                      │
│ Signature: [DigiCert's signature]    │
└──────────────────────────────────────┘
```

## The Chain of Trust

Browsers don't verify certificates directly. They verify **chains**.

```
┌─────────────────┐
│    Root CA      │  ← Pre-installed in browsers/OS
│   (DigiCert)    │     Self-signed (signs itself)
└────────┬────────┘
         │ signs
         ▼
┌─────────────────┐
│ Intermediate CA │  ← Signed by Root
│   (DigiCert)    │     Can issue end certificates
└────────┬────────┘
         │ signs
         ▼
┌─────────────────┐
│  End Entity     │  ← Your server's cert
│  (example.com)  │     Signed by Intermediate
└─────────────────┘
```

**How verification works:**

1. Server presents its certificate + intermediate(s)
2. Browser checks: Is this cert signed by an intermediate I trust?
3. Browser checks: Is that intermediate signed by a root I trust?
4. If yes → Connection is trusted
5. If no → "Your connection is not private"

## Root CAs: The Trust Anchors

Your browser/OS ships with ~100-150 pre-installed root CA certificates. These are the "trust anchors" — the starting points for all certificate validation.

You trust these because:
- Browser/OS vendors vetted them
- They follow strict security practices
- They're legally liable for misissuance

**Key point:** Anyone can create a CA. The question is whether clients trust it.

## Why Intermediates?

Root CA private keys are extremely valuable. If compromised, an attacker could issue certificates for any domain.

Best practice: Keep the root key offline (literally in a safe). Use an intermediate CA for day-to-day issuance.

```
Root CA (offline, in a vault)
    │
    └── Intermediate CA (online, issues certs)
            │
            └── Your server cert
```

If the intermediate is compromised, you revoke it and create a new one. The root stays safe.

For internal PKI with auto-ssl, we use this same pattern — `step-ca` creates both a root and intermediate by default.

## Subject Alternative Names (SANs)

Modern certificates use SANs to specify what they're valid for:

```
Subject: myserver
SANs:
  - DNS: myserver.internal
  - DNS: myserver.local
  - IP: 192.168.1.50
  - IP: 10.0.0.50
```

This cert is valid for any of those names/IPs. This is how we issue certificates for IP addresses — they go in the SAN field.

## Certificate Lifetimes

Traditional certificates last 1-2 years. This is convenient but risky:

- Longer exposure window if compromised
- Easy to forget about renewal
- Leads to 3am "cert expired" emergencies

Modern best practice: **short-lived certificates** (hours to days) with automatic renewal. This is what auto-ssl does with 7-day certificates.

## Revocation

What if a certificate is compromised before it expires?

Two mechanisms:
- **CRL (Certificate Revocation List)** — CA publishes list of revoked certs
- **OCSP (Online Certificate Status Protocol)** — Client asks CA "is this cert valid?"

With short-lived certs, revocation is less critical — even if you don't revoke, the cert expires in 7 days.

## Private Keys: The Crown Jewels

The private key is everything. Whoever has it can:
- Impersonate the certificate's identity
- Decrypt traffic encrypted to that certificate (in some modes)

**Rules for private keys:**
1. Never send them over the network (generate locally)
2. Protect with filesystem permissions (600)
3. Never commit to git
4. Rotate if compromised (issue new cert)

## Putting It Together for Internal PKI

Here's how auto-ssl uses these concepts:

```
┌─────────────────────────┐
│     Your Root CA        │  Created by 'auto-ssl ca init'
│  (step-ca on CA server) │  Trusted by your clients
└───────────┬─────────────┘
            │
            │ signs (automatically)
            ▼
┌─────────────────────────┐
│   Intermediate CA       │  Also created by step-ca
│  (managed by step-ca)   │  Does the actual signing
└───────────┬─────────────┘
            │
            │ issues (via ACME or step CLI)
            ▼
┌─────────────────────────┐
│   Server Certificates   │  7-day validity
│   (on your servers)     │  Auto-renewed by systemd
└─────────────────────────┘
```

**One-time setup:**
- Initialize CA (creates root + intermediate)
- Trust root on clients (add to trust store)

**Ongoing (automated):**
- Servers request certificates
- Certificates auto-renew before expiry
- You don't think about it

## Key Takeaways

| Concept | What It Means |
|---------|---------------|
| Certificate | Signed document binding identity to public key |
| CA | Entity that signs certificates |
| Root CA | Trust anchor, pre-installed or manually trusted |
| Intermediate | Signs certs on behalf of root (safer) |
| Private key | Secret, never share, generate locally |
| SANs | What names/IPs the cert is valid for |
| Chain | Root → Intermediate → End cert |
| Short-lived | Certs that expire quickly (safer) |

## Next Steps

- **[Short-Lived Certificates](short-lived-certs.md)** — Why 7-day certs are better
- **[ACME Protocol](acme-protocol.md)** — How automatic cert management works
- **[Quick Start](../guides/quickstart.md)** — Get started with auto-ssl
