# Backup & Restore Guide

Protect your Certificate Authority with regular backups.

## Why Backup?

Your CA contains:
- **Root CA private key** - Cannot be regenerated
- **Intermediate CA private key** - Required for issuing certs
- **Certificate database** - Record of all issued certs
- **Configuration** - Provisioners, policies, etc.

**If lost**: You must recreate the CA and re-enroll all servers and clients.

## What to Backup

### Critical (Must Backup)
- `/opt/step-ca/` - Entire CA directory
- `/etc/auto-ssl/` - Configuration and passwords

### Optional but Recommended
- Server inventory (`/etc/auto-ssl/servers.yaml`)
- Documentation of enrolled servers

## Backup Methods

### Method 1: Using auto-ssl (Recommended)

```bash
# Create encrypted backup
sudo auto-ssl ca backup --output /backup/ca-backup.enc
```

You'll be prompted for an encryption passphrase. **Store this securely!**

### Method 2: Manual Backup

```bash
# Stop CA for consistent backup
sudo systemctl stop step-ca

# Create archive
sudo tar -czf ca-backup-$(date +%Y%m%d).tar.gz \
  /opt/step-ca \
  /etc/auto-ssl

# Encrypt (recommended)
gpg --symmetric --cipher-algo AES256 ca-backup-*.tar.gz

# Restart CA
sudo systemctl start step-ca
```

## Automatic Backups

### Schedule Backups

```bash
sudo auto-ssl ca backup-schedule \
  --enable \
  --schedule weekly \
  --retention 4 \
  --output /var/backups/auto-ssl
```

This creates:
- Weekly backups at 2 AM Sunday
- Keeps 4 most recent backups
- Automatic cleanup of old backups

### Backup Destinations

#### Local Storage

```bash
sudo auto-ssl ca backup-schedule \
  --enable \
  --schedule daily \
  --output /mnt/nas/ca-backups
```

#### Remote via rsync

```bash
sudo auto-ssl ca backup-schedule \
  --enable \
  --schedule weekly \
  --dest-type rsync \
  --rsync-target backup-server:/backups/ca/
```

#### S3/Wasabi

```bash
# Configure AWS CLI first
aws configure

# Enable S3 backups
sudo auto-ssl ca backup-schedule \
  --enable \
  --schedule weekly \
  --dest-type s3 \
  --s3-bucket my-ca-backups \
  --s3-endpoint https://s3.wasabisys.com
```

## Restore Procedures

### Restore from auto-ssl Backup

```bash
# Stop existing CA (if running)
sudo systemctl stop step-ca

# Restore
sudo auto-ssl ca restore --input /backup/ca-backup.enc
```

Enter the decryption passphrase when prompted.

### Restore to Different IP

If your CA server IP changed:

```bash
sudo auto-ssl ca restore \
  --input /backup/ca-backup.enc \
  --new-address 192.168.1.200:9000
```

Then update all enrolled servers:
```bash
auto-ssl remote update-ca-url --new-url https://192.168.1.200:9000
```

### Manual Restore

```bash
# Decrypt
gpg --decrypt ca-backup-20240115.tar.gz.gpg > ca-backup.tar.gz

# Stop CA
sudo systemctl stop step-ca

# Extract
sudo tar -xzf ca-backup.tar.gz -C /

# Start CA
sudo systemctl start step-ca
```

## Backup Verification

### Test Backup Integrity

```bash
# Try to decrypt/extract without actually restoring
sudo auto-ssl ca backup --output test-backup.enc
sudo auto-ssl ca restore --input test-backup.enc --dry-run
```

### Periodic Restore Tests

**Best practice**: Test restore annually on a separate VM to ensure backups work.

## Disaster Recovery

### Complete CA Loss

If CA is completely lost and you have no backup:

1. **Create new CA**
   ```bash
   sudo auto-ssl ca init --name "Recovery CA"
   ```

2. **Re-enroll all servers**
   ```bash
   for server in $(cat servers.txt); do
     auto-ssl remote enroll --host $server --user admin
   done
   ```

3. **Re-trust on all clients**
   ```bash
   # Distribute new root CA fingerprint
   # Each client must run:
   sudo auto-ssl client trust --ca-url https://NEW_CA_IP:9000 --fingerprint NEW_FP
   ```

### Partial Data Loss

If only certain files are lost:

**Lost: Root CA certificate only**
- Can be recreated from existing CA (it's public)
- `step certificate root /opt/step-ca/certs/root_ca.crt`

**Lost: Configuration only**
- Recreate `/etc/auto-ssl/config.yaml` manually
- Check `/opt/step-ca/config/ca.json` for CA URL

**Lost: Private keys**
- **Cannot recover** - Must create new CA

## Security Considerations

### Backup Encryption

**Always encrypt backups** - they contain private keys:

```bash
# auto-ssl encrypts by default
sudo auto-ssl ca backup --output ca.enc

# Or use gpg
tar -czf ca.tar.gz /opt/step-ca /etc/auto-ssl
gpg --symmetric --cipher-algo AES256 ca.tar.gz
```

### Passphrase Management

Store backup passphrases:
- Password manager (1Password, BitWarden)
- Physical safe
- Multiple secure locations
- **Not** on the CA server itself

### Access Control

```bash
# Secure backup files
sudo chmod 600 /var/backups/auto-ssl/*.enc
sudo chown root:root /var/backups/auto-ssl/*.enc

# Limit access to backup directory
sudo chmod 700 /var/backups/auto-ssl
```

### Backup Retention

**Recommended retention**:
- Daily backups: Keep 7 days
- Weekly backups: Keep 4 weeks
- Monthly backups: Keep 12 months
- Yearly backups: Keep indefinitely

## Monitoring

### Check Backup Status

```bash
auto-ssl ca backup-schedule
```

Shows:
- Backup schedule
- Last backup time
- Next backup time
- Number of backups stored

### Backup Alerts

Add to monitoring:
```bash
# Check if backup succeeded
systemctl status auto-ssl-backup.service

# Alert if last backup > 8 days old
LAST_BACKUP=$(ls -t /var/backups/auto-ssl/*.enc | head -1)
AGE=$(( ($(date +%s) - $(stat -c %Y "$LAST_BACKUP")) / 86400 ))
if [ $AGE -gt 8 ]; then
  echo "WARNING: Last backup is $AGE days old"
fi
```

## Best Practices

1. **Automate backups** - Don't rely on manual backups
2. **Test restores** - Verify backups work before disaster strikes
3. **Multiple locations** - Store backups off-site
4. **Encrypt everything** - Backups contain sensitive keys
5. **Document procedure** - Keep restore instructions accessible
6. **Monitor backups** - Alert on failures
7. **Rotate passphrases** - Change periodically

## Next Steps

- [CA Migration](ca-migration.md) - Move CA to new server
- [CA Setup](ca-setup.md) - Initial CA configuration
- [Troubleshooting](troubleshooting.md) - Common issues
