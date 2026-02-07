# Client Trust Guide

How to trust your internal CA on client machines (laptops, desktops, workstations).

## Why Trust the CA?

After enrolling servers with certificates, client machines (browsers, CLI tools) need to trust your internal CA. Otherwise, you'll see "certificate not trusted" warnings.

## One-Time Setup Per Client

This is a **one-time operation** per client machine. Once your CA root certificate is trusted, all certificates issued by that CA are automatically trusted.

## Automatic Installation

### Linux/macOS

```bash
# Download and run auto-ssl
curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash

# Trust the CA
sudo auto-ssl client trust \
  --ca-url https://192.168.1.100:9000 \
  --fingerprint abc123def456...
```

This:
1. Downloads the root CA certificate
2. Verifies the fingerprint (prevents MITM)
3. Installs it into the system trust store
4. Updates the trust database

### Windows

auto-ssl doesn't have native Windows support, but you can install manually:

1. **Download the root CA**:
   - Visit `https://192.168.1.100:9000/roots.pem` in a browser
   - Save as `internal-ca.crt`

2. **Install the certificate**:
   - Right-click `internal-ca.crt` → Install Certificate
   - Choose "Local Machine"
   - Select "Place all certificates in the following store"
   - Click "Browse" → "Trusted Root Certification Authorities"
   - Click "Next" → "Finish"

3. **Restart your browser**

Or via PowerShell (Admin):
```powershell
# Download certificate
Invoke-WebRequest -Uri https://192.168.1.100:9000/roots.pem -OutFile internal-ca.crt -SkipCertificateCheck

# Import
Import-Certificate -FilePath internal-ca.crt -CertStoreLocation Cert:\LocalMachine\Root
```

## Manual Installation

### macOS

```bash
# Download root CA
curl -k https://192.168.1.100:9000/roots.pem -o internal-ca.crt

# Verify fingerprint
openssl x509 -in internal-ca.crt -noout -fingerprint -sha256

# Install to system keychain
sudo security add-trusted-cert -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  internal-ca.crt

# Verify
security find-certificate -a -c "Internal CA" /Library/Keychains/System.keychain
```

### RHEL/Rocky/CentOS/Fedora

```bash
# Download root CA
curl -k https://192.168.1.100:9000/roots.pem -o internal-ca.crt

# Install
sudo cp internal-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# Verify
trust list | grep "Internal CA"
```

### Ubuntu/Debian

```bash
# Download root CA
curl -k https://192.168.1.100:9000/roots.pem -o internal-ca.crt

# Install
sudo cp internal-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Verify
ls /etc/ssl/certs/ | grep internal-ca
```

## Verification

### Test with curl

```bash
# Should work WITHOUT -k flag
curl https://192.168.1.50

# If it works, CA is trusted
# If you see certificate errors, CA is not trusted
```

### Test with Browser

1. Navigate to `https://192.168.1.50`
2. Check the padlock icon
3. View certificate details
4. Verify issuer is your CA

### Check Trust Status

```bash
# Using auto-ssl
auto-ssl client status

# Manual checks:
# macOS
security verify-cert -c internal-ca.crt

# Linux
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt your-server.crt
```

## Browser-Specific Configuration

### Firefox

Firefox uses its own certificate store (doesn't use system store by default).

**Option 1: Enable system certificates** (Recommended)
1. Open Firefox
2. Go to `about:config`
3. Search for `security.enterprise_roots.enabled`
4. Set to `true`
5. Restart Firefox

**Option 2: Import manually**
1. Open Firefox Settings
2. Search for "certificates"
3. View Certificates → Authorities
4. Import → Select `internal-ca.crt`
5. Check "Trust this CA to identify websites"
6. OK

### Chrome/Edge

Use system certificate store (automatic).

### Safari

Use system keychain (automatic on macOS).

## Docker Containers

Containers need the CA certificate:

### Method 1: Mount Certificate

```bash
docker run -v /etc/ssl/certs:/etc/ssl/certs:ro myapp
```

### Method 2: Add to Image

```dockerfile
FROM ubuntu:22.04

# Copy root CA
COPY internal-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Your application
COPY . /app
CMD ["/app/start.sh"]
```

### Method 3: At Runtime

```bash
docker run myapp sh -c '
  curl -k https://ca.internal:9000/roots.pem > /usr/local/share/ca-certificates/internal-ca.crt &&
  update-ca-certificates &&
  /app/start.sh
'
```

## Programming Language Support

### Python

```python
import requests

# Should work automatically after system trust
response = requests.get('https://192.168.1.50')

# If not, specify CA bundle
response = requests.get('https://192.168.1.50',
    verify='/etc/ssl/certs/ca-certificates.crt')
```

### Node.js

```javascript
const https = require('https');

// Should work automatically
https.get('https://192.168.1.50', (res) => {
  console.log('Status:', res.statusCode);
});

// If not, set environment variable:
// NODE_EXTRA_CA_CERTS=/path/to/internal-ca.crt node app.js
```

### Go

```go
import (
    "crypto/x509"
    "net/http"
)

// Should work automatically with system trust

// If not, load CA manually
caCert, _ := os.ReadFile("/etc/ssl/certs/ca-certificates.crt")
caCertPool := x509.NewCertPool()
caCertPool.AppendCertsFromPEM(caCert)

client := &http.Client{
    Transport: &http.Transport{
        TLSClientConfig: &tls.Config{
            RootCAs: caCertPool,
        },
    },
}
```

### cURL

```bash
# Should work automatically
curl https://192.168.1.50

# If not, specify CA
curl --cacert /etc/ssl/certs/ca-certificates.crt https://192.168.1.50
```

## Mobile Devices

### iOS

1. Email the `internal-ca.crt` file to yourself
2. Open on iPhone/iPad
3. Settings → Profile Downloaded → Install
4. Enter passcode
5. Settings → General → About → Certificate Trust Settings
6. Enable full trust for the CA

### Android

1. Download `internal-ca.crt` to device
2. Settings → Security → Encryption & credentials
3. Install a certificate → CA certificate
4. Select the file
5. Name it (e.g., "Internal CA")

## Troubleshooting

### Certificate Still Not Trusted

```bash
# Check if CA cert is in trust store
# macOS
security find-certificate -a -c "Internal CA" /Library/Keychains/System.keychain

# Linux (RHEL)
trust list | grep -i internal

# Linux (Debian)
ls -la /etc/ssl/certs/ | grep internal
```

### Wrong Fingerprint Error

The fingerprint doesn't match. This could indicate:
- Typo in fingerprint
- Wrong CA URL
- MITM attack (rare internally)

Get the correct fingerprint:
```bash
# On CA server
step certificate fingerprint /opt/step-ca/certs/root_ca.crt

# Or
curl -k https://CA_IP:9000/roots.pem | step certificate fingerprint
```

### Browser Still Shows Warning

1. **Clear browser cache** and restart
2. **Check certificate chain**: View the certificate, ensure it's issued by your CA
3. **Firefox**: Ensure `security.enterprise_roots.enabled` is true
4. **Check date/time**: Ensure client clock is correct

### Container Applications Fail

```bash
# Check if CA is in container
docker exec container cat /etc/ssl/certs/ca-certificates.crt | grep -A 20 "Internal CA"

# If missing, rebuild image with CA cert
```

## Automation

### Ansible Playbook

```yaml
---
- name: Trust internal CA
  hosts: workstations
  become: yes
  tasks:
    - name: Download auto-ssl installer
      get_url:
        url: https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh
        dest: /tmp/install-auto-ssl.sh
        mode: '0755'
    
    - name: Install auto-ssl
      shell: /tmp/install-auto-ssl.sh
    
    - name: Trust CA
      command: >
        auto-ssl client trust
        --ca-url https://192.168.1.100:9000
        --fingerprint {{ ca_fingerprint }}
```

### Puppet

```puppet
exec { 'trust-internal-ca':
  command => '/usr/bin/auto-ssl client trust --ca-url https://192.168.1.100:9000 --fingerprint abc123',
  unless  => '/usr/bin/test -f /etc/pki/ca-trust/source/anchors/auto-ssl-root-ca.crt',
  require => Package['auto-ssl'],
}
```

## Best Practices

1. **Verify Fingerprints**: Always verify before trusting
2. **Document the Process**: Keep instructions for new employees
3. **Automate When Possible**: Use configuration management
4. **Test After Installation**: Verify with curl/browser
5. **Keep CA Certificate Accessible**: Store in a shared location (not the CA server)

## Next Steps

- **[Server Enrollment](server-enrollment.md)** — Enroll servers
- **[Troubleshooting](troubleshooting.md)** — Common issues
- **[PKI Fundamentals](../concepts/pki-fundamentals.md)** — Understanding certificates
