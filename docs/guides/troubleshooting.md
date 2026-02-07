# Troubleshooting Guide

Common issues and solutions for auto-ssl.

## CA Server Issues

### CA Won't Start

**Symptoms**: `systemctl start step-ca` fails

**Diagnosis**:
```bash
# Check logs
sudo journalctl -u step-ca -n 50 --no-pager

# Common errors to look for:
# - "address already in use"
# - "permission denied"
# - "config file error"
```

**Solutions**:

**Port already in use**:
```bash
# Find what's using port 9000
sudo netstat -tlnp | grep 9000
# Kill the process or change CA port
```

**Permission issues**:
```bash
# Fix ownership
sudo chown -R root:root /opt/step-ca
sudo chmod 700 /opt/step-ca/secrets
```

**Config errors**:
```bash
# Validate config
sudo step-ca /opt/step-ca/config/ca.json --dry-run
```

### CA Not Reachable from Servers

**Symptoms**: `curl: (7) Failed to connect`

**Diagnosis**:
```bash
# From the CA server
sudo netstat -tlnp | grep 9000  # Should show step-ca listening

# From a client
curl -k https://CA_IP:9000/health  # Should return {"status":"ok"}
```

**Solutions**:

**Firewall blocking**:
```bash
# RHEL/CentOS
sudo firewall-cmd --list-ports  # Check if 9000/tcp is listed
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --reload

# Ubuntu
sudo ufw status
sudo ufw allow 9000/tcp
```

**Wrong IP address**:
```bash
# Check CA config
grep address /opt/step-ca/config/ca.json
# Should match your CA server's IP
```

## Enrollment Issues

### "fingerprint mismatch" Error

**Cause**: The root CA fingerprint provided doesn't match the actual CA

**Solution**:
```bash
# Get correct fingerprint from CA server
step certificate fingerprint /opt/step-ca/certs/root_ca.crt

# Or
curl -k https://CA_IP:9000/roots.pem | step certificate fingerprint
```

### "provisioner password incorrect"

**Solutions**:

**Reset provisioner password** (CA server):
```bash
export STEPPATH=/opt/step-ca

# Remove old provisioner
step ca provisioner remove admin

# Add new one
step ca provisioner add admin --create

# Restart CA
sudo systemctl restart step-ca
```

### Certificate Request Fails

**Symptoms**: `step ca certificate` returns error

**Common causes**:
- CA not running: `systemctl status step-ca`
- Network issues: `ping CA_IP`
- Wrong provisioner name: Check `step ca provisioner list`
- Step CLI not bootstrapped: Run `step ca bootstrap`

## Certificate Issues

### Certificate Expired

**Quick fix**:
```bash
# Force immediate renewal
sudo auto-ssl server renew --force
```

**Why it happened**:
- Auto-renewal timer not running
- CA was unreachable during renewal
- System clock wrong

**Prevent recurrence**:
```bash
# Check renewal timer
systemctl status auto-ssl-renew.timer
systemctl list-timers auto-ssl-renew.timer

# Check timer logs
sudo journalctl -u auto-ssl-renew.service
```

### "Certificate not trusted" in Browser

**Cause**: Client doesn't trust your CA

**Solution**:
```bash
# On the client machine
sudo auto-ssl client trust \
  --ca-url https://CA_IP:9000 \
  --fingerprint abc123
```

For Firefox specifically:
1. Go to `about:config`
2. Set `security.enterprise_roots.enabled` to `true`
3. Restart Firefox

### Renewal Fails

**Diagnosis**:
```bash
# Check renewal logs
sudo journalctl -u auto-ssl-renew.service -n 50

# Test renewal manually
sudo systemctl start auto-ssl-renew.service
```

**Common issues**:

**CA unreachable**:
```bash
# Test from server
curl -k https://CA_IP:9000/health
```

**Certificate already expired**:
```bash
# Use --force
sudo auto-ssl server renew --force
```

**Permission issues**:
```bash
# Check ownership
ls -l /etc/ssl/auto-ssl/
# Should be owned by root
sudo chown root:root /etc/ssl/auto-ssl/*
sudo chmod 644 /etc/ssl/auto-ssl/server.crt
sudo chmod 600 /etc/ssl/auto-ssl/server.key
```

## Remote Enrollment Issues

### SSH Connection Fails

**Diagnosis**:
```bash
# Test SSH manually
ssh -v user@target-host

# Common issues:
# - Wrong username
# - No SSH key
# - SSH key not authorized
# - SSH not running on target
```

**Solutions**:

**Set up SSH key**:
```bash
# On CA server
ssh-keygen -t ed25519

# Copy to target
ssh-copy-id user@target-host
```

### Remote enrollment completes but server unreachable

**Cause**: auto-ssl was installed but web server not configured

**Solution**: Configure your web server to use the certificates (see integration guides)

## Network Issues

### "Connection refused"

**Diagnosis**:
```bash
# Check if service is running
systemctl status step-ca  # or nginx, caddy, etc.

# Check if port is listening
sudo netstat -tlnp | grep PORT
```

### "Connection timed out"

**Diagnosis**:
```bash
# Test connectivity
ping TARGET_IP

# Check firewall rules
sudo iptables -L -n | grep PORT
sudo firewall-cmd --list-all
```

## Performance Issues

### CA Slow to Issue Certificates

**Causes**:
- CA server under-resourced
- Many concurrent requests

**Solutions**:
- Increase CA server resources
- Use ACME instead of step CLI (better for high volume)
- Rate limit certificate requests

### Renewal Timer Using Too Much CPU

**Diagnosis**:
```bash
# Check timer frequency
systemctl list-timers auto-ssl-renew.timer

# Check service resource usage
systemctl status auto-ssl-renew.service
```

**Solution**: Adjust renewal schedule in `/etc/systemd/system/auto-ssl-renew.timer`

## Backup/Restore Issues

### Backup Fails

**Common causes**:
- Not enough disk space
- Permission issues
- CA not stopped cleanly

**Solutions**:
```bash
# Check disk space
df -h

# Check permissions
ls -ld /var/backups/auto-ssl

# Retry backup
sudo auto-ssl ca backup --output /backup/ca-backup.enc
```

### Restore Fails

**Diagnosis**:
```bash
# Verify backup file
file /backup/ca-backup.enc  # Should say "data" (encrypted)

# Check passphrase
# Wrong passphrase will fail decryption
```

**Solution**: Ensure you have the correct passphrase from when backup was created

## Getting Help

### Collect Diagnostic Information

```bash
# System info
auto-ssl info

# CA status (if CA server)
auto-ssl ca status

# Server status (if enrolled server)
auto-ssl server status

# Logs
sudo journalctl -u step-ca -n 100 > ca-logs.txt
sudo journalctl -u auto-ssl-renew.service -n 100 > renewal-logs.txt

# Network
ip addr show
ss -tlnp | grep -E '(9000|443|80)'
```

### Report Issues

Include in bug reports:
- Output of `auto-ssl info`
- Relevant log excerpts
- Steps to reproduce
- OS and version
- step-ca and step CLI versions

### Community Resources

- GitHub Issues: https://github.com/Brightblade42/auto-ssl/issues
- Smallstep Docs: https://smallstep.com/docs/step-ca
- Discord/Slack: (if available)

## Known Issues

### Issue: Date parsing on BSD systems

**Symptoms**: Certificate expiration calculations wrong on macOS

**Workaround**: Install GNU coreutils: `brew install coreutils`

### Issue: systemd timers don't persist across reboots

**Cause**: `Persistent=true` not set in timer

**Fix**:
```bash
# Edit /etc/systemd/system/auto-ssl-renew.timer
# Ensure it has:
[Timer]
Persistent=true
```

## FAQ

**Q: Can I use the same CA for multiple networks?**
A: Not recommended. Use separate CAs for security isolation.

**Q: What happens if the CA server goes down?**
A: Existing certificates continue to work. New issuance and renewal fail until CA is back.

**Q: Can I change the CA IP address?**
A: Yes, but you need to update all enrolled servers. See CA Migration guide.

**Q: How do I rotate the CA root certificate?**
A: This requires careful planning. Document coming soon.

**Q: Can I use this in production?**
A: Yes, but ensure you have backups, monitoring, and tested disaster recovery.
