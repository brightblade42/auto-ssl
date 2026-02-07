# Architecture

Technical overview of auto-ssl's architecture and components.

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       INTERNAL NETWORK                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐                                       │
│  │   CA Server      │  - step-ca process                    │
│  │  192.168.1.100   │  - auto-ssl CLI                       │
│  │                  │  - systemd services                    │
│  └────────┬─────────┘                                       │
│           │                                                  │
│           │ HTTPS/ACME (port 9000)                          │
│           │                                                  │
│           ├─────────────────┬────────────────────┐          │
│           ▼                 ▼                    ▼          │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐│
│  │ App Server 1   │  │ App Server 2   │  │ App Server N   ││
│  │ 192.168.1.50   │  │ 192.168.1.51   │  │ 192.168.1.X    ││
│  │                │  │                │  │                ││
│  │ - auto-ssl     │  │ - auto-ssl     │  │ - auto-ssl     ││
│  │ - systemd timer│  │ - systemd timer│  │ - systemd timer││
│  │ - web server   │  │ - web server   │  │ - web server   ││
│  └────────────────┘  └────────────────┘  └────────────────┘│
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                      CLIENT MACHINES                         │
│                                                             │
│  - Browsers (with trusted root CA)                          │
│  - CLI tools (curl, wget, etc.)                             │
│  - Applications (Python, Node.js, Go, etc.)                 │
└─────────────────────────────────────────────────────────────┘
```

## Components

### CA Server

**Purpose**: Issue and manage certificates

**Components**:
- `step-ca` - The actual CA server (Go binary)
- `auto-ssl` - Management wrapper (Bash)
- `auto-ssl-tui` - Companion TUI/CLI that embeds and orchestrates `auto-ssl`
- `step` CLI - Certificate operations

**Key Files**:
- `/opt/step-ca/` - CA data directory
  - `config/ca.json` - Configuration
  - `certs/root_ca.crt` - Root certificate
  - `secrets/` - Private keys
  - `db/` - Certificate database
- `/etc/auto-ssl/config.yaml` - auto-ssl config
- `/etc/systemd/system/step-ca.service` - Service definition

**Processes**:
- `step-ca` - Always running, listens on port 9000

**Network**:
- Inbound: Port 9000/TCP (HTTPS)
- Outbound: None required

### Application Servers

**Purpose**: Run applications with HTTPS

**Components**:
- `auto-ssl` - Certificate management
- `step` CLI - Certificate operations
- Web server (nginx, Caddy, etc.)
- Application

**Key Files**:
- `/etc/ssl/auto-ssl/server.crt` - Server certificate
- `/etc/ssl/auto-ssl/server.key` - Private key
- `/etc/auto-ssl/config.yaml` - Configuration
- `/etc/systemd/system/auto-ssl-renew.{service,timer}` - Renewal automation

**Processes**:
- Web server (nginx, Caddy, etc.)
- Application server
- `auto-ssl-renew.timer` - Triggers renewal

**Network**:
- Inbound: Port 443/TCP (HTTPS), 80/TCP (HTTP redirect)
- Outbound: Port 9000/TCP to CA (for renewal)

### Client Machines

**Purpose**: Access applications securely

**Components**:
- Browser or CLI tool
- System trust store

**Key Files**:
- macOS: `/Library/Keychains/System.keychain`
- RHEL: `/etc/pki/ca-trust/source/anchors/`
- Debian: `/usr/local/share/ca-certificates/`

**Network**:
- Outbound: Port 443/TCP to application servers

## Certificate Lifecycle

### Issuance

```
┌──────────┐                     ┌──────────┐
│  Server  │                     │    CA    │
└────┬─────┘                     └────┬─────┘
     │                                │
     │ 1. Generate private key        │
     ├────────────────────────────────┤
     │                                │
     │ 2. Create CSR                  │
     ├────────────────────────────────┤
     │                                │
     │ 3. Send CSR + auth             │
     ├───────────────────────────────>│
     │                                │
     │ 4. Validate identity           │
     │                                ├─── Check provisioner
     │                                ├─── Verify password
     │                                ├─── Apply policies
     │                                │
     │ 5. Issue certificate           │
     │<───────────────────────────────┤
     │                                │
     │ 6. Save certificate            │
     ├────────────────────────────────┤
     │                                │
     │ 7. Configure web server        │
     ├────────────────────────────────┤
```

### Renewal

```
┌──────────┐                     ┌──────────┐
│  Server  │                     │    CA    │
└────┬─────┘                     └────┬─────┘
     │                                │
     │ Timer triggers (every 5 days)  │
     ├────────────────────────────────┤
     │                                │
     │ Send existing cert + key       │
     ├───────────────────────────────>│
     │                                │
     │ Verify cert is valid           │
     │                                ├─── Check signature
     │                                ├─── Check not revoked
     │                                │
     │ Issue new certificate          │
     │<───────────────────────────────┤
     │                                │
     │ Replace old cert atomically    │
     ├────────────────────────────────┤
     │                                │
     │ Reload web server (optional)   │
     ├────────────────────────────────┤
```

## Data Flow

### Certificate Request (Initial)

1. **User runs**: `sudo auto-ssl server enroll --ca-url https://CA --fingerprint FP`
2. **auto-ssl**:
   - Installs step CLI if needed
   - Runs `step ca bootstrap` (trust CA)
   - Detects primary IP
   - Runs `step ca certificate` with provisioner auth
3. **step CLI**:
   - Generates key pair
   - Creates CSR
   - Authenticates with provisioner password
   - Sends CSR to CA
4. **step-ca**:
   - Validates provisioner password
   - Checks CSR against policies
   - Signs certificate with intermediate CA
   - Returns certificate
5. **auto-ssl**:
   - Saves certificate and key
   - Sets permissions
   - Creates systemd timer
   - Saves configuration

### Certificate Renewal (Automatic)

1. **systemd timer** triggers every 5 days
2. **systemd service** runs: `step ca renew --force /path/to/cert /path/to/key`
3. **step CLI**:
   - Reads existing certificate and key
   - Authenticates to CA using the certificate itself
   - Requests new certificate with same SANs
4. **step-ca**:
   - Verifies certificate signature
   - Checks certificate not revoked
   - Issues new certificate
5. **step CLI**:
   - Overwrites old certificate with new one
6. **systemd** (if configured):
   - Runs `ExecStartPost` (reload web server)

## Security Architecture

### Trust Model

```
┌────────────────┐
│   Root CA      │  ← Self-signed, trusted by clients
│  (offline key) │     Never used to sign server certs
└────────┬───────┘
         │ signs
         ▼
┌────────────────┐
│ Intermediate CA│  ← Signs all server certificates
│  (online key)  │     Used by step-ca
└────────┬───────┘
         │ signs
         ▼
┌────────────────┐
│  Server Certs  │  ← Short-lived (7 days)
│  (ephemeral)   │     Auto-renewed
└────────────────┘
```

### Threat Model

**Threats Mitigated**:
- Man-in-the-middle attacks (via TLS)
- Certificate forgery (private key protection)
- Long-lived key exposure (7-day certificates)
- Unauthorized issuance (provisioner authentication)

**Assumptions**:
- Internal network is trusted
- CA server is secure
- Provisioner passwords are protected
- Clients trust root CA

**Out of Scope**:
- DDoS attacks
- Physical access to servers
- Insider threats with root access
- Certificate transparency

### Access Control

**CA Server**:
- Root access required for: CA operations, backups
- Provisioner password required for: certificate issuance
- No access required for: certificate verification

**Application Servers**:
- Root access required for: enrollment, renewal service management
- No access required for: web server to read certificates

**Clients**:
- Root access required for: installing root CA
- No access required for: using HTTPS

## Performance Considerations

### CA Server

**Capacity**:
- Can handle 100+ simultaneous certificate requests
- Renewal overhead: <1 second per certificate
- Recommended: 2 CPU cores, 1GB RAM

**Bottlenecks**:
- Disk I/O for database writes
- Network bandwidth (minimal)

**Scaling**:
- Single CA handles 1000+ servers easily
- For larger deployments: Multiple CAs per network segment

### Application Servers

**Overhead**:
- Renewal timer: Runs once every 5 days, <1 second
- TLS overhead: 1-2ms additional latency
- Memory: +10-20MB for TLS libraries

**Web Server Reload**:
- nginx: <100ms, no connection drops
- Caddy: Zero-downtime (built-in)

### Network

**Bandwidth**:
- Certificate size: ~2KB
- Renewal: ~4KB round trip (req + resp)
- Per server: <1KB/day average

## Deployment Patterns

### Single CA

```
CA Server (1) → App Servers (N)
```
**Use for**: Small deployments (<50 servers)

### Multi-Network

```
CA Server (1 per network) → App Servers (N per network)
```
**Use for**: Multiple isolated networks

### High Availability

```
CA Server (active) ┐
                   ├→ Shared storage → App Servers (N)
CA Server (standby)┘
```
**Use for**: Production environments requiring <1hr recovery

## Monitoring Points

**CA Health**:
- step-ca process running
- Port 9000 listening
- `/health` endpoint responding
- Certificate database size

**Server Health**:
- Certificate validity (days remaining)
- Renewal timer active
- Last renewal success/failure
- Web server using correct certificate

**Client Health**:
- Root CA in trust store
- Able to connect to HTTPS endpoints

## See Also

- [Security Model](security-model.md)
- [PKI Fundamentals](../concepts/pki-fundamentals.md)
- [Configuration Files](config-files.md)
