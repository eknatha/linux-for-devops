# 07 - Linux System Monitoring for DevOps

> **Production-grade Linux system monitoring** — covering CPU, memory, disk, network, process monitoring, log analysis, alerting, and observability tooling for real-world DevOps environments.

---

## 📁 Module Structure

```
07-system-monitoring/
├── README.md                            ← You are here
├── system-monitoring.md                 ← Deep-dive reference guide
├── scripts/
    ├── health-check.sh                  ← Full system health snapshot
    ├── disk-alert.sh                    ← Disk usage threshold alerting
    ├── process-monitor.sh               ← Monitor & auto-restart processes
    └── log-analyzer.sh                  ← Parse and summarize system logs

```

---

## 🚀 Quick Start

### Instant system health snapshot

```bash
# CPU, memory, disk, load average — at a glance
echo "=== Load ===" && uptime
echo "=== CPU ===" && top -bn1 | grep "Cpu(s)"
echo "=== Memory ===" && free -h
echo "=== Disk ===" && df -hT | grep -v tmpfs
echo "=== Top processes ===" && ps aux --sort=-%cpu | head -8
```

### Monitor a specific process

```bash
# Watch nginx CPU + memory every 2 seconds
watch -n2 'ps aux | grep nginx | grep -v grep'
```

### Check open ports and connections

```bash
sudo ss -tulnp
sudo netstat -tulnp     # alternative
```

### Real-time log tailing

```bash
sudo journalctl -f -u nginx
sudo tail -f /var/log/syslog
sudo tail -f /var/log/auth.log | grep --line-buffered 'Failed\|Accepted'
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [CPU Monitoring](#) | load average, top, htop, mpstat, sar |
| [Memory Monitoring](#) | free, vmstat, /proc/meminfo, OOM killer |
| [Disk & I/O](#) | df, du, iostat, iotop, lsof |
| [Network Monitoring](#) | ss, netstat, iftop, nethogs, tcpdump |
| [Process Management](#) | ps, pgrep, strace, lsof, systemd |
| [Log Management](#) | journalctl, syslog, logrotate, grep patterns |
| [System Metrics](#) | sar, vmstat, dstat, /proc filesystem |
| [Alerting](#) | threshold scripts, Prometheus, Alertmanager |
| [Observability Stack](#) | Prometheus + Grafana + Node Exporter |
| [Automation](#) | cron-based health checks, auto-restart scripts |

---

## ⚡ Production Monitoring Checklist

- [ ] Set up `node_exporter` on all servers (Prometheus metrics)
- [ ] Configure disk usage alerts at 75% warn / 90% critical
- [ ] Monitor CPU load average — alert when > number of cores for 5+ min
- [ ] Set memory alert at 85% used
- [ ] Enable `auditd` for security event monitoring
- [ ] Configure `logrotate` for all application logs
- [ ] Set up `journalctl` log persistence (`Storage=persistent`)
- [ ] Monitor failed `systemd` units automatically
- [ ] Set up dead man's switch / heartbeat for cron jobs
- [ ] Configure `fail2ban` for brute force detection

---

## 🛠️ Essential Monitoring Commands — Quick Reference

```bash
# System overview
top / htop / btop           # Interactive process viewer
uptime                      # Load average (1, 5, 15 min)
vmstat 1 10                 # Virtual memory, CPU, I/O stats (10 samples, 1s interval)
dstat                       # Combined CPU + disk + net + memory

# CPU
mpstat -P ALL 1 5           # Per-core CPU stats
sar -u 1 5                  # CPU utilisation via sysstat
pidstat -u 1                # Per-process CPU usage

# Memory
free -h                     # Memory overview
cat /proc/meminfo           # Detailed memory breakdown
vmstat -s                   # Memory statistics summary

# Disk
df -hT                      # Disk usage by filesystem
du -sh /var/log/*           # Directory sizes
iostat -xz 1                # I/O statistics per device
iotop -o                    # Processes doing I/O (needs root)
lsblk                       # Block device tree

# Network
ss -tulnp                   # Open ports + listening processes
iftop -i eth0               # Network bandwidth by connection
nethogs eth0                # Network bandwidth by process
tcpdump -i eth0 -n port 80  # Packet capture

# Logs
journalctl -xe              # Recent journal entries with context
journalctl -u sshd -f       # Follow specific service log
journalctl --since "1 hour ago" --priority=err
grep -r 'ERROR\|CRIT' /var/log/ --include="*.log"
```

---

## 🔗 See Also

- [system-monitoring.md] — full reference with all commands and production examples
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Linux Performance Tools by Brendan Gregg](https://www.brendangregg.com/linuxperf.html)
- [USE Method](https://www.brendangregg.com/usemethod.html) — Utilisation, Saturation, Errors

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha

> **Repository:** linux-for-devops / 07-system-monitoring
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
