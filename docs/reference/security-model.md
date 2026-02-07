# Security Model

Security considerations and best practices for auto-ssl.

## Security Overview

auto-ssl implements a Private CA (Certificate Authority) for internal networks. Security depends on:
1. **Physical security** of CA server
2. **Network isolation** (internal network only)
3. **Access control** (root/sudo required for operations)
4. **Cryptographic strength** (RSA 2048+, ECDSA P-256+)
5. **Short certificate lifetimes** (7 days default)

## Threat Model

### In Scope

**Threats Mitigated**:
- ✅ Man-in-the-middle attacks (TLS encryption)
- ✅ Certificate impersonation (private key protection)
- ✅ Compromised certificates (short lifetimes)
- ✅ Unauthorized certificate issuance (provisioner auth)
- ✅ Certificate forgery (cryptographic signatures)

### Out of Scope

**Not Protected Against**:
- ❌ Compromised CA server with root access
- ❌ Physical access to servers
- ❌ Malicious insiders with root privileges
- ❌ DDoS attacks on CA
- ❌ Advanced persistent threats (APTs)

### Assumptions

1. **Network Trust**: Internal network is reasonably secure
2. **Physical Security**: Servers are in secure datacenters
3. **Access Control**: Only authorized personnel have root access
4. **Trust Decisions**: Users verify CA fingerprint on first use

## Cryptographic Primitives

### Algorithms

**Root CA**: RSA 4096-bit or ECDSA P-384
**Intermediate CA**: RSA 2048-bit or ECDSA P-256  
**Server Certificates**: RSA 2048-bit or ECDSA P-256

**Supported TLS**:
- TLS 1.2, TLS 1.3
- Modern cipher suites only
- No export-grade or weak ciphers

### Key Storage

**CA Private Keys**:
- Location: `/opt/step-ca/secrets/`
- Permissions: `600` (root only)
- Encryption: Encrypted with password
- Protection: Filesystem permissions + systemd hardening

**Server Private Keys**:
- Location: `/etc/ssl/auto-ssl/server.key`
- Permissions: `600` (root only)
- Generated on server (never transmitted)
- Used only by web server process

### Random Number Generation

- Source: `/dev/urandom` (Linux kernel CSPRNG)
- Usage: Private key generation, nonces, passwords
- Quality: Cryptographically secure

## Access Control

### CA Server

**Root Access Required**:
- CA initialization (`auto-ssl ca init`)
- Backup and restore
- Service management
- Password changes

**Provisioner Password Required**:
- Certificate issuance
- Server enrollment

**No Authentication Required**:
- Viewing certificates (public information)
- CA health endpoint (`/health`)
- Downloading root CA (public certificate)

### Application Servers

**Root Access Required**:
- Server enrollment
- Certificate renewal service setup
- Web server configuration

**No Authentication Required**:
- Web server reading certificate files
- Certificate renewal (uses existing cert to authenticate)

### Clients

**Root Access Required**:
- Installing root CA to system trust store

**No Authentication Required**:
- Using HTTPS (transparent to users)

## Authentication Methods

### Provisioner Authentication

**Password-based** (JWK provisioner):
- User provides password
- auto-ssl sends to CA
- CA validates and issues certificate

**Certificate-based** (for renewal):
- Server presents existing valid certificate
- CA verifies signature and expiration
- Issues new certificate

**ACME** (optional):
- Uses ACME protocol challenges
- Requires DNS or HTTP validation
- Best for automated systems (like Caddy)

## Network Security

### TLS Configuration

**CA Server** (step-ca):
```
Port: 9000/TCP
Protocol: HTTPS only
TLS: 1.2, 1.3
Ciphers: Modern only
Certificate: Self-signed (bootstrap exception)
```

**Application Servers**:
```
Port: 443/TCP
Protocol: HTTPS
TLS: 1.2, 1.3
Ciphers: Configured by web server
Certificate: Issued by internal CA
```

### Network Isolation

**Recommended**:
- CA on management VLAN
- Firewall rules limiting CA access
- No direct internet access to CA
- Monitor CA traffic

**Minimum**:
- CA port 9000 only accessible internally

## Certificate Lifecycle Security

### Issuance

**Controls**:
- Provisioner password required
- SANs validated against policies
- Certificate duration enforced (max 30 days)
- Serial numbers tracked in database

**Logging**:
- All issuance logged by step-ca
- Logs include: timestamp, SANs, provisioner, IP

### Renewal

**Controls**:
- Uses existing certificate to authenticate
- Requires certificate not expired >5% of lifetime
- Verifies certificate not revoked
- Issues same SANs only

**Automation**:
- Renewal 2/3 through validity period
- systemd timer with random delay
- Automatic retry on failure

### Revocation

**Methods**:
- `auto-ssl server revoke` - immediate revocation
- Certificate expires - automatic after 7 days
- Database entry - tracked by CA

**Checking**:
- Step-ca maintains revocation database
- Online checking (not OCSP by default)
- Short lifetimes reduce revocation importance

## Backup Security

### Encryption

**Backup Contents**:
- Root CA private key
- Intermediate CA private key
- Certificate database
- Configuration files
- Provisioner keys

**Protection**:
- AES-256-CBC encryption (via OpenSSL)
- PBKDF2 key derivation
- Salt and IV generated per backup
- Password/passphrase required

**Storage**:
- Backups should be encrypted at rest
- Store passphrases separately from backups
- Multiple secure locations recommended

### Access Control

**Backup Creation**: Root access required
**Backup Restoration**: Root access + passphrase required
**Backup Storage**: Secure location, limited access

## Common Attack Scenarios

### Scenario 1: Stolen Provisioner Password

**Impact**: Attacker can issue certificates for any name

**Mitigations**:
- Short certificate lifetimes (7 days)
- Monitoring certificate issuance
- Regular password rotation
- Limit provisioner scope if possible

**Response**:
1. Rotate provisioner password immediately
2. Review CA logs for unauthorized issuance
3. Revoke suspicious certificates
4. Update password on all enrolled servers

### Scenario 2: Compromised Server Private Key

**Impact**: Attacker can impersonate that server

**Mitigations**:
- File permissions (600)
- Short certificate lifetimes
- Certificate revocation

**Response**:
1. Revoke certificate immediately
2. Re-enroll server with new key
3. Investigate how key was compromised

### Scenario 3: Compromised CA Server

**Impact**: Complete PKI compromise

**Mitigations**:
- Physical security
- Access controls
- Regular security updates
- Monitoring

**Response**:
1. Take CA offline immediately
2. Investigate extent of compromise
3. If root key compromised:
   - Create new CA
   - Re-enroll all servers
   - Re-trust on all clients
4. If only intermediate compromised:
   - Create new intermediate
   - Existing root CA still valid

### Scenario 4: Man-in-the-Middle on Enrollment

**Impact**: Attacker obtains provisioner password or redirects to rogue CA

**Mitigations**:
- Fingerprint verification (prevents rogue CA)
- Secure password transmission
- Internal network only

**Response**:
1. If password stolen: Rotate immediately
2. If enrolled to rogue CA: Re-enroll with correct fingerprint

## Best Practices

### For CA Server

1. ✅ **Isolate physically and logically**
2. ✅ **Regular backups** (automated, encrypted)
3. ✅ **Monitor CA logs** for unusual activity
4. ✅ **Strong provisioner passwords** (16+ characters)
5. ✅ **Restrict network access** (firewall)
6. ✅ **Keep software updated**
7. ✅ **Document procedures**
8. ✅ **Test disaster recovery** annually

### For Application Servers

1. ✅ **Protect private keys** (600 permissions)
2. ✅ **Monitor certificate expiration**
3. ✅ **Verify renewal timer** is active
4. ✅ **Use strong TLS configuration**
5. ✅ **Keep web server updated**

### For Clients

1. ✅ **Verify CA fingerprint** on first trust
2. ✅ **Secure root CA distribution**
3. ✅ **Document trusted CAs**

### For Administrators

1. ✅ **Use password managers** for provisioner passwords
2. ✅ **Separate CA and app server roles**
3. ✅ **Audit access to CA server**
4. ✅ **Regular security reviews**
5. ✅ **Incident response plan**

## Compliance Considerations

### Certificate Lifetimes

**Apple/Google Requirements** (for public CAs):
- Maximum 398 days (13 months)

**Our Defaults**:
- 7 days (far more secure)
- Configurable up to 30 days

### Logging

**What's Logged**:
- Certificate issuance
- Revocations
- Authentication failures
- Service starts/stops

**Where**:
- systemd journal: `journalctl -u step-ca`
- Optional: `/var/log/step-ca/`

**Retention**: Configure per organizational requirements

### Auditing

**Audit Points**:
- Who has root on CA server
- Provisioner password changes
- Certificate issuance patterns
- Backup verification
- Access to backup storage

## Incident Response

### Detection

**Monitor for**:
- Unexpected certificate issuance
- Failed authentication attempts
- CA service disruptions
- Certificate near expiration
- Backup failures

### Response Plan

1. **Assess**: Determine scope and impact
2. **Contain**: Stop unauthorized activity
3. **Eradicate**: Remove attacker access
4. **Recover**: Restore services
5. **Learn**: Update procedures

### Contacts

Document:
- CA administrator contact
- Security team escalation
- Backup restoration procedure
- Vendor support contacts (Smallstep)

## Security Updates

### Updating step-ca

```bash
# Check current version
step-ca version

# Download new version
# (check Smallstep releases)

# Stop CA
sudo systemctl stop step-ca

# Replace binary
sudo mv step-ca /usr/bin/step-ca

# Start CA
sudo systemctl start step-ca
```

### Updating auto-ssl

```bash
# Download latest
git pull origin main

# Reinstall
sudo make install
```

### Security Advisories

Monitor:
- Smallstep security advisories
- auto-ssl GitHub releases
- CVE databases for dependencies

## Further Reading

- [NIST PKI Guide](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final)
- [Smallstep Security Model](https://smallstep.com/docs/step-ca/certificate-authority-server-production)
- [TLS Best Practices](https://wiki.mozilla.org/Security/Server_Side_TLS)

## See Also

- [Architecture](architecture.md)
- [PKI Fundamentals](../concepts/pki-fundamentals.md)
- [Backup & Restore](../guides/backup-restore.md)
- [Troubleshooting](../guides/troubleshooting.md)
