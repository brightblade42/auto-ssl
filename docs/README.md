# auto-ssl Documentation

Welcome to the auto-ssl documentation. This guide will help you understand and use auto-ssl to set up internal PKI for your network.

## Getting Started

If you're new to auto-ssl, start here:

1. **[Why Internal PKI?](concepts/why-internal-pki.md)** — Understand the problem we're solving
2. **[Quick Start](guides/quickstart.md)** — Get up and running in 5 minutes
3. **[PKI Fundamentals](concepts/pki-fundamentals.md)** — Learn the underlying concepts

## Documentation Structure

### Concepts

Background knowledge and theory:

- [Why Internal PKI?](concepts/why-internal-pki.md) — The problem and solution
- [PKI Fundamentals](concepts/pki-fundamentals.md) — Root CAs, intermediates, chain of trust
- [Short-Lived Certificates](concepts/short-lived-certs.md) — Why 7-day certs beat 1-year certs
- [ACME Protocol](concepts/acme-protocol.md) — How automatic certificate management works
- [Certificate Lifecycle](concepts/certificate-lifecycle.md) — Issuance, renewal, revocation

### Guides

Step-by-step instructions:

- [Quick Start](guides/quickstart.md) — Get running in 5 minutes
- [CA Setup](guides/ca-setup.md) — Complete CA server setup
- [Server Enrollment](guides/server-enrollment.md) — Get certificates on your servers
- [Client Trust](guides/client-trust.md) — Trust the CA on client machines
- [Caddy Integration](guides/caddy-integration.md) — Zero-touch TLS with Caddy
- [nginx Integration](guides/nginx-integration.md) — Using certificates with nginx
- [Backup & Restore](guides/backup-restore.md) — Protect your CA
- [CA Migration](guides/ca-migration.md) — Move CA to a new server
- [Troubleshooting](guides/troubleshooting.md) — Common issues and solutions

### Reference

Detailed specifications:

- [CLI Reference](reference/cli-reference.md) — All commands and options
- [Configuration Files](reference/config-files.md) — Config file formats
- [Architecture](reference/architecture.md) — System design and decisions
- [Security Model](reference/security-model.md) — Security considerations

## Quick Links

| I want to... | Go to... |
|--------------|----------|
| Set up a CA from scratch | [CA Setup Guide](guides/ca-setup.md) |
| Get certs on a server | [Server Enrollment](guides/server-enrollment.md) |
| Trust the CA on my laptop | [Client Trust](guides/client-trust.md) |
| Back up my CA | [Backup & Restore](guides/backup-restore.md) |
| Move CA to new hardware | [CA Migration](guides/ca-migration.md) |
| Use Caddy with auto-ssl | [Caddy Integration](guides/caddy-integration.md) |
| Fix something that's broken | [Troubleshooting](guides/troubleshooting.md) |
