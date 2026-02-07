# Quick Start Guide

Get HTTPS working on your internal network in 5 minutes.

## Prerequisites

- One machine to be the CA server (Linux: RHEL/Rocky/Ubuntu)
- SSH access to servers you want to enroll
- Ability to install software on client machines (macOS/Windows/Linux)

## Step 1: Set Up the CA (2 minutes)

On the machine that will be your CA server:

```bash
# Download and install auto-ssl
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash

# Initialize the CA
sudo auto-ssl ca init \
  --name "My Internal CA" \
  --address "$(hostname -I | awk '{print $1}'):9000"
```

You'll see output like:

```
✓ Installed step-ca
✓ Initialized CA: My Internal CA
✓ Enabled ACME provisioner
✓ Started step-ca service

CA is running at: https://192.168.1.100:9000
Root fingerprint: abc123def456...

Save this fingerprint! You'll need it for server enrollment.
```

**Save the fingerprint** — you'll need it for the next steps.

## Step 2: Enroll a Server (1 minute)

On each server that needs certificates:

```bash
# Download and install auto-ssl
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash

# Enroll this server
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123def456
```

Output:

```
✓ Installed step CLI
✓ Bootstrapped trust to CA
✓ Issued certificate for 192.168.1.50
✓ Set up automatic renewal (every 5 days)

Certificate: /etc/ssl/auto-ssl/server.crt
Private key: /etc/ssl/auto-ssl/server.key
```

Your certificates are ready to use!

### OR: Enroll Remotely from the CA Server

If you don't want to SSH into each server manually:

```bash
# From the CA server, enroll a remote server via SSH
sudo auto-ssl remote enroll \
  --host 192.168.1.50 \
  --user ryan
```

## Step 3: Use the Certificates

### With Caddy (easiest)

Caddy can get certificates automatically via ACME — no manual cert handling:

```
# Caddyfile
{
    acme_ca https://192.168.1.100:9000/acme/acme/directory
    acme_ca_root /etc/ssl/auto-ssl/root_ca.crt
}

192.168.1.50 {
    reverse_proxy localhost:8080
}
```

### With nginx

```nginx
server {
    listen 443 ssl;
    server_name 192.168.1.50;
    
    ssl_certificate     /etc/ssl/auto-ssl/server.crt;
    ssl_certificate_key /etc/ssl/auto-ssl/server.key;
    
    location / {
        proxy_pass http://localhost:8080;
    }
}
```

Reload nginx after certificate renewal:

```bash
# Edit /etc/systemd/system/auto-ssl-renew.service to add:
ExecStartPost=/usr/bin/systemctl reload nginx
```

### With a Go application

```go
http.ListenAndServeTLS(":443",
    "/etc/ssl/auto-ssl/server.crt",
    "/etc/ssl/auto-ssl/server.key",
    handler,
)
```

## Step 4: Trust the CA on Clients (1 minute each)

On each client machine (laptop, desktop), install the root CA:

```bash
# Download and install auto-ssl (or just download the root CA)
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash

# Trust the CA
sudo auto-ssl client trust \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123def456
```

### Manual Trust Installation

#### macOS

```bash
# Download root CA
curl -k -o root_ca.crt https://192.168.1.100:9000/roots.pem

# Add to system keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain root_ca.crt
```

#### Windows

1. Download `https://192.168.1.100:9000/roots.pem`
2. Rename to `root_ca.crt`
3. Double-click → Install Certificate
4. Select "Local Machine"
5. Place in "Trusted Root Certification Authorities"
6. Restart browser

#### Linux (RHEL/Fedora)

```bash
curl -k -o root_ca.crt https://192.168.1.100:9000/roots.pem
sudo cp root_ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

#### Linux (Ubuntu/Debian)

```bash
curl -k -o root_ca.crt https://192.168.1.100:9000/roots.pem
sudo cp root_ca.crt /usr/local/share/ca-certificates/internal-ca.crt
sudo update-ca-certificates
```

## Step 5: Verify It Works

Open a browser and navigate to your server:

```
https://192.168.1.50
```

You should see:
- A padlock icon (secure connection)
- No certificate warnings
- Certificate issued by "My Internal CA"

From the command line:

```bash
# Should work without -k flag now
curl https://192.168.1.50
```

## What's Happening Behind the Scenes

1. **CA server** runs `step-ca`, listening on port 9000
2. **Servers** have certificates signed by your CA, auto-renewed every 5 days
3. **Clients** trust your root CA, so they accept your server certificates

```
Client                    Server                    CA
  │                         │                        │
  │──── HTTPS request ─────▶│                        │
  │                         │                        │
  │◀─── Certificate ────────│                        │
  │     (signed by CA)      │                        │
  │                         │                        │
  │ Verify: Is this cert    │                        │
  │ signed by a CA I trust? │                        │
  │ ✓ Yes! (root CA in      │                        │
  │   trust store)          │                        │
  │                         │                        │
  │◀════ Encrypted ════════▶│                        │
  │      Communication      │                        │
```

## Next Steps

- **Run a full Linux validation pass** — `./scripts/validate-linux.sh`
- **[CA Setup Guide](ca-setup.md)** — Detailed CA configuration options
- **[Server Enrollment](server-enrollment.md)** — Advanced enrollment options
- **[Backup & Restore](backup-restore.md)** — Protect your CA
- **[Troubleshooting](troubleshooting.md)** — Common issues and fixes

## Troubleshooting Quick Fixes

### "Connection refused" to CA

```bash
# Check if step-ca is running
sudo systemctl status step-ca

# Check firewall
sudo firewall-cmd --add-port=9000/tcp --permanent
sudo firewall-cmd --reload
```

### "Certificate not trusted" in browser

The root CA isn't installed on the client. Run `auto-ssl client trust` or manually install the root certificate.

### "Certificate expired"

Renewal isn't working. Check the renewal timer:

```bash
sudo systemctl status auto-ssl-renew.timer
sudo journalctl -u auto-ssl-renew.service
```

Force immediate renewal:

```bash
sudo auto-ssl server renew --force
```

### "I want to start over"

On a CA server:

```bash
sudo auto-ssl ca reset
```

On an enrolled app server:

```bash
sudo auto-ssl server remove
```
