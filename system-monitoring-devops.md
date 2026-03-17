# Advanced System Monitoring Guide for SRE / DevOps / Platform Engineers (Linux/RHEL)

A comprehensive guide to monitoring Linux systems using both basic and advanced tools for performance, reliability, and troubleshooting in production environments.

---

## Table of Contents

- Overview
- Monitoring Principles
- CPU Monitoring
- Memory Monitoring
- Disk Monitoring
- Network Monitoring
- Process Monitoring
- System Load Monitoring
- Advanced Troubleshooting Commands
- Logging & Observability
- Monitoring Tools
- Best Practices

---

# Overview

System monitoring ensures:

- High availability
- Performance optimization
- Early detection of failures
- Security visibility

This guide focuses on **real-world commands used by SREs in production systems**.

---

# Monitoring Principles

- **Observe everything** (metrics, logs, traces)
- **Automate alerting**
- **Reduce noise (alert fatigue)**
- **Correlate metrics with logs**

---

# CPU Monitoring

Basic:

```bash
top
htop
```

Advanced:

Per-core usage in real time :

```bash
mpstat -P ALL 1
```

CPU usage per process :

```bash
pidstat 1
```

Historical CPU usage :

```bash
sar -u 1 5
```


---

# Memory Monitoring

Basic:

```bash
free -h
```

Advanced:

Real-time memory + CPU stats : 

```bash
vmstat 1
```

Accurate memory usage per process : 

```bash
smem -r
```

Detailed memory breakdown : 

```bash
cat /proc/meminfo
```


---

# Disk Monitoring

Basic:

```bash
df -h
```

Advanced:

Detailed disk I/O stats :

```bash
iostat -x 1
```

Real-time disk usage per process :

```bash
iotop
```

Block device info :

```bash
lsblk
```

Filesystem UUID info :

```bash
blkid
```


Find largest files : 

```bash
du -xah / | sort -rh | head -20
```


---

# Network Monitoring

Basic:

```bash
ss -tulnp
```

Advanced:

**Live bandwidth usage**

```bash
iftop
```

Traffic monitoring : 

```bash
nload
```

**Interface statistics :**

```bash
ip -s link
```


**Protocol statistics :**

```bash
netstat -s
```

Packet capture (debugging) :

```bash
tcpdump -i eth0
```

**Network path + latency analysis :**

```bash
mtr google.com
```

---

# Process Monitoring

Basic:

```bash
ps aux
```

Advanced:

**Top CPU-consuming processes :**

```bash
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head
```

**Sort by memory usage :**

```bash
top -o %MEM
```

Files opened by a process : 

```bash
lsof -p <PID>
```

Trace system calls (debugging) : 

```bash
strace -p <PID>
```

---

# System Load Monitoring

```bash
uptime
```

```bash
cat /proc/loadavg
```

Check CPU cores:

```bash
nproc
```

---

# Advanced Troubleshooting Commands

## Check Kernel Messages

```bash
dmesg | tail
```

## Real-time System Logs

```bash
journalctl -f
```

## Check Failed Services

```bash
systemctl --failed
```

## Analyze Boot Performance

```bash
systemd-analyze blame
```

## Service Logs

```bash
journalctl -u nginx <Service_name>
```

## Open Files System-wide

```bash
lsof | wc -l
```

## Check Zombie Processes

```bash
ps aux | grep Z
```

---

# Logging & Observability

Important logs:

```
/var/log/messages
/var/log/secure
/var/log/audit/audit.log
```

Commands:

```bash
tail -f /var/log/messages
```

```bash
journalctl -xe
```

---

# Monitoring Tools

## Metrics & Visualization

- Prometheus
- Grafana
- Node Exporter

## Logging

- ELK Stack (Elasticsearch, Logstash, Kibana)
- Loki

## Traditional Monitoring

- Nagios
- Zabbix

## Security Monitoring

- Falco
- auditd

---

# Best Practices

- Monitor all critical resources (CPU, memory, disk, network)
- Set alert thresholds
- Use dashboards for visibility
- Centralize logs
- Automate monitoring setup
- Regularly review alerts
- Perform capacity planning

---

# Quick Troubleshooting Cheat Sheet

| Use Case | Command |
|----------|--------|
| High CPU | top, mpstat, pidstat |
| High memory | free -h, vmstat, smem |
| Disk issues | df -h, iostat, iotop |
| Network issues | ss, iftop, tcpdump |
| Process issues | ps, top, strace |
| Logs | journalctl, tail |

---

# Conclusion

Advanced monitoring is essential for:

- Diagnosing production issues
- Improving system performance
- Ensuring reliability

SRE and DevOps engineers should combine:

- Real-time monitoring
- Historical metrics
- Log analysis

to achieve full observability.

# Author
**- Eknatha Reddy Puli**
