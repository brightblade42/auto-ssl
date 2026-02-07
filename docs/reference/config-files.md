# Configuration Files Reference

Documentation of all configuration files used by auto-ssl.

## Main Configuration

### `/etc/auto-ssl/config.yaml`

Main configuration file for auto-ssl.

**Format**: YAML

**Location**: Created by `auto-ssl ca init` or `auto-ssl server enroll`

**Example**:
```yaml
ca:
  url: https://192.168.1.100:9000
  fingerprint: abc123def456789...
  name: My Internal CA
  steppath: /opt/step-ca

defaults:
  cert_duration: 168h
  max_cert_duration: 720h

server:
  cert_path: /etc/ssl/auto-ssl/server.crt
  key_path: /etc/ssl/auto-ssl/server.key
  sans: 192.168.1.50,myserver.local
  suspended: false

backup:
  enabled: true
  schedule: weekly
  output_dir: /var/backups/auto-ssl
  retention: 4
  passphrase_file: /etc/auto-ssl/backup-passphrase
```

**Fields**:
- `ca.url` - CA HTTPS endpoint
- `ca.fingerprint` - SHA256 fingerprint of root CA
- `ca.name` - Human-readable CA name
- `ca.steppath` - Path to step-ca data (CA server only)
- `defaults.cert_duration` - Default certificate validity period
- `defaults.max_cert_duration` - Maximum allowed certificate duration
- `server.cert_path` - Path to server certificate
- `server.key_path` - Path to server private key
- `server.sans` - Comma-separated list of SANs
- `server.suspended` - Whether renewal is suspended
- `backup.*` - Backup configuration

**Permissions**: `600` (readable only by root)

## CA Configuration

### `/opt/step-ca/config/ca.json`

step-ca configuration file.

**Format**: JSON

**Location**: Created by `auto-ssl ca init`

**Example**:
```json
{
  "root": "/opt/step-ca/certs/root_ca.crt",
  "crt": "/opt/step-ca/certs/intermediate_ca.crt",
  "key": "/opt/step-ca/secrets/intermediate_ca_key",
  "address": "192.168.1.100:9000",
  "dnsNames": ["192.168.1.100"],
  "logger": {
    "format": "text"
  },
  "db": {
    "type": "badger",
    "dataSource": "/opt/step-ca/db"
  },
  "authority": {
    "provisioners": [
      {
        "type": "JWK",
        "name": "admin",
        "key": {
          "use": "sig",
          "kty": "EC",
          "kid": "...",
          "crv": "P-256",
          "alg": "ES256",
          "x": "...",
          "y": "..."
        },
        "encryptedKey": "..."
      },
      {
        "type": "ACME",
        "name": "acme"
      }
    ],
    "claims": {
      "minTLSCertDuration": "1h",
      "maxTLSCertDuration": "720h",
      "defaultTLSCertDuration": "168h",
      "disableRenewal": false
    }
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3
  }
}
```

**Key Fields**:
- `address` - IP and port to listen on
- `provisioners` - Certificate issuance methods
- `authority.claims` - Certificate duration policies
- `tls` - TLS configuration for CA endpoint

**Permissions**: `644` (world-readable)

**Editing**: Must restart step-ca after changes: `sudo systemctl restart step-ca`

## Password Files

### `/etc/auto-ssl/ca-password`

CA private key password.

**Format**: Plain text, single line

**Location**: Created by `auto-ssl ca init`

**Permissions**: `600` (readable only by root)

**Used by**: step-ca service to unlock private keys

**Security**: This file must be protected. Anyone with access can issue certificates.

### `/etc/auto-ssl/backup-passphrase`

Backup encryption passphrase.

**Format**: Plain text, single line

**Location**: Created by `auto-ssl ca backup-schedule --enable`

**Permissions**: `600`

**Security**: Required to decrypt backups. Store securely.

## Inventory

### `/etc/auto-ssl/servers.yaml`

Enrolled servers inventory (CA server only).

**Format**: YAML

**Location**: Created by `auto-ssl remote enroll`

**Example**:
```yaml
servers:
  - host: 192.168.1.50
    name: web-server-1
    user: admin
    enrolled: true
    enrolled_at: 2024-01-15T10:30:00Z
  - host: 192.168.1.51
    name: app-server-1
    user: admin
    enrolled: true
    enrolled_at: 2024-01-15T11:00:00Z
```

**Fields**:
- `host` - Server IP or hostname
- `name` - Friendly name
- `user` - SSH username for remote access
- `enrolled` - Enrollment status
- `enrolled_at` - Timestamp of enrollment

**Permissions**: `600`

## Systemd Units

### `/etc/systemd/system/step-ca.service`

step-ca systemd service.

**Location**: Created by `auto-ssl ca init`

**Example**:
```ini
[Unit]
Description=Smallstep CA
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=STEPPATH=/opt/step-ca
ExecStart=/usr/bin/step-ca --password-file=/etc/auto-ssl/ca-password /opt/step-ca/config/ca.json
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/step-ca
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

### `/etc/systemd/system/auto-ssl-renew.service`

Certificate renewal service.

**Location**: Created by `auto-ssl server enroll`

**Example**:
```ini
[Unit]
Description=Renew auto-ssl certificate
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/step ca renew --force /etc/ssl/auto-ssl/server.crt /etc/ssl/auto-ssl/server.key
# Optional: reload web server after renewal
# ExecStartPost=/usr/bin/systemctl reload nginx
```

### `/etc/systemd/system/auto-ssl-renew.timer`

Certificate renewal timer.

**Location**: Created by `auto-ssl server enroll`

**Example**:
```ini
[Unit]
Description=Renew auto-ssl certificate periodically

[Timer]
# Run every 5 days (for 7-day certificates)
OnCalendar=*-*-01,06,11,16,21,26 00:00:00
# Add random delay to avoid thundering herd
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
```

### `/etc/systemd/system/auto-ssl-backup.service` and `.timer`

Automatic backup service and timer.

**Location**: Created by `auto-ssl ca backup-schedule --enable`

## Shell Completions

### `/etc/bash_completion.d/auto-ssl`

Bash completion script.

**Location**: Installed by `make install-completions`

**Usage**: Automatic after install. Provides tab completion for commands.

### `/usr/share/zsh/site-functions/_auto-ssl`

Zsh completion script.

**Location**: Installed by `make install-completions` (if zsh detected)

## Environment Variables

Programs respect these environment variables:

**auto-ssl**:
- `AUTO_SSL_CONFIG_DIR` - Override config directory
- `AUTO_SSL_DATA_DIR` - Override data directory
- `AUTO_SSL_CERT_DIR` - Override certificate directory
- `AUTO_SSL_DEBUG` - Enable debug output

**step-ca**:
- `STEPPATH` - CA data directory

**step CLI**:
- `STEPPATH` - Client configuration directory

## Configuration Best Practices

1. **Never commit** password files to version control
2. **Backup** `/etc/auto-ssl/` regularly
3. **Protect** config files with proper permissions
4. **Document** custom settings
5. **Test** changes in dev first
6. **Version control** your customizations (minus secrets)

## See Also

- [CLI Reference](cli-reference.md)
- [CA Setup Guide](../guides/ca-setup.md)
- [Architecture](architecture.md)
