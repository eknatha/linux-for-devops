# dns-check.sh

A DNS audit tool for production deployments and incident triage. Checks all major record types, validates SPF/DKIM/DMARC email security, tests TLS certificate validity, verifies forward-confirmed reverse DNS, and checks propagation consistency across 8 public resolvers — all from a single command.

---

![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**


## What It Does

Runs up to **10 checks** depending on options and record type:

| # | Check | What It Looks At |
|---|---|---|
| 1 | **System Resolver** | Active nameserver from `/etc/resolv.conf` |
| 2 | **A Record** | IPv4 address(es), query time, optional expected IP assertion |
| 3 | **AAAA Record** | IPv6 address (informational — no failure if absent) |
| 4 | **NS Records** | Authoritative nameservers for the domain |
| 5 | **MX Records** | Mail exchanger records for email delivery |
| 6 | **TXT Records** | SPF, DKIM, DMARC — auto-detected and labelled |
| 7 | **CNAME Record** | Alias target (noted if none — not an error) |
| 8 | **PTR / FCrDNS** | Reverse DNS and forward-confirmed reverse DNS match |
| 9 | **TLS Certificate** | Expiry days remaining, SAN coverage, issuer *(with `--check-cert`)* |
| 10 | **Propagation** | A record across 8 public resolvers with consistency check *(with `--check-propagation`)* |

---

## Quick Start

```bash
chmod +x dns-check.sh

# Full audit of all record types
./dns-check.sh --domain api.example.com

# Assert the A record resolves to a specific IP + check TLS cert
./dns-check.sh --domain api.example.com \
  --expected-ip 10.0.1.20 \
  --check-cert

# Check only MX records
./dns-check.sh --domain example.com --type MX

# Propagation test — has the new DNS record reached all resolvers?
./dns-check.sh --domain api.example.com --check-propagation

# Save report and post Slack alert on issues
./dns-check.sh --domain api.example.com \
  --check-cert \
  --output /tmp/dns-report.txt \
  --slack https://hooks.slack.com/services/XXX/YYY/ZZZ
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--domain DOMAIN` | *(required)* | Domain name to check |
| `--type TYPE` | `all` | Record type: `A`, `AAAA`, `MX`, `TXT`, `NS`, `CNAME`, `PTR`, or `all` |
| `--expected-ip IP` | — | Assert the A record equals this IP — fails if it doesn't match |
| `--check-cert` | — | Check TLS certificate expiry, SANs, and hostname coverage |
| `--check-propagation` | — | Test A record against 8 public resolvers and flag inconsistencies |
| `--output FILE` | stdout | Save full report to file |
| `--slack WEBHOOK` | — | Post alert summary to Slack (only fires if issues found) |
| `--quiet` | — | Suppress stdout (use with `--output`) |

---

## Record Types

| Type | Use Case |
|---|---|
| `A` | IPv4 address — most common check |
| `AAAA` | IPv6 address |
| `NS` | Nameserver delegation — check after domain transfer |
| `MX` | Email routing — check before/after email migration |
| `TXT` | SPF, DKIM, DMARC, domain verification tokens |
| `CNAME` | Alias records — CDN, load balancer, third-party integrations |
| `PTR` | Reverse DNS — important for email deliverability |
| `all` | All of the above in sequence (default) |

---

## What Gets Flagged

| Condition | Severity |
|---|---|
| A record not found (NXDOMAIN or timeout) | ✘ Fail |
| A record does not match `--expected-ip` | ✘ Fail |
| No NS records found | ✘ Fail |
| Cannot connect to domain on port 443 | ✘ Fail |
| TLS certificate expired | ✘ Fail |
| Certificate expiring within 14 days | ✘ Fail |
| Certificate does not cover the domain | ✘ Fail |
| No MX records found | ⚠ Warning |
| No SPF record (`v=spf1`) | ⚠ Warning |
| No DMARC record at `_dmarc.<domain>` | ⚠ Warning |
| No PTR (reverse DNS) record | ⚠ Warning |
| FCrDNS mismatch (PTR doesn't resolve back) | ⚠ Warning |
| Certificate expiring within 30 days | ⚠ Warning |
| Resolver returns different IP than others | ⚠ Warning |

---

## TLS Certificate Check

Triggered with `--check-cert`. Connects to port 443 using `openssl s_client` and checks:

- Subject and issuer
- Expiry date and days remaining
- Subject Alternative Names (SANs)
- Whether the certificate covers the domain being checked

```
  Subject:             CN=api.example.com
  Issuer:              Let's Encrypt Authority X3
  Expires:             Mar 15 00:00:00 2025 GMT
  SANs:                DNS:api.example.com DNS:*.example.com
  ✔  Certificate valid for 82 more days
  ✔  Certificate covers api.example.com
```

---

## Propagation Check

Triggered with `--check-propagation`. Tests the A record against **8 public resolvers** and checks whether they all return the same IP — essential after a DNS change or migration.

```
  Resolver                  Name                 Result       Time
  ──────────────────────────────────────────────────────────────────────
  8.8.8.8                   Google               10.0.1.20    12 ms
  8.8.4.4                   Google-2             10.0.1.20    11 ms
  1.1.1.1                   Cloudflare           10.0.1.20    8 ms
  9.9.9.9                   Quad9                10.0.1.20    15 ms
  208.67.222.222            OpenDNS              10.0.1.19    ← different!

  ⚠  Inconsistent answers — DNS may still be propagating
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | One or more warnings |
| `2` | One or more failures |

```bash
./dns-check.sh --domain api.example.com --check-cert || echo "DNS issues found (exit: $?)"
```

---

## Common Use Cases

```bash
# Before a deployment — assert the new IP is live
./dns-check.sh --domain api.example.com --expected-ip 10.0.1.50

# After a Let's Encrypt renewal — verify certificate
./dns-check.sh --domain api.example.com --check-cert

# After a DNS migration — confirm propagation is complete
./dns-check.sh --domain example.com --check-propagation

# Email deliverability audit — check SPF, DKIM, DMARC, PTR
./dns-check.sh --domain example.com --type TXT
./dns-check.sh --domain example.com --type PTR

# Cron: daily cert expiry check with Slack alert
0 8 * * * /opt/scripts/dns-check.sh \
    --domain api.example.com \
    --type A \
    --check-cert \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ \
    --quiet
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `dig` (`dnsutils`) | All DNS record queries |
| `openssl` *(optional)* | TLS certificate check (`--check-cert`) |
| `curl` *(optional)* | Slack alert delivery |

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 03-networking
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
