# log-analyzer.sh

A structured log analysis tool that parses system journals, Nginx/Apache access logs, auth logs, and custom application logs — extracting error rates, top offenders, security events, and traffic patterns into a readable report.

---

![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**


## What It Does

Supports **5 analysis modes**, each targeting a different log source:

| Mode | Source | What It Extracts |
|---|---|---|
| `system` | `journald` | Entry counts by priority, top error services, kernel errors, OOM events, failed units |
| `nginx` | `/var/log/nginx/access.log` | Request volume, HTTP status breakdown, top URLs, top IPs, 4xx/5xx errors, req/min |
| `apache` | `/var/log/apache2/access.log` | Same as nginx — same Combined Log Format parser |
| `auth` | `/var/log/auth.log` or `/var/log/secure` | SSH logins/failures, top attacker IPs, sudo events, account changes, fail2ban bans |
| `app` | any file via `--log-file` | Error/warn/fatal counts, most frequent messages, hourly activity pattern |
| `all` | all of the above | Runs system + auth + nginx (if present) + app (if `--log-file` set) |

---

## Quick Start

```bash
chmod +x log-analyzer.sh

# Full report — last hour
sudo ./log-analyzer.sh

# Auth / security events — last 24 hours
sudo ./log-analyzer.sh --type auth --since "24 hours ago"

# Nginx access log analysis
sudo ./log-analyzer.sh --type nginx

# Custom application log
sudo ./log-analyzer.sh --type app --log-file /opt/myapp/logs/app.log

# Save report to file
sudo ./log-analyzer.sh --type all --since today --output /tmp/log-report.txt

# Post completion notice to Slack
sudo ./log-analyzer.sh --type system \
  --slack https://hooks.slack.com/services/XXX/YYY/ZZZ
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--type TYPE` | `all` | Log mode: `system`, `nginx`, `apache`, `auth`, `app`, `all` |
| `--since DURATION` | `1 hour ago` | Time window — passed directly to `journalctl --since` |
| `--log-file FILE` | — | Custom log file path (required for `--type app`) |
| `--output FILE` | stdout | Save full report to file (also prints to stdout) |
| `--slack WEBHOOK` | — | Post a completion summary to a Slack channel |
| `--top N` | `10` | Number of top entries to show in ranked lists |
| `--error-only` | — | Filter output to error/warning entries only |

---

## `--since` Examples

```bash
--since "1 hour ago"        # last hour (default)
--since "24 hours ago"      # last 24 hours
--since today               # from midnight
--since "2024-01-15"        # from a specific date
--since "2024-01-15 09:00"  # from a specific datetime
```

---

## What Each Mode Reports

### `system` — Journal Analysis
- Total log entries in the time window
- Entry count broken down by priority (`emerg` → `info`)
- Top services generating errors
- Critical and emergency events
- Kernel errors (from `dmesg` / `journalctl -k`)
- OOM kill events
- Currently failed systemd units

### `nginx` / `apache` — Web Access Log
- Total request count for the day
- HTTP status code breakdown (2xx / 3xx / 4xx / 5xx)
- Top `--top N` URLs by request count
- Top `--top N` client IP addresses
- All 5xx server error lines
- Top 4xx client errors grouped by status + URL
- Requests per minute (last 10 minutes)

### `auth` — Security & Authentication
- Successful SSH logins (user, source IP, port)
- Total failed SSH login attempts
- Top `--top N` attacker IPs by failure count
- Root login attempts
- `sudo` command events
- User account changes (`useradd`, `usermod`, `passwd`, etc.)
- `fail2ban` IP bans

### `app` — Custom Application Log
- File size, line count, last modified time
- Count of `ERROR`, `CRITICAL`, `WARN`, `WARNING`, `FATAL` entries
- Last `--top N` error lines
- Most frequently repeated error messages (deduped and ranked)
- Hourly activity pattern across the log file

---

## Sample Output — Auth Mode

```
════ Authentication & Security Log Analysis ════

  ➜  Successful SSH logins:
  deployer        from 10.0.1.45        port 52341
  john.doe        from 10.0.1.12        port 48920

  ➜  Failed SSH login attempts:
  Total failed attempts: 47

  ➜  Top 10 IPs with failed SSH logins:
  42       attempts from: 185.224.128.17
  3        attempts from: 45.33.32.156
  2        attempts from: 192.168.1.100

  ➜  sudo usage events:
  Jan 15 09:12:01 prod-01 sudo: john.doe : TTY=pts/0 ; COMMAND=/usr/bin/systemctl restart nginx
  Jan 15 09:14:44 prod-01 sudo: john.doe : TTY=pts/0 ; COMMAND=/usr/bin/journalctl -u nginx
```

---

## Cron — Scheduled Log Reports

```bash
# Daily auth report at 6am — save to file
0 6 * * * root /opt/scripts/log-analyzer.sh \
    --type auth \
    --since "24 hours ago" \
    --output /var/log/auth-report-$(date +\%F).log

# Hourly nginx summary posted to Slack
0 * * * * root /opt/scripts/log-analyzer.sh \
    --type nginx \
    --since "1 hour ago" \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ \
    --output /dev/null

# Weekly full report emailed to ops
0 8 * * 1 root /opt/scripts/log-analyzer.sh \
    --type all \
    --since "7 days ago" \
    --output /tmp/weekly-log-report.txt && \
    mail -s "Weekly Log Report: $(hostname)" ops@company.com \
    < /tmp/weekly-log-report.txt
```

---

## Using with a Custom App Log

```bash
# Node.js / Python / Go / Java — any file with ERROR/WARN/FATAL keywords
sudo ./log-analyzer.sh \
  --type app \
  --log-file /opt/myapp/logs/app.log \
  --top 20

# Override nginx log path
sudo ./log-analyzer.sh \
  --type nginx \
  --log-file /var/log/nginx/mysite-access.log

# Analyse yesterday's rotated log
sudo ./log-analyzer.sh \
  --type app \
  --log-file /opt/myapp/logs/app.log-$(date -d yesterday +%F).gz
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `journalctl` | System and auth log queries |
| `awk`, `grep`, `sort` | Log parsing and ranking |
| `systemctl` | Failed unit check (`system` mode) |
| `curl` | Slack webhook delivery |
| `mail` *(optional)* | Email delivery in cron setups |

Works on **Ubuntu/Debian** (`auth.log`) and **RHEL/CentOS** (`/var/log/secure`) — auto-detected.

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 07-system-monitoring
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
