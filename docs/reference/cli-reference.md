# CLI Reference

Complete command reference for auto-ssl.

## Global Options

```bash
auto-ssl [command] [subcommand] [options]
```

**Environment Variables**:
- `AUTO_SSL_CONFIG_DIR` - Config directory (default: `/etc/auto-ssl`)
- `AUTO_SSL_DATA_DIR` - Data directory (default: `/var/lib/auto-ssl`)
- `AUTO_SSL_CERT_DIR` - Certificate directory (default: `/etc/ssl/auto-ssl`)
- `AUTO_SSL_DEBUG` - Enable debug logging (set to `1`)
- `STEPPATH` - Step CLI path (default: `/opt/step-ca` for CA, `~/.step` for clients)

## CA Commands

### `ca init`

Initialize this machine as a Certificate Authority.

**Synopsis**:
```bash
auto-ssl ca init [options]
```

**Options**:
- `--name NAME` - CA name (default: "Internal CA")
- `--address ADDR` - Listen address (default: auto-detected IP:9000)
- `--cert-duration DUR` - Default certificate duration (default: 168h / 7 days)
- `--max-duration DUR` - Maximum certificate duration (default: 720h / 30 days)
- `--password-file FILE` - Read CA password from file
- `--non-interactive` - Don't prompt for input
- `-h, --help` - Show help

**Examples**:
```bash
# Basic initialization
sudo auto-ssl ca init --name "My Internal CA"

# Custom settings
sudo auto-ssl ca init \
  --name "Production CA" \
  --address "10.0.1.100:9000" \
  --cert-duration 168h \
  --max-duration 720h
```

### `ca status`

Show CA health and configuration.

**Synopsis**:
```bash
auto-ssl ca status
```

### `ca backup`

Create encrypted backup of CA.

**Synopsis**:
```bash
auto-ssl ca backup [options]
```

**Options**:
- `--output FILE` - Output file path (required)
- `--passphrase-file FILE` - Read encryption passphrase from file
- `--dest-type TYPE` - Destination type: local, rsync, s3 (default: local)
- `--rsync-target HOST` - rsync target (user@host:path)
- `--s3-bucket BUCKET` - S3 bucket name
- `--s3-endpoint URL` - S3 endpoint URL
- `--s3-prefix PREFIX` - S3 key prefix (default: auto-ssl/)

**Examples**:
```bash
# Local backup
sudo auto-ssl ca backup --output /backup/ca-backup.enc

# Backup to S3
sudo auto-ssl ca backup \
  --output ca-backup.enc \
  --dest-type s3 \
  --s3-bucket my-backups \
  --s3-endpoint https://s3.wasabisys.com
```

### `ca restore`

Restore CA from backup.

**Synopsis**:
```bash
auto-ssl ca restore [options]
```

**Options**:
- `--input FILE` - Input backup file (required)
- `--passphrase-file FILE` - Read decryption passphrase from file
- `--new-address ADDR` - Use new address (if CA IP changed)

### `ca reset`

Delete local CA and auto-ssl state to start over.

**Synopsis**:
```bash
auto-ssl ca reset [options]
```

**Options**:
- `--yes` - Skip confirmation prompts
- `--no-backup` - Skip safety backup before deletion

### `ca backup-schedule`

Configure automatic backups.

**Synopsis**:
```bash
auto-ssl ca backup-schedule [options]
```

**Options**:
- `--enable` - Enable scheduled backups
- `--disable` - Disable scheduled backups
- `--schedule SCHEDULE` - Backup schedule: daily, weekly, monthly (default: weekly)
- `--output DIR` - Backup output directory (default: /var/backups/auto-ssl)
- `--retention NUM` - Number of backups to keep (default: 4)
- `--passphrase-file FILE` - Passphrase file for encryption

## Server Commands

### `server enroll`

Enroll this server to get certificates.

**Synopsis**:
```bash
auto-ssl server enroll [options]
```

**Options**:
- `--ca-url URL` - CA server URL (required)
- `--fingerprint FP` - CA root fingerprint (required)
- `--san NAME` - Subject Alternative Name (can repeat)
- `--duration DUR` - Certificate duration (default: from CA)
- `--cert-path PATH` - Where to store certificate (default: /etc/ssl/auto-ssl/server.crt)
- `--key-path PATH` - Where to store private key (default: /etc/ssl/auto-ssl/server.key)
- `--provisioner NAME` - Provisioner name (default: admin)
- `--password-file FILE` - Provisioner password file
- `--no-renewal` - Don't set up automatic renewal
- `--non-interactive` - Don't prompt for input (requires `--password-file`)

**Examples**:
```bash
# Basic enrollment
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123

# With multiple SANs
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123 \
  --san 192.168.1.50 \
  --san myserver.local \
  --san myserver.internal
```

### `server status`

Show certificate status and expiration.

**Synopsis**:
```bash
auto-ssl server status
```

### `server renew`

Force immediate certificate renewal.

**Synopsis**:
```bash
auto-ssl server renew [options]
```

**Options**:
- `--force` - Force renewal even if certificate is still valid
- `--exec CMD` - Command to run after successful renewal

**Examples**:
```bash
# Force renewal
sudo auto-ssl server renew --force

# Renew and reload nginx
sudo auto-ssl server renew --force --exec "systemctl reload nginx"
```

### `server suspend`

Temporarily disable automatic certificate renewal.

**Synopsis**:
```bash
auto-ssl server suspend [options]
```

**Options**:
- `--reason TEXT` - Reason for suspension

### `server resume`

Re-enable automatic certificate renewal.

**Synopsis**:
```bash
auto-ssl server resume
```

### `server revoke`

Revoke the server certificate.

**Synopsis**:
```bash
auto-ssl server revoke [options]
```

**Options**:
- `--reason TEXT` - Reason for revocation
- `--serial NUM` - Certificate serial number (if not current cert)

### `server remove`

Revoke certificate and remove auto-ssl completely.

**Synopsis**:
```bash
auto-ssl server remove [options]
```

**Options**:
- `--reason TEXT` - Reason for removal
- `--keep-certs` - Don't delete certificate files

## Remote Commands

### `remote enroll`

Enroll a remote server via SSH.

**Synopsis**:
```bash
auto-ssl remote enroll [options]
```

**Options**:
- `--host HOST` - Target server hostname or IP (required)
- `--user USER` - SSH username (required)
- `--name NAME` - Friendly name for the server (default: hostname)
- `--port PORT` - SSH port (default: 22)
- `--san NAME` - Additional SAN for the certificate (can repeat)
- `--identity FILE` - SSH identity file

**Examples**:
```bash
# Basic remote enrollment
auto-ssl remote enroll --host 192.168.1.50 --user admin

# With custom name and SANs
auto-ssl remote enroll \
  --host 192.168.1.50 \
  --user admin \
  --name web-server-1 \
  --san myserver.local
```

### `remote status`

Check remote server certificate status.

**Synopsis**:
```bash
auto-ssl remote status [options]
```

**Options**:
- `--host HOST` - Target server (required unless --all)
- `--user USER` - SSH username (required unless --all)
- `--all` - Check all enrolled servers
- `--port PORT` - SSH port (default: 22)

### `remote update-ca-url`

Update CA URL on enrolled servers.

**Synopsis**:
```bash
auto-ssl remote update-ca-url [options]
```

**Options**:
- `--new-url URL` - New CA URL (required)
- `--host HOST` - Update single host (default: all enrolled)
- `--user USER` - SSH username (required if --host)

### `remote list`

List enrolled servers.

**Synopsis**:
```bash
auto-ssl remote list
```

## Client Commands

### `client trust`

Install root CA into system trust store.

**Synopsis**:
```bash
auto-ssl client trust [options]
```

**Options**:
- `--ca-url URL` - CA server URL (required)
- `--fingerprint FP` - CA root fingerprint (required)
- `--cert-file FILE` - Use local CA cert file instead of downloading

**Examples**:
```bash
# Trust CA by downloading root cert
sudo auto-ssl client trust \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123

# Trust from local file
sudo auto-ssl client trust --cert-file /path/to/root_ca.crt
```

### `client status`

Verify root CA is trusted.

**Synopsis**:
```bash
auto-ssl client status
```

## General Commands

### `info`

Show detected environment and configuration.

**Synopsis**:
```bash
auto-ssl info
```

### `version`

Show version information.

**Synopsis**:
```bash
auto-ssl version
auto-ssl -v
auto-ssl --version
```

### `help`

Show help message.

**Synopsis**:
```bash
auto-ssl help
auto-ssl -h
auto-ssl --help
auto-ssl [command] --help
```

## auto-ssl-tui Companion CLI

`auto-ssl-tui` is a bootstrap/helper companion for packaging, dependency checks, runtime extraction, and command pass-through.

### `auto-ssl-tui --version`

Show companion build version.

### `auto-ssl-tui doctor [--json]`

Show dependency and environment readiness (`step`, `step-ca`, `curl`, and workflow-related tools).

### `auto-ssl-tui install-deps [--yes]`

Install missing dependencies using supported package managers.

- Default mode asks for confirmation per dependency.
- `--yes` skips confirmation (automation mode).

### `auto-ssl-tui dump-bash`

Extract embedded Bash scripts for standalone use.

```bash
auto-ssl-tui dump-bash [--output DIR] [--force] [--print-path] [--checksum]
```

- Default output directory: `./auto-ssl-bash`

### `auto-ssl-tui exec -- <args...>`

Run the embedded `auto-ssl` runtime directly.

## Exit Codes

- `0` - Success
- `1` - General error
- `2` - Invalid arguments
- `3` - Missing dependencies
- `4` - Permission denied
- `5` - Network error

## Files

- `/etc/auto-ssl/config.yaml` - Configuration file
- `/etc/auto-ssl/ca-password` - CA password (on CA server)
- `/etc/auto-ssl/servers.yaml` - Server inventory (on CA server)
- `/etc/ssl/auto-ssl/server.crt` - Server certificate
- `/etc/ssl/auto-ssl/server.key` - Server private key
- `/opt/step-ca/` - CA data directory
- `/var/lib/auto-ssl/cert-backups/` - Certificate backups
- `/var/log/auto-ssl/` - Log files (if configured)

## See Also

- `step(1)` - Smallstep CLI
- `step-ca(8)` - Smallstep CA server
- [Quick Start Guide](../guides/quickstart.md)
- [Troubleshooting](../guides/troubleshooting.md)
