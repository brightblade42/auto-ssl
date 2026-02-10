# Caddy Integration Guide

This guide covers production-oriented Caddy patterns for internal ACME with `step-ca`, including rootless Podman.

## Key behavior to understand first

For IP and other internal host labels, Caddy Automatic HTTPS prefers its internal issuer (`Caddy Local Authority`) unless you explicitly set an ACME issuer.

That is why this often happens:

- Global `acme_ca` and `acme_ca_root` are set.
- A site address is an IP (for example `192.168.3.50`).
- Caddy still serves certs from `Caddy Local Authority`.

For internal IP hostnames, use one of these:

1. Per-site `tls { issuer acme { ... } }` (most explicit and reliable)
2. Global `cert_issuer acme { ... }` (applies ACME as default issuer across sites)

`acme_ca` alone only sets the ACME directory URL; it does not force issuer selection for names Caddy classifies as local/internal.

## Recommended Caddyfile patterns

Use one of these two patterns consistently.

### Pattern A: Per-site explicit ACME issuer (recommended)

Best when you want no ambiguity and clear behavior per site.

```caddyfile
{
    email infra@example.internal
}

https://192.168.3.50 {
    tls {
        issuer acme {
            dir https://192.168.3.225:9000/acme/acme/directory
            trusted_roots /etc/caddy/step-root-ca.crt
        }
    }

    reverse_proxy 127.0.0.1:8080
}

https://100.101.102.103 {
    tls {
        issuer acme {
            dir https://192.168.3.225:9000/acme/acme/directory
            trusted_roots /etc/caddy/step-root-ca.crt
        }
    }

    reverse_proxy 127.0.0.1:9090
}
```

### Pattern B: Global default ACME issuer

Best when all sites should always use the same internal ACME issuer.

```caddyfile
{
    email infra@example.internal

    cert_issuer acme {
        dir https://192.168.3.225:9000/acme/acme/directory
        trusted_roots /etc/caddy/step-root-ca.crt
    }
}

https://192.168.3.50 {
    reverse_proxy 127.0.0.1:8080
}

https://100.101.102.103 {
    reverse_proxy 127.0.0.1:9090
}
```

Notes:

- If you use Pattern B, you usually do not need `acme_ca`/`acme_ca_root`.
- If a site should use local certs, override that site with `tls internal`.

## Rootless Podman deployment (Linux-first)

### Why cert trust fails in containers

Rootless containers do not automatically inherit host trust stores in a way Caddy can always use for private ACME endpoints. Mount your `step-ca` root PEM and point Caddy to it with `trusted_roots`.

### Required mounts

- `Caddyfile` mounted read-only.
- `step-ca` root certificate mounted read-only.
- Persistent Caddy data dir for cert/cache state.
- Persistent Caddy config dir.

Example host paths used below:

- `./Caddyfile`
- `./pki/root_ca.crt`
- `./caddy-data`
- `./caddy-config`

## Rootless Podman run template

```bash
podman run -d \
  --name caddy \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v ./Caddyfile:/etc/caddy/Caddyfile:ro \
  -v ./pki/root_ca.crt:/etc/caddy/step-root-ca.crt:ro \
  -v ./caddy-data:/data:Z \
  -v ./caddy-config:/config:Z \
  docker.io/library/caddy:2
```

If SELinux labels are already handled externally, remove `:Z`.

## Podman Compose template

```yaml
services:
  caddy:
    image: docker.io/library/caddy:2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./pki/root_ca.crt:/etc/caddy/step-root-ca.crt:ro
      - ./caddy-data:/data:Z
      - ./caddy-config:/config:Z
```

## Tailscale + private IP best practices

- If you terminate TLS on a private LAN IP and a Tailscale IP, define each as its own site label and explicitly use ACME issuer config.
- Keep SANs minimal and intentional; do not request broad names unless required.
- Do not depend on implicit global defaults for issuer choice on internal labels.
- Keep `/data` persistent; without it, certs/accounts are recreated and can cause churn.
- Validate certificate issuer after reloads (expect your `step-ca` chain, not `Caddy Local Authority`).

## Validation checklist

```bash
# Validate Caddyfile syntax
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Reload and watch logs
caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
journalctl -u caddy -f

# Container logs (Podman)
podman logs -f caddy

# Confirm ACME directory reachable from container
podman exec -it caddy wget -qO- https://192.168.3.225:9000/acme/acme/directory

# Check leaf issuer from a client
openssl s_client -connect 192.168.3.50:443 -servername 192.168.3.50 </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject
```

## Troubleshooting quick hits

### Still seeing `Caddy Local Authority`

- Ensure site has explicit `tls { issuer acme { ... } }`, or global `cert_issuer acme { ... }`.
- Reload Caddy after config changes.
- Confirm no `tls internal` remains in that site.
- Confirm the certificate currently served is freshly issued (not old cache entry).

### ACME endpoint trust failure in container

- Verify mounted root file exists in container at `/etc/caddy/step-root-ca.crt`.
- Ensure `trusted_roots` points to the same in-container path.
- Verify CA URL from inside container (`podman exec ...`).

### Renewal instability

- Keep container `/data` volume persistent.
- Avoid frequent destructive container recreation.
- Check `podman logs caddy` for ACME challenge/issuer errors.

## Operational recommendation

For SOC 2-friendly consistency, standardize on:

- Pattern A (per-site explicit ACME issuer) for internal IP/Tailscale labels.
- Rootless Podman with mounted CA root PEM and persistent `/data`.
- A short validation run (`caddy validate`, reload, issuer check) in every config change workflow.
