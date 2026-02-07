# Short-Lived Certificates

Traditional certificates last 1-2 years. auto-ssl defaults to **7 days**. This document explains why that's actually better.

## The Traditional Approach

```
Certificate issued: January 1, 2024
Certificate expires: January 1, 2025
Renewal: Manual, once a year
```

This feels convenient — set it and forget it for a year.

But it's actually a source of problems.

## Problems with Long-Lived Certificates

### 1. The 3am Expiry Problem

You issued a cert a year ago. It's 3am on a Saturday. Your monitoring didn't catch it. Your site is down with a certificate error.

```
NET::ERR_CERT_DATE_INVALID
```

This happens constantly in the industry. Long lifetimes mean infrequent renewals, which mean you forget the process, which means failures.

### 2. The Compromise Window

If your private key is compromised:

- **1-year cert:** Attacker can impersonate you for up to 364 days
- **7-day cert:** Attacker can impersonate you for up to 6 days

Even with revocation (CRL/OCSP), many clients don't check or cache results. Short lifetimes provide a hard limit.

### 3. The "We Don't Know How to Renew" Problem

When you only renew once a year, knowledge gets lost:

- The person who set it up left the company
- The documentation is outdated
- The renewal process changed
- Nobody remembers the password

### 4. Crypto Agility

Cryptographic best practices change. Short-lived certs mean you're always using current settings when you renew.

## The Short-Lived Approach

```
Certificate issued: February 3, 2024
Certificate expires: February 10, 2024
Renewal: Automatic, every 5 days (before expiry)
```

This seems scary — what if renewal fails?

But that's actually the point.

## Why Short-Lived is Better

### 1. Renewal is Continuously Tested

If your renewal process breaks, you find out in days, not months. The system either works or it doesn't — there's no "it'll probably work when we need it."

```
Week 1: Renewal works ✓
Week 2: Renewal works ✓
Week 3: Renewal fails ✗ → You notice immediately
```

### 2. Compromise Window is Limited

| Cert Lifetime | Max Exposure |
|---------------|--------------|
| 1 year | 365 days |
| 90 days | 90 days |
| 7 days | 7 days |
| 24 hours | 24 hours |

With 7-day certs, even if an attacker steals your key, they have limited time to exploit it.

### 3. No Renewal Surprise

You can't be surprised by expiration because expiration is happening constantly. It's either working or you know immediately.

### 4. Forces Automation

You can't manually renew a 7-day cert. You must automate. This means:

- Documented process (it's in the automation)
- Tested process (it runs every week)
- Reliable process (or you'd know by now)

## The Automation Requirement

Short-lived certificates require automation. This is a feature, not a bug.

**auto-ssl provides this automation:**

```bash
# Server enrollment sets up automatic renewal
auto-ssl server enroll --ca-url https://ca:9000 --fingerprint abc123
```

This creates a systemd timer that renews every 5 days:

```
/etc/systemd/system/auto-ssl-renew.timer
```

You don't think about it. It just works. If it stops working, you notice within days.

## What About Outages?

"What if my CA is down when renewal happens?"

Good question. With 7-day certs and 5-day renewal cycles:

- Day 0: Cert issued, valid for 7 days
- Day 5: Renewal attempted
  - If success: New cert, valid for 7 more days
  - If failure: Old cert still valid for 2 more days
- Day 6: Retry renewal (if day 5 failed)
- Day 7: Retry renewal (last chance)

You have a **2-day buffer**. If your CA is down for more than 2 days, you have bigger problems.

## Choosing Your Duration

auto-ssl lets you configure certificate lifetime:

| Duration | Use Case |
|----------|----------|
| 24 hours | High security, reliable infrastructure |
| 7 days | Default, good balance (recommended) |
| 30 days | Less frequent renewal, larger buffer |

```bash
# Set at CA initialization
auto-ssl ca init --cert-duration 7d --max-duration 30d

# Override per-enrollment (up to max)
auto-ssl server enroll --duration 14d ...
```

## Industry Trend

The industry is moving toward shorter lifetimes:

| Year | Browser CA/B Forum Max |
|------|------------------------|
| 2015 | 5 years |
| 2018 | 2 years |
| 2020 | 1 year (398 days) |
| Future | Likely 90 days or less |

Let's Encrypt has always used 90-day certificates. Many organizations are moving to 24-hour or shorter for internal use.

## Key Takeaways

| Long-Lived | Short-Lived |
|------------|-------------|
| Renew yearly | Renew continuously |
| Manual process | Automated process |
| Long compromise window | Limited compromise window |
| "Set and forget" | "Continuously verified" |
| Surprise failures | Immediate failure detection |

## The Bottom Line

> "The best way to ensure your renewal process works is to run it constantly."

Short-lived certificates aren't about making your life harder. They're about making failures visible and recovery automatic.

auto-ssl defaults to 7 days because it's the sweet spot:
- Short enough to limit compromise
- Long enough to recover from outages
- Forces automation (which is good)

## Next Steps

- **[ACME Protocol](acme-protocol.md)** — How automatic renewal works
- **[Server Enrollment](../guides/server-enrollment.md)** — Set up auto-renewal
