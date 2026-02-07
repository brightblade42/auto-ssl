# Caddy Integration Guide

Caddy has native ACME support, making it the easiest web server to integrate with auto-ssl.

## Why Caddy?

- **Automatic HTTPS**: Built-in ACME client
- **Auto-renewal**: Handles renewals automatically  
- **Simple config**: No complex SSL directives
- **Zero-downtime reloads**: Updates certs without restarting

## Installation

### RHEL/Rocky/CentOS

```bash
dnf install 'dnf-command(copr)'
dnf copr enable @caddy/caddy
dnf install caddy
```

### Ubuntu/Debian

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

## Configuration

### Basic Setup with ACME

Edit `/etc/caddy/Caddyfile`:

```
# Global options
{
    # Point to your internal CA
    acme_ca https://192.168.1.100:9000/acme/acme/directory
    
    # Trust your CA's root certificate
    acme_ca_root /etc/ssl/auto-ssl/root_ca.crt
    
    # Email for important notifications
    email admin@example.com
}

# Site configuration
192.168.1.50 {
    reverse_proxy localhost:8080
}
```

### Multiple Sites

```
{
    acme_ca https://192.168.1.100:9000/acme/acme/directory
    acme_ca_root /etc/ssl/auto-ssl/root_ca.crt
}

# App server 1
192.168.1.50 {
    reverse_proxy localhost:8080
}

# App server 2
192.168.1.51 {
    reverse_proxy localhost:3000
}

# Named host
myapp.internal {
    reverse_proxy localhost:8080
    log {
        output file /var/log/caddy/myapp.log
    }
}
```

### Static Site

```
{
    acme_ca https://192.168.1.100:9000/acme/acme/directory
    acme_ca_root /etc/ssl/auto-ssl/root_ca.crt
}

192.168.1.50 {
    root * /var/www/html
    file_server
}
```

## Trust the CA

Before Caddy can verify your CA's certificates, install the root CA:

```bash
# Download root CA
sudo mkdir -p /etc/ssl/auto-ssl
curl -k https://192.168.1.100:9000/roots.pem | sudo tee /etc/ssl/auto-ssl/root_ca.crt
```

Or if you enrolled this server:
```bash
# Root CA is already at:
# /root/.step/certs/root_ca.crt
sudo cp /root/.step/certs/root_ca.crt /etc/ssl/auto-ssl/root_ca.crt
```

## Start Caddy

```bash
# Enable and start
sudo systemctl enable caddy
sudo systemctl start caddy

# Check status
sudo systemctl status caddy

# View logs
sudo journalctl -u caddy -f
```

## Verify HTTPS

```bash
# From another machine
curl https://192.168.1.50

# Check certificate
openssl s_client -connect 192.168.1.50:443 -showcerts
```

## Troubleshooting

### "Obtaining certificate: error getting certificate from certificate authority"

**Cause**: Can't reach ACME endpoint

**Fix**:
```bash
# Test CA connectivity
curl https://192.168.1.100:9000/acme/acme/directory

# Check Caddy can reach CA
sudo journalctl -u caddy -n 50 | grep acme
```

### "Remote error: tls: unknown certificate authority"

**Cause**: Caddy doesn't trust your CA

**Fix**: Ensure `acme_ca_root` points to correct file:
```bash
ls -l /etc/ssl/auto-ssl/root_ca.crt
# File should exist and be readable
```

### Certificate Not Renewing

**Diagnosis**:
```bash
# Caddy renews automatically at 2/3 of certificate lifetime
# For 7-day certs, that's ~5 days

# Check Caddy logs for renewal attempts
sudo journalctl -u caddy | grep -i renew
```

**Manual renewal**:
```bash
# Reload Caddy (triggers cert check)
sudo systemctl reload caddy
```

## Advanced Configuration

### Custom TLS Settings

```
192.168.1.50 {
    tls {
        protocols tls1.2 tls1.3
        ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
    }
    reverse_proxy localhost:8080
}
```

### Automatic HTTPS Redirect

```
192.168.1.50 {
    # Automatically redirects HTTP -> HTTPS
    redir https://{host}{uri} permanent
}
```

### Environment-Specific Config

```
{
    # Development
    acme_ca https://192.168.1.100:9000/acme/acme/directory
    acme_ca_root /etc/ssl/auto-ssl/root_ca.crt
    
    # Production: use staging first!
    # acme_ca https://ca.prod.internal:9000/acme/acme/directory
    # acme_ca_root /etc/ssl/auto-ssl/prod-root-ca.crt
}
```

## Best Practices

1. **Use ACME with Caddy** instead of manual enrollment
2. **Set email** for notifications
3. **Monitor Caddy logs** for cert issues
4. **Test with curl** before browser
5. **Keep Caddy updated** for security fixes

## Performance

Caddy's HTTPS overhead is minimal:
- ~1-2ms additional latency
- Minimal CPU usage
- HTTP/2 support out of the box

## Next Steps

- [Server Enrollment](server-enrollment.md) - Manual cert management
- [nginx Integration](nginx-integration.md) - For nginx users
- [Troubleshooting](troubleshooting.md) - Common issues
