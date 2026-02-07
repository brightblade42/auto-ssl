# Why Internal PKI?

## The Problem

You're building internal tools — admin dashboards, API servers, development environments. They need HTTPS because:

- Browsers mark HTTP as "Not Secure"
- Modern APIs require HTTPS (cookies, service workers, etc.)
- Security compliance demands encryption
- You want to practice good habits

But getting HTTPS on internal servers is surprisingly painful.

## The Usual Options (All Bad)

### Option 1: Self-Signed Certificates

```
Your connection is not private
NET::ERR_CERT_AUTHORITY_INVALID
```

Every browser screams warnings. Users learn to click "Proceed anyway." You've trained them to ignore security warnings — the exact opposite of what you wanted.

**Verdict:** Creates bad habits. Doesn't scale.

### Option 2: Let's Encrypt

Let's Encrypt is amazing for public websites. But for internal servers:

- Requires a **public domain name** (can't use internal IPs or `.local` names)
- Requires **internet access** for validation
- Requires opening **port 80 or 443** to the internet for HTTP-01 challenge
- DNS-01 challenge requires public DNS you control

**Verdict:** Designed for public internet, not internal networks.

### Option 3: Buy Certificates

Commercial CAs like DigiCert or Sectigo can issue internal certificates, but:

- **Expensive** — $100+ per certificate per year
- **Slow** — Manual validation process
- **Limited** — Can't issue for IP addresses or internal hostnames
- **Doesn't scale** — 50 internal servers = $5,000/year

**Verdict:** Cost-prohibitive for internal use.

### Option 4: Just Use HTTP

"It's internal, who cares?"

- Can't use modern browser features (secure cookies, service workers)
- Network sniffing is trivial on shared networks
- Compliance auditors will not be happy
- Bad practice that bleeds into production habits

**Verdict:** Unacceptable for any serious environment.

## The Solution: Run Your Own CA

Here's what enterprises have done for decades: run their own Certificate Authority.

```
┌─────────────────┐
│   Your Root CA  │  ← You control this
└────────┬────────┘
         │ issues
         ▼
┌─────────────────┐
│  Your Server    │  ← Gets a certificate
│  Certificate    │
└────────┬────────┘
         │ trusted by
         ▼
┌─────────────────┐
│  Your Clients   │  ← Trust your Root CA once
└─────────────────┘
```

**The key insight:** Browsers trust certificates because they trust the CA that issued them. If you run your own CA, and tell your clients to trust it, you can issue certificates for anything — IP addresses, internal hostnames, `.local` domains, whatever you need.

## Why This Used to Be Hard

Running a CA used to require:

- Deep PKI knowledge
- Complex software (EJBCA, OpenSSL scripts)
- Manual certificate management
- No automation

It was "enterprise software" — complex, expensive, and overkill for a small team.

## Why It's Easy Now: Smallstep

[Smallstep](https://smallstep.com/) changed everything. Their `step-ca` is:

- **Simple to set up** — One command to initialize
- **Standards-based** — Supports ACME (same protocol as Let's Encrypt)
- **Automation-friendly** — Designed for short-lived, auto-renewed certs
- **Open source** — Free to use

**auto-ssl** wraps Smallstep's tools to make the process even simpler.

## What You Get

With auto-ssl, you get:

| Feature | Description |
|---------|-------------|
| **HTTPS everywhere** | Every internal server can have valid TLS |
| **No browser warnings** | Clients trust your CA, so certs are "valid" |
| **IP address certificates** | Works without DNS infrastructure |
| **Short-lived certificates** | 7-day certs limit blast radius |
| **Automatic renewal** | systemd timers handle renewal |
| **Zero-touch for Caddy** | Caddy handles everything via ACME |
| **One-time client setup** | Trust the root CA once per machine |

## The Mental Model

Think of it like this:

1. **You are the authority** — Your CA is the source of trust
2. **Clients opt-in once** — They install your root CA
3. **Servers get certs easily** — Bootstrap, enroll, forget
4. **Automation handles renewal** — No more 3am expired cert pages

## When NOT to Use Internal PKI

Internal PKI is great for:
- Development environments
- Internal tools and dashboards  
- Private APIs
- Lab/test infrastructure

It's NOT a replacement for:
- Public-facing websites (use Let's Encrypt)
- Services that external clients access
- Anything where you can't control the client trust store

## Next Steps

Ready to set up your own internal PKI?

1. **[PKI Fundamentals](pki-fundamentals.md)** — Understand the concepts
2. **[Quick Start](../guides/quickstart.md)** — Get running in 5 minutes
3. **[CA Setup Guide](../guides/ca-setup.md)** — Detailed CA setup
