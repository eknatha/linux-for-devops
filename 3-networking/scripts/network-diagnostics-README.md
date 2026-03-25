# network-diagnostics.sh

A single-command network health snapshot for production Linux servers. Checks interfaces, routing, DNS, internet connectivity, open ports, firewall policy, TCP performance, and NTP sync — then summarises all findings with colour-coded ✔ / ⚠ / ✘ indicators.

---
![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**


## What It Does

Runs **8 checks** in one shot and produces a structured report:

| # | Check | What It Looks At |
|---|---|---|
| 1 | **Interfaces** | Link state (UP/DOWN), IP assignment, MTU, RX/TX error counters |
| 2 | **Routing** | Default gateway presence and reachability, full routing table |
| 3 | **DNS** | Configured resolvers, query test against Google/Cloudflare/Quad9, reverse PTR for own IPs |
| 4 | **Connectivity** | ICMP ping with avg RTT to public IPs, HTTPS reachability, optional custom target |
| 5 | **Ports** | All listening TCP/UDP ports, unexpected sub-1024 listeners, connections by state |
| 6 | **Firewall** | iptables INPUT policy, UFW status, nftables rule count |
| 7 | **Performance** | Total/established/TIME_WAIT sockets, TCP retransmits, key sysctl values |
| 8 | **NTP** | Sync status, NTP service, time zone |

---

## Quick Start

```bash
chmod +x network-diagnostics.sh

# Run interactively
sudo ./network-diagnostics.sh

# Save report to file
sudo ./network-diagnostics.sh --output /var/log/net-diag-$(date +%F).log

# Test connectivity to a specific host + post alerts to Slack
sudo ./network-diagnostics.sh \
  --target api.example.com \
  --slack https://hooks.slack.com/services/XXX/YYY/ZZZ

# Machine-readable JSON summary
sudo ./network-diagnostics.sh --json | jq .
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--output FILE` | stdout | Save full report to a file (also prints to stdout) |
| `--slack WEBHOOK` | — | Post alert summary to Slack (only if issues found) |
| `--target HOST` | — | Additional host/IP to test ICMP + TCP 80/443 connectivity |
| `--json` | — | Output a JSON summary to stdout |
| `--quiet` | — | Suppress stdout (use with `--output`) |

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | One or more warnings |
| `2` | One or more critical alerts |

```bash
sudo ./network-diagnostics.sh || echo "Network issues detected (exit: $?)"
```

---

## Sample Output

```
╔══════════════════════════════════════════════════╗
║       Network Diagnostics Report                 ║
╚══════════════════════════════════════════════════╝

  Host:               prod-web-01.example.com
  Kernel:             5.15.0-91-generic

━━━━ 1. Network Interfaces ━━━━
  eth0            state:UP        mtu:1500
  eth0            10.0.1.10/24    UP
  ✔  No interface errors

━━━━ 2. Routing Table ━━━━
  ✔  Default gateway: 10.0.1.1
  ✔  Gateway 10.0.1.1 is reachable

━━━━ 3. DNS Configuration and Resolution ━━━━
  ✔  8.8.8.8 → google.com resolves to 142.250.80.46
  ✔  1.1.1.1 → google.com resolves to 142.250.80.46
  ✔  System DNS resolves google.com → 142.250.80.46

━━━━ 6. Firewall Status ━━━━
  iptables INPUT policy:    DROP
  ✔  iptables INPUT policy: DROP (default deny)
  ✔  UFW is active

━━━━ DIAGNOSTICS SUMMARY ━━━━
  Critical:           0
  Warnings:           0
  ✔ All network checks passed.
```

---

## JSON Output

Use `--json` to pipe results into monitoring systems or dashboards.

```bash
sudo ./network-diagnostics.sh --json
```

```json
{
  "host": "prod-web-01.example.com",
  "date": "2024-01-15 09:00:01 UTC",
  "critical": 0,
  "warnings": 1,
  "issues": ["WARN: UFW is not active"],
  "healthy": 0
}
```

---

## Slack Alert

When `--slack` is provided and issues are found, a formatted message is posted. Critical issues use 🔴, warnings use ⚠️. No message is sent when all checks pass.

```
⚠  Network Diagnostics — prod-web-01
  • WARN: UFW is not active
  • CRIT: Gateway 10.0.1.1 is NOT reachable
```

---

## What Gets Flagged

| Condition | Severity |
|---|---|
| Network interface in DOWN state | ⚠ Warning |
| Interface has no IP address | ⚠ Warning |
| No default gateway configured | ✘ Critical |
| Default gateway unreachable | ✘ Critical |
| DNS resolver fails to resolve | ✘ Critical |
| System DNS resolution fails | ✘ Critical |
| ICMP unreachable to public IP | ✘ Critical |
| HTTPS connectivity check fails | ⚠ Warning |
| Unexpected privileged port listening | ⚠ Warning |
| iptables INPUT policy is ACCEPT (no default deny) | ⚠ Warning |
| UFW not active | ⚠ Warning |
| NTP not synchronised | ⚠ Warning |

---

## Cron — Scheduled Checks

```bash
# Every 15 minutes — alert Slack on issues
*/15 * * * * root /opt/scripts/network-diagnostics.sh \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ \
    --quiet

# Daily report saved to file
0 7 * * * root /opt/scripts/network-diagnostics.sh \
    --output /var/log/net-diag-$(date +\%F).log \
    --quiet

# Keep only last 30 reports
0 8 * * * root find /var/log -name 'net-diag-*.log' -mtime +30 -delete
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `ip` (iproute2) | Interface, address, and routing queries |
| `ping` | Gateway and connectivity checks |
| `dig` | DNS resolution tests |
| `ss` | Port and connection statistics |
| `sysctl` | Kernel network parameter checks |
| `timedatectl` | NTP sync status |
| `nc` *(optional)* | Custom target TCP port test |
| `curl` *(optional)* | HTTPS connectivity check |
| `iptables` / `ufw` / `nft` *(optional)* | Firewall policy checks |

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 03-networking
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
