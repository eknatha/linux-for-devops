# 02 - Linux Process Management for DevOps

> **Production-grade Linux process management** — covering process lifecycle, signals, job control, systemd service management, resource limits, priority tuning, daemon patterns, and process observability for real-world DevOps environments.

---

![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)



## 📁 Module Structure

```
02-process-management/
├── README.md                          ← You are here
├── process-management.md              ← Deep-dive reference guide
├── scripts/
│   ├── process-snapshot.sh            ← Full process state snapshot
│   ├── resource-limiter.sh            ← Apply cgroup/ulimit resource controls
│   ├── graceful-restart.sh            ← Zero-downtime service restart
│   └── zombie-cleaner.sh              ← Detect and clean zombie processes
└── examples/
    ├── systemd-app.service            ← Hardened production systemd unit
    ├── limits-production.conf         ← /etc/security/limits.conf for production
```

---

## 🚀 Quick Start

### Inspect running processes

```bash
# Interactive process viewer
top
htop            # install: sudo apt install htop

# Static snapshot — sorted by CPU
ps aux --sort=-%cpu | head -15

# Full process tree
ps axjf
pstree -p

# Find a process by name
pgrep -la nginx
ps aux | grep nginx
```

### Control a process

```bash
# Graceful stop (SIGTERM → process cleans up)
kill -15 <PID>
kill <PID>        # SIGTERM is default

# Force kill (SIGKILL → immediate termination, no cleanup)
kill -9 <PID>

# Reload config (SIGHUP — no restart required)
kill -HUP <PID>

# By name
pkill nginx
killall nginx
```

### Manage services with systemd

```bash
sudo systemctl start|stop|restart|reload myapp
sudo systemctl status myapp
sudo systemctl enable myapp        # Start on boot
journalctl -u myapp -f             # Follow service logs
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [Process Lifecycle](#) | fork, exec, exit, wait — states and transitions |
| [Signals](#) | SIGTERM, SIGKILL, SIGHUP, SIGUSR1/2, signal handling |
| [Job Control](#) | foreground/background, fg, bg, nohup, disown |
| [ps and pgrep](#) | process inspection, filtering, formatting |
| [top / htop / btop](#) | interactive monitoring, sorting, killing |
| [Process Priority](#) | nice, renice, ionice — CPU and I/O scheduling |
| [Resource Limits](#) | ulimit, /etc/security/limits.conf, cgroups |
| [systemd](#) | units, targets, journald, socket activation |
| [Daemon Patterns](#) | nohup, screen, tmux, double-fork, systemd |
| [Zombie Processes](#) | detection, causes, prevention, cleanup |
| [Process Profiling](#) | strace, lsof, /proc filesystem |
| [Production Runbook](#) | high CPU, runaway processes, OOM incidents |

---

## ⚡ Production Process Management Checklist

- [ ] Run all services as dedicated non-root service accounts
- [ ] Manage all daemons via systemd — never run bare `nohup` commands in production
- [ ] Set `Restart=on-failure` and `RestartSec=` in all systemd units
- [ ] Configure `LimitNOFILE`, `LimitNPROC`, `MemoryMax` in service units
- [ ] Enable `NoNewPrivileges=yes` and `ProtectSystem=strict` for security
- [ ] Use `systemctl reload` instead of `restart` when the app supports live config reload
- [ ] Monitor for zombie processes — more than 10 indicates a bug in the parent
- [ ] Set up `OOMScoreAdj` to protect critical services from the OOM killer
- [ ] Configure `ulimit` / `/etc/security/limits.conf` before tuning `sysctl`
- [ ] Log all systemd service failures to a centralised log aggregator

---

## 🛠️ Essential Process Commands — Quick Reference

```bash
# List and find
ps aux                          All processes, all users
ps -eo pid,ppid,user,%cpu,%mem,stat,comm  Custom format
pgrep -la nginx                 PIDs + names matching nginx
pgrep -P 1234                   Child processes of PID 1234
pidof nginx                     PID of process named nginx

# Signals
kill -l                         List all signals
kill -15 <PID>                  SIGTERM — graceful stop
kill -9 <PID>                   SIGKILL — force stop
kill -1 <PID>                   SIGHUP — reload
kill -USR1 <PID>                SIGUSR1 — app-defined action
pkill -15 nginx                 SIGTERM all nginx processes
killall -HUP nginx              SIGHUP all nginx processes

# Priority
nice -n 10 ./myscript.sh        Start with low priority (+10)
renice +10 -p <PID>             Lower priority of running process
renice -5 -p <PID>              Raise priority (requires root)
ionice -c 3 -p <PID>            Set I/O class to idle

# Background / foreground
command &                       Run in background
Ctrl+Z                          Suspend foreground job
bg %1                           Resume suspended job in background
fg %1                           Bring job to foreground
jobs -l                         List background jobs
nohup command &                 Persist after terminal close
disown %1                       Remove job from shell job table

# Resource limits (current session)
ulimit -n 65536                 Set open file limit
ulimit -u 4096                  Set process limit
ulimit -a                       Show all limits

# systemd
systemctl list-units --failed   Failed services
systemctl is-active myapp       Is it running?
systemctl show myapp            All service properties
systemd-analyze blame           Slowest services at boot
```

---

## 🔗 See Also

- [process-management.md] — full reference with all commands and production examples
- `man ps`, `man kill`, `man nice`, `man systemctl`, `man journalctl`
- [systemd documentation](https://www.freedesktop.org/wiki/Software/systemd/)
- [Linux Process States](https://man7.org/linux/man-pages/man5/proc.5.html)
- [cgroups v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 02-process-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
