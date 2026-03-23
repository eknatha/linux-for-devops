# health-check.sh

A single-command system health snapshot for production Linux servers. Checks CPU, memory, disk, network, services, logs, file descriptors, and security — then summarises all findings with colour-coded ✔ / ⚠ / ✘ indicators.

---
![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**


## What It Does

Runs **8 checks** in one shot and produces a structured, colour-coded report:

| # | Check | What It Looks At |
|---|---|---|
| 1 | **CPU & Load** | Load average ratio vs core count, per-core breakdown |
| 2 | **Memory** | Used %, swap usage, top 5 memory consumers |
| 3 | **Disk** | Used % per filesystem, inode usage |
| 4 | **Network** | Interface RX/TX stats, listening ports, TCP state counts |
| 5 | **Services** | Failed systemd units, status of key services (nginx, postgres, etc.) |
| 6 | **Log Errors** | Error/critical count from journald in the last hour |
| 7 | **File Descriptors** | System-wide FD usage vs limit, top FD consumers |
| 8 | **Security** | SSH failure count, root login detection, zombie processes |

---

## Quick Start

```bash
chmod +x health-check.sh

# Run interactively
sudo ./health-check.sh

# Save report to file
sudo ./health-check.sh --output /var/log/health-$(date +%F).log

# Send Slack alert if issues found
sudo ./health-check.sh --slack https://hooks.slack.com/services/XXX/YYY/ZZZ

# Machine-readable JSON output
sudo ./health-check.sh --json | jq .
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--output FILE` | stdout | Save full report to a file |
| `--slack WEBHOOK` | — | Post alert summary to Slack (only fires if issues found) |
| `--json` | — | Output a JSON summary to stdout |
| `--quiet` | — | Suppress stdout (use with `--output` or `--slack`) |
| `--threshold-cpu N` | `1.5` | Load ratio (load / cores) that triggers a warning |
| `--threshold-mem N` | `85` | Memory used % that triggers a warning |
| `--threshold-disk N` | `80` | Disk used % that triggers a warning |

---

## Exit Codes

The script uses exit codes so it integrates cleanly with monitoring wrappers and CI pipelines.

| Code | Meaning |
|---|---|
| `0` | All checks passed — system is healthy |
| `1` | One or more warnings |
| `2` | One or more critical alerts |

```bash
sudo ./health-check.sh || echo "Issues found (exit: $?)"
```

---

## Sample Output

```
╔══════════════════════════════════════════════╗
║      System Health Check Report              ║
╚══════════════════════════════════════════════╝

  Host:               prod-web-01.example.com
  Uptime:             up 12 days, 4 hours

━━━━ 1. CPU & Load Average ━━━━
  CPU Cores:          4
  Load (1/5/15 min):  0.82 / 0.74 / 0.68
  Load Ratio (5min):  0.19x
  ✔  Load ratio 0.19x — healthy

━━━━ 2. Memory ━━━━
  Total RAM:          15 GB
  Used:               6 GB (41.2%)
  Available:          9 GB (58.8%)
  ✔  Memory used: 41.2% — healthy
  ✔  No swap usage

━━━━ 5. Systemd Services ━━━━
  ✔  No failed systemd units
  ✔  nginx: active
  ✔  postgresql: active

━━━━ HEALTH SUMMARY ━━━━
  Critical alerts:    0
  Warnings:           0
  ✔ All checks passed — system is healthy.
```

---

## JSON Output

Use `--json` to feed results into monitoring pipelines, dashboards, or scripts.

```bash
sudo ./health-check.sh --json
```

```json
{
  "host": "prod-web-01.example.com",
  "date": "2024-01-15 09:00:01 UTC",
  "critical": 0,
  "warnings": 1,
  "alerts": ["WARN: Memory used: 87.3% — watch closely"],
  "healthy": 0
}
```

---

## Slack Alert

When `--slack` is provided and issues are found, a message is posted with emoji severity indicators.

```
⚠  Health Check — prod-web-01 (2024-01-15 09:00:01 UTC)
  • WARN: Memory used: 87.3% — watch closely
  • WARN: Disk /var: 82% used > threshold 80%
```

Critical alerts use 🔴, warnings use ⚠️. No alert is sent if all checks pass.

---

## Cron — Scheduled Health Reports

```bash
# Daily report at 8am, saved to file
0 8 * * * root /opt/scripts/health-check.sh \
    --output /var/log/health-daily.log \
    --quiet

# Every 15 minutes with Slack alerts on issues
*/15 * * * * root /opt/scripts/health-check.sh \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ \
    --quiet

# Daily report emailed to ops (requires mailutils)
0 7 * * * root /opt/scripts/health-check.sh \
    --output /tmp/health.log --quiet && \
    mail -s "Health: $(hostname) $(date +%F)" ops@company.com < /tmp/health.log
```

---

## Thresholds Reference

| Metric | Default Warn | Default Crit |
|---|---|---|
| CPU load ratio | > `1.5x` | > `2.0x` (auto) |
| Memory used | > `70%` (warn) | > `85%` (threshold) |
| Disk used | > threshold | > threshold `+10%` |
| Log errors / hour | > `10` | > `50` |
| SSH failures / hour | > `5` | > `20` |
| File descriptor usage | > `60%` | > `80%` |

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `bc` | Floating-point threshold comparisons |
| `ss` | Network port and connection stats |
| `journalctl` | Log error counts and security events |
| `systemctl` | Service status checks |
| `mpstat` *(optional)* | Per-core CPU breakdown (`sysstat` package) |
| `curl` | Slack webhook delivery |

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 07-system-monitoring
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
