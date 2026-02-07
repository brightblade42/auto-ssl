# nginx Integration Guide

Integrate auto-ssl certificates with nginx for HTTPS.

## Installation

### RHEL/Rocky/CentOS

```bash
sudo dnf install nginx
```

### Ubuntu/Debian

```bash
sudo apt install nginx
```

## Enroll Server

First, get certificates:

```bash
sudo auto-ssl server enroll \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123
```

Certificates will be at:
- `/etc/ssl/auto-ssl/server.crt`
- `/etc/ssl/auto-ssl/server.key`

## Configuration

### Basic HTTPS Server

Edit `/etc/nginx/conf.d/myapp.conf`:

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name 192.168.1.50;
    
    # SSL certificates
    ssl_certificate     /etc/ssl/auto-ssl/server.crt;
    ssl_certificate_key /etc/ssl/auto-ssl/server.key;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    
    # Application
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name 192.168.1.50;
    return 301 https://$server_name$request_uri;
}
```

### Static Site

```nginx
server {
    listen 443 ssl http2;
    server_name mysite.internal;
    
    ssl_certificate     /etc/ssl/auto-ssl/server.crt;
    ssl_certificate_key /etc/ssl/auto-ssl/server.key;
    
    root /var/www/html;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
}
```

### Multiple Sites

```nginx
# Site 1
server {
    listen 443 ssl http2;
    server_name app1.internal;
    
    ssl_certificate     /etc/ssl/auto-ssl/server.crt;
    ssl_certificate_key /etc/ssl/auto-ssl/server.key;
    
    location / {
        proxy_pass http://localhost:8080;
    }
}

# Site 2
server {
    listen 443 ssl http2;
    server_name app2.internal;
    
    ssl_certificate     /etc/ssl/auto-ssl/server.crt;
    ssl_certificate_key /etc/ssl/auto-ssl/server.key;
    
    location / {
        proxy_pass http://localhost:3000;
    }
}
```

## Start nginx

```bash
# Test configuration
sudo nginx -t

# Enable and start
sudo systemctl enable nginx
sudo systemctl start nginx

# Check status
sudo systemctl status nginx
```

## Certificate Renewal

### Configure Auto-Reload

Edit `/etc/systemd/system/auto-ssl-renew.service`:

```ini
[Unit]
Description=Renew auto-ssl certificate
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/step ca renew --force /etc/ssl/auto-ssl/server.crt /etc/ssl/auto-ssl/server.key
ExecStartPost=/usr/bin/systemctl reload nginx
```

Reload systemd:
```bash
sudo systemctl daemon-reload
```

Now nginx automatically reloads after renewal.

### Manual Renewal

```bash
# Renew and reload
sudo auto-ssl server renew --force --exec "systemctl reload nginx"
```

## Verify HTTPS

```bash
# Test from another machine
curl https://192.168.1.50

# Check certificate
echo | openssl s_client -connect 192.168.1.50:443 -servername 192.168.1.50 2>/dev/null | openssl x509 -noout -text
```

## Troubleshooting

### "SSL: error:0200100D:system library"

**Cause**: Permission issue with certificate files

**Fix**:
```bash
sudo chmod 644 /etc/ssl/auto-ssl/server.crt
sudo chmod 600 /etc/ssl/auto-ssl/server.key
sudo chown root:root /etc/ssl/auto-ssl/*
```

### nginx Won't Start

**Diagnosis**:
```bash
# Check nginx error log
sudo tail /var/log/nginx/error.log

# Common issues:
# - Certificate file not found
# - Invalid certificate
# - Port already in use
```

### Certificate Not Reloading

**Symptom**: Old certificate still served after renewal

**Cause**: nginx not reloaded

**Fix**: Add reload to renewal service (see above)

## Security Best Practices

### Strong SSL Configuration

```nginx
# /etc/nginx/conf.d/ssl-params.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers off;

# HSTS
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# OCSP Stapling (optional)
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/ssl/auto-ssl/server.crt;
```

Include in your server blocks:
```nginx
server {
    listen 443 ssl http2;
    include /etc/nginx/conf.d/ssl-params.conf;
    # ...
}
```

### Disable Weak Protocols

```nginx
ssl_protocols TLSv1.2 TLSv1.3;  # No TLSv1.0 or TLSv1.1
```

## Performance Tuning

### SSL Session Cache

```nginx
http {
    # SSL session cache
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Enable SSL session tickets
    ssl_session_tickets on;
}
```

### HTTP/2

```nginx
listen 443 ssl http2;  # Enable HTTP/2
```

## Monitoring

### Check Certificate Expiration

```bash
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -enddate
```

### nginx Status

```nginx
server {
    listen 127.0.0.1:8080;
    location /nginx_status {
        stub_status;
        access_log off;
    }
}
```

Query: `curl http://127.0.0.1:8080/nginx_status`

## Next Steps

- [Caddy Integration](caddy-integration.md) - Easier alternative
- [Server Enrollment](server-enrollment.md) - Certificate management
- [Troubleshooting](troubleshooting.md) - Common issues
