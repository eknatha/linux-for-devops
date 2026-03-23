# process-monitor.sh

A lightweight Bash script that watches critical Linux processes and automatically restarts them when they go down — with smart cooldown logic, Slack/email alerting, and recovery detection.

---
![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**


## What It Does

- **Detects** when a process or systemd service has stopped
- **Restarts** it automatically via `systemctl` or a custom command
- **Limits** restarts to prevent infinite restart loops (configurable max + cooldown window)
- **Alerts** your team via Slack webhook or email on crash, restart, max-restarts-exceeded, and recovery
- **Logs** every event to a log file and syslog (`logger`)
- **Runs** as a daemon (background loop) or one-shot via cron

---

## Quick Start

```bash
# Clone the repo and make executable
chmod +x process-monitor.sh

# Monitor nginx (systemd service)
sudo ./process-monitor.sh --service nginx

# Monitor with Slack alerts
sudo ./process-monitor.sh --service myapp \
  --slack https://hooks.slack.com/services/XXX/YYY/ZZZ

# Monitor a custom process (non-systemd)
sudo ./process-monitor.sh \
  --process myapp \
  --restart-cmd "sudo systemctl restart myapp" \
  --max-restarts 3 \
  --cooldown-min 30

# Cron mode — run once per minute check
echo "* * * * * root /opt/scripts/process-monitor.sh --service myapp --once" \
  | sudo tee /etc/cron.d/process-monitor
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--service NAME` | — | systemd service to monitor and restart |
| `--process NAME` | — | Process name to watch via `pgrep` |
| `--restart-cmd CMD` | — | Custom restart command (non-systemd) |
| `--pid-file FILE` | — | Check a PID file instead of `pgrep` |
| `--max-restarts N` | `3` | Max restarts allowed within cooldown window |
| `--cooldown-min N` | `60` | Cooldown window in minutes |
| `--slack WEBHOOK` | — | Slack incoming webhook URL for alerts |
| `--email ADDRESS` | — | Email address for alerts (requires `mailutils`) |
| `--log-file FILE` | `/var/log/process-monitor.log` | Log file path |
| `--interval N` | `30` | Check interval in seconds (daemon mode) |
| `--dry-run` | — | Log and alert without actually restarting |
| `--once` | — | Check once and exit (for cron use) |

---

## How the Restart Limit Works

The script tracks restart timestamps in `/tmp/process-monitor-state/`. If a process is restarted more than `--max-restarts` times within the `--cooldown-min` window, further restarts are blocked and a **MAX_RESTARTS_EXCEEDED** alert is fired — preventing restart loops from masking a deeper problem.

```
Process crashes → restart #1 → OK
Process crashes → restart #2 → OK
Process crashes → restart #3 → OK
Process crashes → [BLOCKED] Max restarts reached → Alert fired → Manual action needed
```

After the cooldown window passes, the counter resets automatically.

---

## Alert Events

| Event | Triggered When |
|---|---|
| `RESTARTED` | Process was down and successfully restarted |
| `RESTART_FAILED` | Restart command ran but process still not running |
| `MAX_RESTARTS_EXCEEDED` | Restart limit hit within cooldown window |
| `RECOVERED` | Process is back online after being marked down |

---

## Running as a systemd Service (Daemon Mode)

```ini
# /etc/systemd/system/process-monitor-nginx.service
[Unit]
Description=Process Monitor — nginx
After=network.target

[Service]
ExecStart=/opt/scripts/process-monitor.sh \
    --service nginx \
    --interval 30 \
    --max-restarts 3 \
    --cooldown-min 60 \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now process-monitor-nginx
```

---

## Running via Cron

```bash
# Check every minute, exit after one check
* * * * * root /opt/scripts/process-monitor.sh \
    --service myapp \
    --once \
    --max-restarts 3 \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ \
    >> /var/log/process-monitor.log 2>&1
```

---

## Log Output

```
2024-01-15 14:32:01 [WARN]  myapp is DOWN — reason: process not found
2024-01-15 14:32:01 [WARN]  Restart attempts in last 60 min: 1/3
2024-01-15 14:32:01 [INFO]  Attempting restart of myapp (attempt 1/3)...
2024-01-15 14:32:06 [INFO]  myapp restarted successfully
2024-01-15 14:32:06 [INFO]  Slack alert sent: RESTARTED
```

---

## Requirements

| Tool | Required | Purpose |
|---|---|---|
| `bash` ≥ 4.x | ✔ | Script runtime |
| `systemctl` | For `--service` mode | Service restart |
| `pgrep` | For `--process` mode | Process detection |
| `curl` | For Slack alerts | Webhook POST |
| `mail` | For email alerts | Email delivery (`mailutils`) |
| `logger` | Always | Syslog integration |

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 07-system-monitoring
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
