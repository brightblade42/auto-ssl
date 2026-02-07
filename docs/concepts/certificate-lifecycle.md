# Certificate Lifecycle

auto-ssl uses short-lived certificates and automation to keep TLS healthy with minimal manual work.

## Lifecycle Stages

1. **Bootstrap trust**
   - Server trusts the CA root with `step ca bootstrap`.
2. **Issue certificate**
   - Server requests a certificate from the CA using provisioner authentication.
3. **Serve traffic**
   - Web server presents `/etc/ssl/auto-ssl/server.crt` and `/etc/ssl/auto-ssl/server.key`.
4. **Renew automatically**
   - `auto-ssl-renew.timer` triggers periodic renewals.
5. **Revoke if needed**
   - Certificates can be revoked immediately (`auto-ssl server revoke`).
6. **Expire naturally**
   - Short validity (7 days by default) limits impact of leaked keys.

## Why Short-Lived Certs

- Reduces blast radius of key compromise
- Makes stale certificates self-heal quickly via automation
- Lowers dependency on heavy revocation infrastructure

## Operational Checks

- Renewal timer is active: `systemctl is-active auto-ssl-renew.timer`
- Certificate not near expiry: `auto-ssl server status`
- CA reachable and healthy: `curl -sk https://<ca>:9000/health`

## Related Docs

- [Server Enrollment](../guides/server-enrollment.md)
- [Troubleshooting](../guides/troubleshooting.md)
- [Security Model](../reference/security-model.md)
