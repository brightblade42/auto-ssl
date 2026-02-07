# Server Enrollment Guide

Guide to enrolling servers and obtaining certificates with auto-ssl.

## Overview

Server enrollment is the process of:
1. Installing auto-ssl on a server
2. Obtaining a certificate from the CA
3. Setting up automatic renewal

## Prerequisites

- CA server running and accessible
- CA URL and fingerprint (from CA setup)
- SSH access to the server (for remote enrollment)
- OR sudo access (for local enrollment)

## Methods

### Method 1: Local Enrollment (On the Server)

SSH into the server and run:

```bash
# Install auto-ssl
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | sudo bash

# Enroll
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123def456...
```

You'll be prompted for the provisioner password.

### Method 2: Remote Enrollment (From CA Server)

From the CA server:

```bash
auto-ssl remote enroll \
  --host 192.168.1.50 \
  --user admin
```

This handles everything via SSH.

## Enrollment Options

### Basic Enrollment

```bash
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123def456...
```

Uses default settings:
- Certificate location: `/etc/ssl/auto-ssl/server.crt`
- Private key: `/etc/ssl/auto-ssl/server.key`
- SAN: Primary IP address
- Auto-renewal: Enabled

### Custom SANs

Add multiple names/IPs to the certificate:

```bash
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123 \
  --san 192.168.1.50 \
  --san myserver.local \
  --san myserver.internal
```

### Custom Certificate Location

```bash
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123 \
  --cert-path /etc/nginx/certs/server.crt \
  --key-path /etc/nginx/certs/server.key
```

### Non-Interactive Enrollment

For automation:

```bash
# Create password file
echo "your-provisioner-password" | sudo tee /etc/auto-ssl/provision-pw
sudo chmod 600 /etc/auto-ssl/provision-pw

# Enroll
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123 \
  --password-file /etc/auto-ssl/provision-pw \
  --non-interactive
```

### Skip Auto-Renewal Setup

If you want to handle renewal yourself:

```bash
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123 \
  --no-renewal
```

## What Happens During Enrollment

1. **Install step CLI** (if not present)
2. **Bootstrap trust** to the CA
3. **Request certificate** with specified SANs
4. **Save certificate and key** to disk
5. **Set permissions** (644 for cert, 600 for key)
6. **Verify certificate** with root CA
7. **Set up renewal timer** (systemd)
8. **Save configuration** to `/etc/auto-ssl/config.yaml`

## After Enrollment

### Verify Certificate

```bash
# Check status
auto-ssl server status

# Inspect certificate
openssl x509 -in /etc/ssl/auto-ssl/server.crt -text -noout

# Verify against CA
step certificate verify /etc/ssl/auto-ssl/server.crt \
  --roots $(step path)/certs/root_ca.crt
```

### Configure Your Web Server

See integration guides:
- [Caddy Integration](caddy-integration.md)
- [nginx Integration](nginx-integration.md)

### Test HTTPS

```bash
# From another machine
curl https://192.168.1.50

# Should work without -k flag if CA is trusted
```

## Certificate Renewal

### Automatic Renewal

By default, certificates renew every 5 days (for 7-day certificates):

```bash
# Check renewal timer
systemctl status auto-ssl-renew.timer

# View next renewal time
systemctl list-timers auto-ssl-renew.timer
```

### Manual Renewal

```bash
# Force immediate renewal
sudo auto-ssl server renew --force

# Renew and reload nginx
sudo auto-ssl server renew --force --exec "systemctl reload nginx"
```

### Renewal Troubleshooting

```bash
# Check renewal service logs
sudo journalctl -u auto-ssl-renew.service -n 50

# Test renewal manually
sudo systemctl start auto-ssl-renew.service

# Common issues:
# - CA not reachable: check network/firewall
# - Certificate expired: run manual renewal with --force
# - Permission errors: check file ownership
```

## Managing Certificates

### View Certificate Details

```bash
auto-ssl server status
```

Shows:
- Certificate path
- Expiration date
- Days remaining
- Renewal timer status
- CA connectivity

### Revoke Certificate

If a private key is compromised:

```bash
sudo auto-ssl server revoke --reason "Key compromised"
```

Then re-enroll:

```bash
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123
```

### Remove Server

To completely remove auto-ssl:

```bash
# Stop and disable renewal timer
sudo systemctl stop auto-ssl-renew.timer
sudo systemctl disable auto-ssl-renew.timer

# Remove certificates
sudo rm -rf /etc/ssl/auto-ssl/

# Remove configuration
sudo rm -rf /etc/auto-ssl/

# Remove step trust
rm -rf ~/.step/
```

## Integration Examples

### nginx

```nginx
server {
    listen 443 ssl;
    server_name myserver.local;
    
    ssl_certificate     /etc/ssl/auto-ssl/server.crt;
    ssl_certificate_key /etc/ssl/auto-ssl/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://localhost:8080;
    }
}
```

Reload nginx after renewal:
```bash
# Edit /etc/systemd/system/auto-ssl-renew.service
ExecStartPost=/usr/bin/systemctl reload nginx
```

### Apache

```apache
<VirtualHost *:443>
    ServerName myserver.local
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/auto-ssl/server.crt
    SSLCertificateKeyFile /etc/ssl/auto-ssl/server.key
    
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/
</VirtualHost>
```

### Go Application

```go
package main

import (
    "log"
    "net/http"
)

func main() {
    http.HandleFunc("/", handler)
    
    log.Println("Starting server on :443")
    err := http.ListenAndServeTLS(":443",
        "/etc/ssl/auto-ssl/server.crt",
        "/etc/ssl/auto-ssl/server.key",
        nil)
    if err != nil {
        log.Fatal(err)
    }
}
```

## Troubleshooting

### Enrollment Fails

```bash
# Verify CA is reachable
curl -k https://CA_IP:9000/health

# Check fingerprint
step certificate fingerprint <(curl -k https://CA_IP:9000/roots.pem)

# Verify provisioner password
step ca token 192.168.1.50 --ca-url https://CA_IP:9000
```

### Certificate Not Trusted

The client machines need to trust your CA:
```bash
# On client machines
sudo auto-ssl client trust \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123
```

### Renewal Fails

```bash
# Check if CA is reachable
curl -k https://CA_IP:9000/health

# Check certificate isn't expired
openssl x509 -in /etc/ssl/auto-ssl/server.crt -noout -enddate

# Force renewal
sudo auto-ssl server renew --force
```

## Best Practices

1. **Use Remote Enrollment** when possible (cleaner, centralized)
2. **Store Provisioner Passwords Securely** (use password files with 600 permissions)
3. **Monitor Renewal Timers** (set up alerts)
4. **Test Certificate Changes** before applying to production
5. **Document Your SANs** (keep a list of what each server needs)
6. **Automate Post-Renewal Actions** (reload web servers)

## Next Steps

- **[Caddy Integration](caddy-integration.md)** — Use ACME with Caddy
- **[nginx Integration](nginx-integration.md)** — Configure nginx
- **[Client Trust](client-trust.md)** — Trust CA on clients
- **[Troubleshooting](troubleshooting.md)** — Common issues
