# 05 - Linux Log Analysis for DevOps

> **Production-grade Linux log analysis** — covering journald, syslog, application logs, nginx/apache access logs, security logs, log rotation, centralised logging, and real-time monitoring for real-world DevOps environments.

![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)

---

## 📁 Module Structure

```
05-log-analysis/
├── README.md                          ← You are here
├── log-analysis.md                    ← Deep-dive reference guide
├── scripts/
│   ├── log-monitor.sh                 ← Real-time log pattern alerting
│   ├── error-tracker.sh               ← Track and deduplicate errors across logs
│   └── log-archiver.sh                ← Compress, rotate, and archive logs safely
└── examples/
    ├── journalctl-patterns.sh         ← Production journalctl query patterns
    ├── grep-log-patterns.sh           ← grep patterns for common log formats
    └── logrotate-configs.conf         ← logrotate configuration templates
```

---

## 🚀 Quick Start

### Real-time log monitoring

```bash
# Follow system logs
journalctl -f

# Follow a specific service
journalctl -u nginx -f

# Follow multiple services together
journalctl -u nginx -u myapp -f

# Tail application log
tail -f /var/log/app/app.log | grep --line-buffered -iE "error|warn|crit"
```

### Investigate an incident

```bash
# Errors in the last hour
journalctl -p err --since "1 hour ago" --no-pager

# What happened around a specific time
journalctl --since "2024-01-15 14:00" --until "2024-01-15 14:30"

# All logs for a failing service
journalctl -u myapp -n 100 --no-pager
```

### Quick access log analysis

```bash
# Top 10 IPs
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# HTTP 5xx errors in the last hour
awk -v d="$(date -d '1 hour ago' +'%d/%b/%Y:%H')" '$4 > "["d && $9 ~ /^5/' \
  /var/log/nginx/access.log | wc -l

# Requests per minute
awk '{print $4}' /var/log/nginx/access.log | cut -d: -f1-3 | \
  sed 's/\[//' | sort | uniq -c | tail -10
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [journalctl](#) | systemd journal — query, filter, export |
| [syslog / rsyslog](#) | Traditional syslog, facilities, priorities |
| [Application Logs](#) | Structured and unstructured log parsing |
| [Nginx / Apache Logs](#) | Access and error log analysis |
| [Security Logs](#) | auth.log, fail2ban, SSH, sudo audit |
| [Kernel Logs](#) | dmesg, kernel messages |
| [Log Rotation](#) | logrotate configuration and management |
| [grep / awk / sed](#) | Text processing for log analysis |
| [Centralised Logging](#) | rsyslog forwarding, ELK/Loki patterns |
| [Alerting Patterns](#) | Threshold-based log alerts |
| [Log Formats](#) | JSON, combined, syslog, custom formats |
| [Production Runbook](#) | High error rate, log flood, disk full incidents |

---

## ⚡ Production Log Analysis Checklist

- [ ] Enable persistent journald storage (`Storage=persistent` in journald.conf)
- [ ] Set journal max size (`SystemMaxUse=2G` in journald.conf)
- [ ] Configure logrotate for all application log directories
- [ ] Forward critical logs to a centralised logging server
- [ ] Set up real-time alerting on ERROR/CRITICAL patterns
- [ ] Monitor log disk usage — alert at 75% of log partition
- [ ] Retain logs for at least 90 days (compliance)
- [ ] Use structured/JSON logging in applications when possible
- [ ] Index access logs for traffic analysis and anomaly detection
- [ ] Test log rotation with `logrotate --debug` before deploying

---

## 🛠️ Essential Log Commands — Quick Reference

```bash
# journalctl
journalctl -f                          Follow all logs in real-time
journalctl -u service -f               Follow specific service
journalctl -p err --since today        Errors since midnight
journalctl -b                          Logs from current boot
journalctl -b -1                       Logs from previous boot
journalctl --since "2h ago"            Last 2 hours
journalctl --disk-usage                How much disk space journal uses
journalctl --vacuum-size=1G            Trim journal to 1GB

# System logs
tail -f /var/log/syslog                Follow syslog
grep -iE "error|fail" /var/log/syslog | tail -20
dmesg -T | grep -iE "error|fail"       Kernel messages with timestamps

# Access logs
tail -f /var/log/nginx/access.log
awk '{print $9}' access.log | sort | uniq -c | sort -rn  # Status codes
grep " 5[0-9][0-9] " access.log | tail -20               # 5xx errors

# Security logs
grep "Failed password" /var/log/auth.log | tail -20
grep "Accepted" /var/log/auth.log | tail -20              # Successful logins
journalctl _COMM=sudo --since today                       # sudo activity

# Log sizes
du -sh /var/log/*/ 2>/dev/null | sort -rh | head -10
journalctl --disk-usage
```

---

## 🔗 See Also

- [log-analysis.md] — full reference with all commands and production examples
- `man journalctl`, `man logrotate`, `man rsyslog`, `man dmesg`
- [systemd journal documentation](https://www.freedesktop.org/software/systemd/man/journalctl.html)
- [Nginx log format documentation](https://nginx.org/en/docs/http/ngx_http_log_module.html)
- [The Art of Log Management](https://www.loggly.com/ultimate-guide/linux-logging-basics/)

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 05-log-analysis
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
