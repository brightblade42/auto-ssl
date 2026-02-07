# CA Setup Guide

Complete guide to setting up your Certificate Authority server with auto-ssl.

## Prerequisites

### Hardware Requirements
- **Minimum**: 1 CPU core, 512MB RAM, 10GB disk
- **Recommended**: 2 CPU cores, 1GB RAM, 20GB disk
- Dedicated machine or VM (don't share with application servers)

### Operating System
- RHEL/Rocky Linux/AlmaLinux 8+
- Ubuntu 20.04+ / Debian 11+
- Fedora 35+

### Network Requirements
- Static IP address (required)
- Port 9000 accessible from all servers needing certificates
- (Optional) Port 443 for ACME if using with Caddy/certbot

### Before You Start
- Choose your CA name (e.g., "MyCompany Internal CA")
- Decide on certificate duration (default: 7 days)
- Plan backup strategy

## Installation

### Option 1: One-liner Install

```bash
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | sudo bash
```

### Option 2: From Source

```bash
git clone https://github.com/Brightblade42/auto-ssl.git
cd auto-ssl
sudo make install
```

### Verify Installation

```bash
auto-ssl version
```

Should output version information.

## Initialize the CA

### Basic Initialization

```bash
sudo auto-ssl ca init --name "My Internal CA"
```

This will:
1. Detect your primary IP address
2. Install step-ca and step CLI
3. Initialize the CA with default settings
4. Create systemd service
5. Start the CA server
6. Open firewall port (if firewalld is active)

### Advanced Initialization

```bash
sudo auto-ssl ca init \
  --name "MyCompany Internal CA" \
  --address "192.168.1.100:9000" \
  --cert-duration 168h \
  --max-duration 720h \
  --password-file /secure/ca-password
```

**Options:**
- `--name`: CA display name (appears in certificates)
- `--address`: IP:port to listen on (use your static IP)
- `--cert-duration`: Default certificate validity (168h = 7 days)
- `--max-duration`: Maximum certificate validity (720h = 30 days)
- `--password-file`: Read CA password from file (for automation)

### What Gets Created

```
/opt/step-ca/
├── config/
│   └── ca.json              # CA configuration
├── certs/
│   ├── root_ca.crt          # Root certificate (trust this)
│   ├── intermediate_ca.crt  # Intermediate certificate
│   └── root_ca.key          # Root private key (protect!)
├── secrets/
│   └── intermediate_ca_key  # Intermediate private key
└── db/                      # Certificate database

/etc/auto-ssl/
├── config.yaml              # auto-ssl configuration
└── ca-password              # CA password (protected)

/etc/systemd/system/
└── step-ca.service          # systemd service
```

## Post-Installation

### 1. Save Important Information

After initialization, you'll see:

```
CA Name:        My Internal CA
CA URL:         https://192.168.1.100:9000
Root CA:        /opt/step-ca/certs/root_ca.crt
ACME Directory: https://192.168.1.100:9000/acme/acme/directory

Root Fingerprint:
abc123def456789...

Save this fingerprint! You'll need it for server enrollment.
```

**Save these somewhere secure:**
- Root CA fingerprint
- CA password (in `/etc/auto-ssl/ca-password`)
- Root CA certificate

### 2. Verify CA is Running

```bash
sudo systemctl status step-ca
```

Should show "active (running)".

### 3. Check CA Health

```bash
curl -k https://192.168.1.100:9000/health
```

Should return `{"status":"ok"}`.

### 4. Verify Provisioners

```bash
export STEPPATH=/opt/step-ca
step ca provisioner list
```

Should show:
- `admin` (JWK provisioner)
- `acme` (ACME provisioner)

## Configuration

### Adjusting Certificate Duration

Edit `/opt/step-ca/config/ca.json`:

```json
{
  "authority": {
    "claims": {
      "defaultTLSCertDuration": "168h",
      "maxTLSCertDuration": "720h",
      "minTLSCertDuration": "1h"
    }
  }
}
```

Restart after changes:
```bash
sudo systemctl restart step-ca
```

### Adding Additional Provisioners

```bash
# Add a new JWK provisioner for a specific team
export STEPPATH=/opt/step-ca
step ca provisioner add devteam --create

# Add ACME provisioner with specific settings
step ca provisioner add acme-custom --type ACME
```

### Changing the CA Address

If you need to change the IP address:

```bash
# 1. Stop CA
sudo systemctl stop step-ca

# 2. Edit config
sudo nano /opt/step-ca/config/ca.json
# Update "address" and "dnsNames"

# 3. Update auto-ssl config
sudo nano /etc/auto-ssl/config.yaml
# Update ca.url

# 4. Restart
sudo systemctl start step-ca
```

## Firewall Configuration

### firewalld (RHEL/CentOS/Fedora)

```bash
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
```

### ufw (Ubuntu/Debian)

```bash
sudo ufw allow 9000/tcp
sudo ufw status
```

### iptables

```bash
sudo iptables -A INPUT -p tcp --dport 9000 -j ACCEPT
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

## Backup and Restore

### Create Manual Backup

```bash
sudo auto-ssl ca backup --output /backup/ca-$(date +%Y%m%d).enc
```

You'll be prompted for a backup passphrase. **Store this securely!**

### Set Up Automatic Backups

```bash
sudo auto-ssl ca backup-schedule \
  --enable \
  --schedule weekly \
  --retention 4
```

Backs up weekly, keeps 4 most recent backups in `/var/backups/auto-ssl/`.

### Restore from Backup

```bash
sudo auto-ssl ca restore --input /backup/ca-20240115.enc
```

## Security Hardening

### 1. Restrict Network Access

Only allow CA port from your internal network:

```bash
# firewalld with zone
sudo firewall-cmd --permanent --zone=internal \
  --add-source=192.168.0.0/16
sudo firewall-cmd --permanent --zone=internal \
  --add-port=9000/tcp
sudo firewall-cmd --reload
```

### 2. Protect the Root Key

The root CA private key is at `/opt/step-ca/secrets/root_ca_key`. This is **extremely sensitive**.

```bash
# Verify permissions
sudo ls -l /opt/step-ca/secrets/
# Should be: -rw------- (600) root root
```

**Consider**: Moving root key to offline storage after CA initialization (advanced).

### 3. Enable Audit Logging

```bash
# Add to /opt/step-ca/config/ca.json
{
  "logger": {
    "format": "json",
    "file": "/var/log/step-ca/audit.log"
  }
}
```

### 4. Regular Security Updates

```bash
# Update step-ca
sudo systemctl stop step-ca
# Download latest release and replace binary
sudo systemctl start step-ca
```

## Monitoring

### Check CA Status

```bash
auto-ssl ca status
```

### Monitor Certificate Issuance

```bash
# View step-ca logs
sudo journalctl -u step-ca -f
```

### Monitor Health Endpoint

Add to your monitoring system:
```bash
curl -f https://ca.internal:9000/health || alert
```

## Troubleshooting

### CA Won't Start

```bash
# Check logs
sudo journalctl -u step-ca -n 50

# Common issues:
# - Port already in use: sudo netstat -tlnp | grep 9000
# - Permission issues: sudo chown -R root:root /opt/step-ca
# - Config errors: sudo step-ca /opt/step-ca/config/ca.json --dry-run
```

### Port Not Accessible

```bash
# Test from another machine
curl -k https://CA_IP:9000/health

# Check firewall
sudo firewall-cmd --list-all
sudo iptables -L -n | grep 9000

# Check if service is listening
sudo netstat -tlnp | grep 9000
```

### Reset CA (Danger!)

```bash
# This destroys your CA and all issued certificates!
sudo systemctl stop step-ca
sudo rm -rf /opt/step-ca
sudo rm -rf /etc/auto-ssl
sudo auto-ssl ca init --name "My Internal CA"
```

**Note**: All enrolled servers will need re-enrollment.

## Next Steps

- **[Server Enrollment](server-enrollment.md)** — Enroll your first server
- **[Client Trust](client-trust.md)** — Trust the CA on client machines
- **[Backup & Restore](backup-restore.md)** — Detailed backup strategies
- **[Troubleshooting](troubleshooting.md)** — Common issues and solutions
