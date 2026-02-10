# auto-ssl

**Internal PKI made easy.** Any server on your internal network can serve HTTPS that browsers trust.

```
┌─────────────────────────────────────────────────────────────────┐
│                        INTERNAL NETWORK                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐                                              │
│   │   CA Server  │  Runs step-ca                                │
│   │  (one node)  │  Exposes ACME endpoint                       │
│   │              │  https://ca.internal:9000                    │
│   └──────┬───────┘                                              │
│          │                                                      │
│          │ ACME / step ca renew                                 │
│          ▼                                                      │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│   │  App Server  │  │  App Server  │  │  App Server  │          │
│   │   (Caddy)    │  │   (nginx)    │  │  (Go app)    │          │
│   │  auto-renew  │  │  step renew  │  │  step renew  │          │
│   └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│   CLIENTS (trust root CA once)                                  │
│   • macOS — Keychain                                            │
│   • Windows — Certificate Store                                 │
│   • Linux — update-ca-trust / update-ca-certificates            │
└─────────────────────────────────────────────────────────────────┘
```

## Why?

You're building internal tools. They need HTTPS. Your options are:

1. **Self-signed certs** — Browsers scream warnings. Users learn to click "proceed anyway."
2. **Let's Encrypt** — Requires public DNS and internet access. Internal IPs don't work.
3. **Buy certs** — Expensive, slow, requires domain ownership proof.
4. **Ignore it** — Use HTTP. Hope nobody's sniffing the network.

**auto-ssl** gives you a fifth option: Run your own Certificate Authority. Issue your own certificates. Trust that CA once on each client machine. Done.

## Features

- **One-command CA setup** — Initialize a production-ready CA with ACME support
- **Easy server enrollment** — Get certificates on any server with one command
- **Automatic renewal** — 7-day certificates with systemd-based auto-renewal
- **Remote enrollment via SSH** — Enroll servers from the CA without touching them
- **Multi-platform client trust** — Install root CA on macOS, Windows, and Linux
- **CA backup & restore** — Encrypted backups to local, rsync, or S3/Wasabi
- **Certificate revocation** — Revoke compromised certs immediately
- **Server suspension** — Temporarily block renewals for maintenance
- **Bash-first runtime** — Core workflows run directly through `auto-ssl`
- **Optional bootstrap companion** — `auto-ssl-tui` handles packaging/runtime helper tasks
- **Ejectable Bash runtime** — `dump-bash` exports standalone scripts when needed

## Quick Start

### 1. Set up the CA (one machine)

```bash
# Install auto-ssl
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash

# Initialize the CA
sudo auto-ssl ca init --name "My Internal CA" --address "192.168.1.100:9000"

# Note the fingerprint displayed — you'll need it for other servers
```

### 2. Enroll a server (each app server)

```bash
# Install auto-ssl on the server
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash

# Enroll the server
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint <fingerprint-from-step-1>

# Done! Certificates are at:
#   /etc/ssl/auto-ssl/server.crt
#   /etc/ssl/auto-ssl/server.key
```

### 3. Trust the CA (each client machine)

```bash
# Download and trust the root CA
sudo auto-ssl client trust \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint <fingerprint-from-step-1>
```

## auto-ssl-tui (Single Binary)

`auto-ssl-tui` embeds the Bash runtime and provides bootstrap/helper commands. Core operations should run via `auto-ssl`.

```bash
# Show embedded dependency status
auto-ssl-tui doctor

# Install missing dependencies (interactive by default)
auto-ssl-tui install-deps

# Non-interactive dependency install
auto-ssl-tui install-deps --yes

# Eject embedded Bash scripts to a standalone layout
auto-ssl-tui dump-bash --output ./auto-ssl-bash --checksum

# Run embedded auto-ssl directly
auto-ssl-tui exec -- server status
```

## Linux Validation Script

For a fresh Linux VM validation pass (CA init, enroll, renew, trust, backup, companion CLI checks), run:

```bash
./scripts/validate-linux.sh
```

Optional remote enrollment validation:

```bash
REMOTE_HOST=192.168.1.50 REMOTE_USER=admin ./scripts/validate-linux.sh
```

## Documentation

- **Concepts**
  - [Why Internal PKI?](docs/concepts/why-internal-pki.md)
  - [PKI Fundamentals](docs/concepts/pki-fundamentals.md)
  - [Short-Lived Certificates](docs/concepts/short-lived-certs.md)
  - [ACME Protocol](docs/concepts/acme-protocol.md)

- **Guides**
  - [Quick Start](docs/guides/quickstart.md)
  - [CA Setup](docs/guides/ca-setup.md)
  - [Server Enrollment](docs/guides/server-enrollment.md)
  - [Client Trust](docs/guides/client-trust.md)
  - [Caddy Integration](docs/guides/caddy-integration.md)
  - [nginx Integration](docs/guides/nginx-integration.md)
  - [Backup & Restore](docs/guides/backup-restore.md)
  - [CA Migration](docs/guides/ca-migration.md)
  - [Troubleshooting](docs/guides/troubleshooting.md)

- **Reference**
  - [CLI Reference](docs/reference/cli-reference.md)
  - [Configuration Files](docs/reference/config-files.md)
  - [Architecture](docs/reference/architecture.md)
  - [Security Model](docs/reference/security-model.md)

- **Project**
  - [Release Notes](CHANGELOG.md)

## Installation

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash
```

### From source

```bash
git clone https://github.com/Brightblade42/auto-ssl.git
cd auto-ssl
make install
```

`make install` installs `auto-ssl-tui` plus an `auto-ssl` compatibility wrapper that runs `auto-ssl-tui exec -- ...`.

You can treat `auto-ssl-tui` as optional bootstrap tooling and use `auto-ssl` directly for day-to-day operations.

## CLI Reference

```
auto-ssl <command> [options]

CA Commands:
  ca init              Initialize this machine as the CA server
  ca status            Show CA health and configuration
  ca backup            Create encrypted backup of CA
  ca restore           Restore CA from backup
  ca reset             Remove CA and local auto-ssl state (start over)
  ca backup-schedule   Configure automatic backups

Server Commands:
  server enroll        Enroll this server (get certs, setup renewal)
  server status        Show certificate status and expiration
  server renew         Force immediate certificate renewal
  server suspend       Temporarily block certificate renewals
  server resume        Re-enable certificate renewals
  server revoke        Revoke certificate immediately
  server remove        Revoke certificate and remove from inventory

Remote Commands (run from CA server):
  remote enroll        Enroll a server via SSH
  remote status        Check remote server status
  remote update-ca-url Update CA URL on enrolled servers
  remote list          List enrolled servers

Client Commands:
  client trust         Install root CA into system trust store
  client status        Verify root CA is trusted

General:
  info                 Show detected environment
  version              Show version information
  help                 Show help
```

## Configuration

### Default certificate duration: 7 days

Certificates are short-lived by design. This limits the damage if a certificate is compromised, and ensures your renewal automation is working.

You can configure this:

```bash
# At CA init time (sets default and maximum)
auto-ssl ca init --cert-duration 7d --max-duration 30d

# Per-enrollment (up to max)
auto-ssl server enroll --duration 14d ...
```

### Configuration file

`/etc/auto-ssl/config.yaml`:

```yaml
ca:
  url: https://192.168.1.100:9000
  fingerprint: abc123...

defaults:
  cert_duration: 168h      # 7 days
  max_cert_duration: 720h  # 30 days

backup:
  enabled: true
  schedule: "weekly"
  retention: 4
  destinations:
    - type: local
      path: /var/backups/auto-ssl
    - type: s3
      bucket: my-backups
      endpoint: https://s3.wasabisys.com
```

## Built With

- [Smallstep step-ca](https://smallstep.com/docs/step-ca) — The actual CA engine
- [Smallstep step CLI](https://smallstep.com/docs/step-cli) — Certificate operations
- [gum](https://github.com/charmbracelet/gum) — Enhanced bash prompts

## License

MIT

## Contributing

Contributions welcome! Please read the [contributing guide](CONTRIBUTING.md) first.
