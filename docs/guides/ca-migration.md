# CA Migration Guide

How to migrate your Certificate Authority to a new server or IP address.

## When to Migrate

- Hardware upgrade
- IP address change
- Datacenter move
- Consolidation
- Disaster recovery

## Before You Start

### Prerequisites
- Working backup of current CA
- New server prepared
- Network access between old and new
- Downtime window planned

### Plan Downtime
CA migration requires brief downtime:
- CA stop: ~1 minute
- Data transfer: depends on size (usually < 5 minutes)
- Verification: ~2 minutes
- **Total**: ~10-15 minutes typical

## Migration Types

### Type 1: Same IP (Hardware Upgrade)

Simplest - CA URL doesn't change.

### Type 2: New IP (Network Change)

Requires updating all enrolled servers.

### Type 3: New CA (Complete Replacement)

Most complex - essentially starting fresh.

## Migration Procedure

### Same IP Migration

**Step 1: Backup on old server**
```bash
# On old CA server
sudo auto-ssl ca backup --output /tmp/ca-backup.enc
```

**Step 2: Transfer backup**
```bash
# Copy to new server
scp /tmp/ca-backup.enc newserver:/tmp/
```

**Step 3: Stop old CA**
```bash
# On old CA server
sudo systemctl stop step-ca
sudo systemctl disable step-ca
```

**Step 4: Assign old IP to new server**
```bash
# On new server - adjust for your network config
sudo ip addr add 192.168.1.100/24 dev eth0
```

**Step 5: Restore on new server**
```bash
# On new CA server
sudo auto-ssl ca restore --input /tmp/ca-backup.enc
```

**Step 6: Verify**
```bash
# Check CA is running
sudo systemctl status step-ca

# Test from enrolled server
curl -k https://192.168.1.100:9000/health
```

**Done!** No enrolled server changes needed.

### New IP Migration

**Step 1-3: Same as above**

**Step 4: Restore with new IP**
```bash
# On new CA server
sudo auto-ssl ca restore \
  --input /tmp/ca-backup.enc \
  --new-address 192.168.1.200:9000
```

**Step 5: Update enrolled servers**

Option A - Using auto-ssl:
```bash
# From new CA server
auto-ssl remote update-ca-url \
  --new-url https://192.168.1.200:9000
```

Option B - Manual update per server:
```bash
# On each enrolled server
export STEPPATH=/root/.step
step ca bootstrap \
  --ca-url https://192.168.1.200:9000 \
  --fingerprint $(step certificate fingerprint /etc/ssl/auto-ssl/server.crt) \
  --force
```

**Step 6: Update client trust**

Clients don't need updates (they trust the root CA, not the server).

### New CA (Fresh Start)

**Step 1: Initialize new CA**
```bash
# On new server
sudo auto-ssl ca init --name "New Internal CA"
```

**Step 2: Get new fingerprint**
```bash
step certificate fingerprint /opt/step-ca/certs/root_ca.crt
```

**Step 3: Re-enroll all servers**
```bash
# From new CA
for server in server1 server2 server3; do
  auto-ssl remote enroll --host $server --user admin
done
```

**Step 4: Re-trust on all clients**
```bash
# Each client needs to trust new CA
sudo auto-ssl client trust \
  --ca-url https://NEW_CA_IP:9000 \
  --fingerprint NEW_FINGERPRINT
```

## Rollback Plan

If migration fails:

### Same IP Migration
```bash
# On old server
sudo systemctl start step-ca
# CA immediately operational
```

### New IP Migration
```bash
# On old server  
sudo systemctl start step-ca

# On servers that were updated
step ca bootstrap --ca-url https://OLD_IP:9000 --fingerprint OLD_FP --force
```

## Post-Migration

### Verification Checklist

- [ ] CA service running: `systemctl status step-ca`
- [ ] Health endpoint responds: `curl https://CA_IP:9000/health`
- [ ] Can issue new certificate: `step ca certificate test.internal test.crt test.key`
- [ ] Enrolled servers can renew: `auto-ssl server renew --force`
- [ ] Clients still trust certificates: `curl https://enrolled-server`

### Update Documentation

- [ ] Update CA URL in documentation
- [ ] Update network diagrams
- [ ] Update disaster recovery procedures
- [ ] Document new IP in inventory

### Clean Up

```bash
# On old CA server (after confirming new CA works)
sudo rm -rf /opt/step-ca
sudo rm -rf /etc/auto-ssl
sudo systemctl daemon-reload
```

## Troubleshooting

### Servers Can't Reach New CA

```bash
# Test connectivity
ping NEW_CA_IP

# Test CA endpoint
curl -k https://NEW_CA_IP:9000/health

# Check firewall
sudo firewall-cmd --list-ports | grep 9000
```

### Renewal Fails After Migration

```bash
# Re-bootstrap trust
step ca bootstrap --ca-url https://NEW_CA_IP:9000 --fingerprint NEW_FP --force

# Force renewal
sudo auto-ssl server renew --force
```

### Clients Get Certificate Errors

If using **new CA** (not migration):
- Clients must trust new root CA
- Old root CA won't work
- Each client needs `auto-ssl client trust` with new fingerprint

If using **migrated CA** (same keys):
- Clients don't need updates
- Check server is serving correct certificate

## Best Practices

1. **Test migration** in dev/staging first
2. **Backup everything** before starting
3. **Plan rollback** procedure
4. **Communicate downtime** to users
5. **Verify thoroughly** before declaring success
6. **Keep old CA** running until confident
7. **Update monitoring** to point to new IP
8. **Document the process** for next time

## Timeline Example

```
T-1 week:  Announce migration window
T-1 day:   Final backup of old CA
T-0:00:    Begin migration
T+0:05:    Old CA stopped, backup transferred
T+0:10:    New CA restored and started
T+0:15:    Verification complete
T+0:30:    Enrolled servers updated
T+1:00:    Migration complete, monitoring
T+1 day:   Decommission old CA
```

## Next Steps

- [Backup & Restore](backup-restore.md) - Backup procedures
- [CA Setup](ca-setup.md) - CA configuration
- [Troubleshooting](troubleshooting.md) - Common issues
