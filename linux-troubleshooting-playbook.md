# Linux Troubleshooting Playbook for DevOps / SRE 

Production systems occasionally fail. When incidents occur, DevOps and SRE engineers must quickly diagnose and resolve issues. A structured troubleshooting approach helps identify root causes faster and minimize downtime.

This playbook provides **practical Linux troubleshooting steps used in real production environments**.

---

# 1. General Troubleshooting Workflow

When investigating issues, follow a consistent process:

1. Identify the problem
2. Check system health
3. Inspect logs
4. Verify service status
5. Investigate resource usage
6. Identify root cause
7. Apply fix
8. Monitor system after fix

---

# 2. Check System Uptime and Load

Check how long the system has been running and its load average.

```bash
uptime
```

Example output:

```
10:25:01 up 5 days,  3 users,  load average: 0.20, 0.30, 0.25
```

Load average represents:

- 1 minute
- 5 minutes
- 15 minutes

High load may indicate **CPU or I/O bottlenecks**.

---

# 3. Check CPU Usage

Identify processes consuming high CPU.

```bash
top
```

Alternative interactive tool:

```bash
htop
```

Sort by CPU usage:

```
Shift + P
```

---

# 4. Check Memory Usage

Check system memory usage.

```bash
free -h
```

Example output:

```
              total   used   free
Mem:           16G    6G     8G
```

Check processes using most memory:

```bash
ps aux --sort=-%mem | head
```

---

# 5. Check Disk Usage

Full disks are a common production issue.

```bash
df -h
```

Find large directories:

```bash
du -sh /* | sort -rh
```

Find large log files:

```bash
du -sh /var/log/*
```

---

# 6. Check Running Processes

View active processes.

```bash
ps aux
```

Find specific process:

```bash
ps aux | grep nginx
```

Kill stuck process:

```bash
kill -9 PID
```

---

# 7. Check Service Status

Verify whether services are running.

```bash
systemctl status service-name
```

Example:

```bash
systemctl status nginx
```

Restart service if needed:

```bash
sudo systemctl restart nginx
```

---

# 8. Check Logs

Logs are essential for identifying failures.

View system logs:

```bash
journalctl
```

View logs for a specific service:

```bash
journalctl -u service-name
```

Follow logs in real time:

```bash
journalctl -f
```

Example:

```bash
journalctl -u nginx -f
```

---

# 9. Check Network Connectivity

Verify network connectivity.

Test connection to remote host:

```bash
ping google.com
```

Check open ports:

```bash
ss -tuln
```

Check process using a port:

```bash
lsof -i :8080
```

Trace network route:

```bash
traceroute google.com
```

---

# 10. Check DNS Resolution

Verify domain resolution.

```bash
dig example.com
```

Alternative:

```bash
nslookup example.com
```

---

# 11. Check Disk I/O Issues

High disk I/O can slow down applications.

```bash
iostat -x 2
```

Check processes causing I/O wait:

```bash
iotop
```

---

# 12. Check Open Files

Applications sometimes hold deleted files that still consume disk space.

```bash
lsof | grep deleted
```

---

# 13. Check Login Activity

View logged-in users:

```bash
who
```

View login history:

```bash
last
```

Check failed login attempts:

```bash
grep "Failed password" /var/log/auth.log
```

---

# 14. Investigate High Load

Steps to investigate high system load:

1. Check load average

```
uptime
```

2. Identify CPU-heavy processes

```
top
```

3. Check disk I/O

```
iostat -x
```

4. Review logs

```
journalctl
```

---

# 15. Troubleshooting Service Down

Example workflow when a service stops working.

1. Check service status

```bash
systemctl status service-name
```

2. Inspect logs

```bash
journalctl -u service-name
```

3. Check port usage

```bash
ss -tuln
```

4. Restart service

```bash
systemctl restart service-name
```

---

# 16. Useful Troubleshooting Commands

| Command | Purpose |
|---|---|
| `uptime` | System load |
| `top` | CPU usage |
| `free -h` | Memory usage |
| `df -h` | Disk usage |
| `du -sh` | Directory size |
| `ps aux` | Running processes |
| `systemctl` | Service management |
| `journalctl` | View logs |
| `ss` | Open ports |
| `lsof` | Open files |
| `ping` | Connectivity test |

---

# Best Practices for Incident Response

- Use a **structured troubleshooting process**
- Check **system resources first**
- Inspect **logs for root cause**
- Avoid random fixes without investigation
- Document incidents and resolutions

---

# Conclusion

Linux troubleshooting is a critical skill for DevOps and SRE engineers. Effective debugging helps reduce downtime, identify root causes quickly, and maintain reliable infrastructure.

By mastering these commands and workflows, engineers can respond to production incidents **faster and more effectively**.

---

⭐ If you found this useful, consider **starring the repository**. 
