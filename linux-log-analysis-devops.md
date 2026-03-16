# Linux Log Analysis for DevOps / SRE / Platform Engineers

Logs are one of the most important sources of information when debugging systems and applications. DevOps and SRE engineers rely on logs to identify failures, monitor system health, and troubleshoot production incidents.

This guide covers **essential Linux log locations, commands, and techniques for analyzing logs effectively**.

---

# 1. What Are Logs?

Logs are files that record events happening in the system or application.

Examples include:

- Application errors
- System activity
- Authentication attempts
- Network events
- Service failures

Logs are typically stored in:

```
/var/log
```

---

# 2. Common Log Directories

Important system log locations:

| Directory | Purpose |
|---|---|
| `/var/log` | Main log directory |
| `/var/log/messages` | General system logs |
| `/var/log/syslog` | System activity logs |
| `/var/log/auth.log` | Authentication logs |
| `/var/log/kern.log` | Kernel logs |
| `/var/log/nginx` | Nginx logs |
| `/var/log/httpd` | Apache logs |

Example:

```
/var/log/nginx/access.log
```

---

# 3. Viewing Logs

## View entire log file

```bash
cat /var/log/syslog
```

---

## View logs with scrolling

```bash
less /var/log/syslog
```

Useful `less` shortcuts:

| Key | Action |
|---|---|
| `Space` | Next page |
| `b` | Previous page |
| `q` | Quit |

---

## View beginning of log file

```bash
head /var/log/syslog
```

Example:

```bash
head -n 50 /var/log/syslog
```

---

## View last lines of log file

```bash
tail /var/log/syslog
```

Example:

```bash
tail -n 100 /var/log/syslog
```

---

# 4. Monitor Logs in Real Time

Real-time log monitoring is critical during debugging.

```bash
tail -f /var/log/syslog
```

Example for web server logs:

```bash
tail -f /var/log/nginx/access.log
```

---

# 5. Searching Logs

Logs can be very large. Use search tools to filter relevant data.

## Search for errors

```bash
grep "ERROR" application.log
```

---

## Case-insensitive search

```bash
grep -i error application.log
```

---

## Recursive search

```bash
grep -r "database" /var/log
```

---

## Show line numbers

```bash
grep -n "timeout" application.log
```

---

# 6. Filter Logs by Time

View logs generated recently.

Example:

```bash
grep "2024-03-01" application.log
```

Combine with `tail`:

```bash
tail -f application.log | grep ERROR
```

---

# 7. Identify Frequent Log Entries

Useful for detecting repeated errors.

Example:

```bash
cat access.log | sort | uniq -c | sort -nr
```

This shows the most frequent log entries.

---

# 8. Extract Specific Fields

Use `awk` to extract specific information.

Example: extract IP addresses from access logs.

```bash
awk '{print $1}' access.log
```

Find most frequent IP addresses:

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -nr
```

---

# 9. Analyze HTTP Access Logs

Typical web server log format:

```
192.168.1.5 - - [12/Jun/2024:10:45:32] "GET /api/users HTTP/1.1" 200 532
```

Example analysis:

Top requested endpoints:

```bash
awk '{print $7}' access.log | sort | uniq -c | sort -nr
```

Top IP addresses:

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -nr
```

---

# 10. System Logs with journalctl

Many Linux systems use **systemd journal logs**.

## View all logs

```bash
journalctl
```

---

## Show recent logs

```bash
journalctl -n 50
```

---

## Follow logs in real time

```bash
journalctl -f
```

---

## View logs for a specific service

Example:

```bash
journalctl -u nginx
```

---

## View logs since specific time

```bash
journalctl --since "1 hour ago"
```

---

# 11. Log Rotation

Logs can grow very large, so Linux uses **log rotation**.

Configuration file:

```
/etc/logrotate.conf
```

Example configuration:

```
/var/log/application.log {
    daily
    rotate 7
    compress
}
```

Meaning:

- Rotate logs daily
- Keep 7 backups
- Compress old logs

---

# 12. Real DevOps Troubleshooting Examples

## Check service crash logs

```bash
journalctl -u service-name
```

---

## Monitor application errors

```bash
tail -f application.log | grep ERROR
```

---

## Identify repeated errors

```bash
grep ERROR application.log | sort | uniq -c | sort -nr
```

---

## Investigate login attempts

```bash
grep "Failed password" /var/log/auth.log
```

---

# 13. Useful Log Analysis Commands

| Command | Purpose |
|---|---|
| `cat` | View entire log file |
| `less` | Scroll through logs |
| `head` | View beginning of file |
| `tail` | View end of file |
| `tail -f` | Follow logs in real time |
| `grep` | Search logs |
| `awk` | Extract fields |
| `sort` | Sort log entries |
| `uniq` | Remove duplicates |
| `journalctl` | View systemd logs |

---

# Conclusion

Effective log analysis helps DevOps engineers: 

- Diagnose production incidents
- Detect security events
- Investigate application failures
- Monitor system behavior
- Identify performance issues

Mastering Linux log analysis significantly improves **incident response and system observability**. 

--- 

⭐ If you found this useful, consider **starring the repository**. 
