# Linux System Monitoring — Production Reference Guide

> Comprehensive reference for monitoring CPU, memory, disk, network, processes, logs, and setting up a full observability stack on production Linux servers.

---

## Table of Contents

1. [The Monitoring Philosophy — USE Method](#1-the-monitoring-philosophy--use-method)
2. [CPU Monitoring](#2-cpu-monitoring)
3. [Memory Monitoring](#3-memory-monitoring)
4. [Disk and I/O Monitoring](#4-disk-and-io-monitoring)
5. [Network Monitoring](#5-network-monitoring)
6. [Process and Service Monitoring](#6-process-and-service-monitoring)
7. [Log Management and Analysis](#7-log-management-and-analysis)
8. [The /proc Filesystem — Direct Kernel Metrics](#8-the-proc-filesystem--direct-kernel-metrics)
9. [sysstat Tools — sar, iostat, mpstat, pidstat](#9-sysstat-tools--sar-iostat-mpstat-pidstat)
10. [Prometheus + Node Exporter + Grafana](#10-prometheus--node-exporter--grafana)
11. [Alerting and Automated Response](#11-alerting-and-automated-response)
12. [Production Monitoring Runbook](#12-production-monitoring-runbook)

---

## 1. The Monitoring Philosophy — USE Method

Before diving into tools, every metric you collect should answer one of these three questions for each resource (CPU, memory, disk, network):

| Letter | Question | Example |
|---|---|---|
| **U** tilisation | How busy is the resource? | CPU at 85% |
| **S** aturation | Is work queuing up? | Load avg > core count |
| **E** rrors | Are there error events? | Disk I/O errors, packet drops |

```bash
# Quick USE snapshot — run this on any server
echo "=== UTILISATION ==="
top -bn1 | grep -E 'Cpu|Mem|Swap'

echo "=== SATURATION (Load vs Cores) ==="
CORES=$(nproc)
LOAD=$(awk '{print $1}' /proc/loadavg)
echo "Cores: $CORES | 1-min Load: $LOAD"

echo "=== ERRORS ==="
dmesg -T --level=err,crit,alert,emerg | tail -20
journalctl -p err --since "1 hour ago" --no-pager | tail -20
```

---

## 2. CPU Monitoring

### Load Average Explained

```bash
uptime
# 14:32:10 up 42 days, 3:15, 2 users, load average: 1.20, 0.95, 0.88
#                                                     ↑1min  ↑5min  ↑15min

# Rule: load average / number of cores = saturation ratio
# Ratio < 1.0  → healthy
# Ratio 1.0    → fully utilised (no headroom)
# Ratio > 1.0  → saturated (queue building up — investigate)

CORES=$(nproc)
LOAD1=$(awk '{print $1}' /proc/loadavg)
echo "Load ratio (1min): $(echo "scale=2; $LOAD1 / $CORES" | bc)"
```

### top — Interactive Process Monitor

```bash
top

# Key interactive shortcuts:
# P  → sort by CPU
# M  → sort by memory
# k  → kill process (enter PID)
# r  → renice (change priority)
# 1  → toggle per-core CPU display
# H  → toggle thread view
# u  → filter by user
# q  → quit

# Non-interactive (batch mode for scripts)
top -bn1 | head -20
top -bn1 -u nginx         # Filter by user
```

### htop — Enhanced Interactive Monitor

```bash
# Install
sudo apt install htop       # Debian/Ubuntu
sudo yum install htop       # RHEL/CentOS

htop
# F2 → Setup (customise columns, colour scheme)
# F4 → Filter by process name
# F5 → Tree view (parent-child relationships)
# F6 → Sort column
# Space → Tag process for bulk action
# F9 → Kill tagged processes
```

### mpstat — Per-Core CPU Statistics

```bash
# Install sysstat
sudo apt install sysstat

# All cores, every 1 second, 5 samples
mpstat -P ALL 1 5

# Sample output:
# CPU  %usr  %sys  %iowait  %steal  %idle
# all  12.3   2.1      0.5     0.0   85.1
#   0  25.6   4.2      1.0     0.0   69.2
#   1   0.0   0.0      0.0     0.0  100.0

# Watch for:
# %iowait > 20%  → disk I/O bottleneck
# %steal  > 5%   → noisy neighbour on VM host
# %sys    > 20%  → kernel/syscall overhead
```

### pidstat — Per-Process CPU Over Time

```bash
# Monitor all processes every 2 seconds
pidstat -u 2

# Monitor specific PID
pidstat -p 1234 1 10

# Monitor threads of a process
pidstat -t -p $(pgrep nginx | head -1) 1 5
```

### sar — Historical CPU Data

```bash
# CPU usage today (collected by sysstat every 10 minutes)
sar -u

# CPU usage at specific time range
sar -u -s 09:00:00 -e 12:00:00

# CPU usage yesterday
sar -u -f /var/log/sysstat/sa$(date -d yesterday +%d)

# Context switches and interrupts (useful for identifying noisy processes)
sar -w 1 5
```

### Identify CPU-Hungry Processes

```bash
# Top 10 processes by CPU
ps aux --sort=-%cpu | head -11

# CPU usage grouped by user
ps aux --sort=-%cpu | awk 'NR>1 {cpu[$1]+=$3} END {for (u in cpu) print cpu[u], u}' | sort -rn

# Real-time CPU per process (refresh every second)
watch -n1 'ps aux --sort=-%cpu | head -15'

# strace — trace system calls of a slow process
sudo strace -p $(pgrep myapp) -c -f    # Summary of syscalls
sudo strace -p $(pgrep myapp) -e trace=file    # File operations only
```

---

## 3. Memory Monitoring

### free — Memory Overview

```bash
free -h
# Output:
#               total    used    free  shared  buff/cache  available
# Mem:          15Gi    4.2Gi   2.1Gi  312Mi      9.1Gi      10.7Gi
# Swap:          2Gi    0.0Ki   2Gi

# Key: "available" is what new processes can use (free + reclaimable cache)
# Alert if: available < 10-15% of total
# Alert if: swap used > 0 on high-performance servers

# One-liner: available memory percentage
awk '/MemAvailable/ {avail=$2} /MemTotal/ {total=$2} END {printf "Available: %.1f%%\n", avail/total*100}' /proc/meminfo
```

### vmstat — Virtual Memory Statistics

```bash
# Continuous stats every 1 second
vmstat 1

# Fields to watch:
# r   → runnable processes (saturation if consistently > nproc)
# b   → blocked processes (waiting for I/O)
# si  → swap in (KB/s) — non-zero means memory pressure
# so  → swap out (KB/s) — non-zero is a serious warning
# bi  → blocks read from disk
# bo  → blocks written to disk
# wa  → % CPU waiting for I/O
# us  → % user CPU
# sy  → % system/kernel CPU

# Memory summary
vmstat -s | head -20
```

### /proc/meminfo — Detailed Breakdown

```bash
cat /proc/meminfo

# Key fields:
# MemTotal       → total RAM
# MemFree        → truly free (not useful alone)
# MemAvailable   → realistic "free for new processes"
# Buffers        → kernel buffer cache (disk metadata)
# Cached         → page cache (file data) — can be reclaimed
# SwapCached     → swap data that was brought back to RAM
# Dirty          → memory waiting to be written to disk
# Writeback      → memory being written to disk right now
# HugePages_Total → huge pages configured
# HugePages_Free  → available huge pages

# Parse specific values
grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree|Dirty' /proc/meminfo
```

### OOM Killer — Find Why Processes Were Killed

```bash
# Check for OOM events
sudo dmesg -T | grep -i 'oom\|out of memory\|killed process'
sudo journalctl -k | grep -i 'oom\|killed process'

# Which process triggered OOM
sudo grep -i 'oom_kill\|Out of memory' /var/log/syslog | tail -20

# Current OOM score per process (higher = more likely to be killed)
for pid in $(ls /proc | grep '^[0-9]'); do
  oom=$(cat /proc/$pid/oom_score 2>/dev/null || echo 0)
  name=$(cat /proc/$pid/comm 2>/dev/null || echo unknown)
  echo "$oom $name $pid"
done | sort -rn | head -10

# Protect a critical process from OOM killer
echo -1000 | sudo tee /proc/$(pgrep postgres)/oom_score_adj
```

### Memory Usage by Process

```bash
# Top 10 by memory
ps aux --sort=-%mem | head -11

# smem — accurate memory (accounts for shared pages)
sudo apt install smem
smem -t -k -c pss,name --sort pss | tail -10

# /proc/<pid>/status — detailed memory per process
cat /proc/$(pgrep nginx | head -1)/status | grep -i 'vmrss\|vmsize\|vmswap'
```

---

## 4. Disk and I/O Monitoring

### df — Disk Space Usage

```bash
# Human-readable with filesystem type
df -hT

# Exclude tmpfs and other virtual filesystems
df -hT | grep -vE 'tmpfs|devtmpfs|udev'

# Alert if any filesystem > 80%
df -h | awk 'NR>1 && $5+0 > 80 {print "WARN:", $0}'

# Inode usage (can be full even if disk space is available)
df -i
df -i | awk 'NR>1 && $5+0 > 80 {print "INODE WARN:", $0}'
```

### du — Directory Size Analysis

```bash
# Top 10 largest directories in /var
du -sh /var/* 2>/dev/null | sort -rh | head -10

# Find large files > 100MB
sudo find / -size +100M -type f -not -path '/proc/*' 2>/dev/null \
  | xargs ls -lh | sort -k5 -rh | head -20

# Largest directories recursively (depth 2)
du -h --max-depth=2 /var | sort -rh | head -15

# Log directory sizes
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

# Find files older than 30 days that are larger than 50MB
sudo find /var/log -mtime +30 -size +50M -type f -ls
```

### iostat — Disk I/O Statistics

```bash
# Install: sudo apt install sysstat
iostat -xz 1

# Key columns:
# Device    → disk or partition
# r/s       → reads per second
# w/s       → writes per second
# rMB/s     → read throughput
# wMB/s     → write throughput
# await     → average I/O wait time (ms) — alert if > 20ms for HDDs, > 2ms for SSDs
# %util     → device utilisation — alert if > 80% sustained

# Extended stats, skip idle devices, 1-second interval
iostat -xz 1 5

# Historical I/O via sar
sar -d 1 5        # I/O per device
sar -b 1 5        # Overall I/O statistics
```

### iotop — I/O by Process

```bash
sudo iotop -o -d 2    # Show only processes doing I/O, 2s interval
sudo iotop -a         # Accumulated totals since start

# Non-interactive, 3 snapshots
sudo iotop -b -n 3 -d 1
```

### lsof — Open Files and File Handles

```bash
# Files opened by a specific process
sudo lsof -p $(pgrep nginx | head -1)

# Who has a specific file open
sudo lsof /var/log/nginx/access.log

# All open network connections
sudo lsof -i

# TCP connections to port 80
sudo lsof -i TCP:80

# Files opened by a user
sudo lsof -u appuser

# Find deleted files still held open (disk not freed yet)
sudo lsof +L1 | grep deleted

# Count open file descriptors per process
sudo lsof | awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# System-wide file descriptor limit
cat /proc/sys/fs/file-max
cat /proc/sys/fs/file-nr    # open, free, max
```

---

## 5. Network Monitoring

### ss — Socket Statistics (modern netstat)

```bash
# All listening TCP/UDP with process names
sudo ss -tulnp

# Established TCP connections
ss -tnp state established

# Connections to a specific port
ss -tnp dst :443

# Count connections by state
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn

# Connections from a specific IP
ss -tnp src 10.0.0.5

# Socket statistics summary
ss -s
```

### netstat — Traditional Network Stats

```bash
# Listening ports with process
sudo netstat -tulnp

# All TCP connections with state
netstat -tan

# Network interface statistics
netstat -i

# Routing table
netstat -rn

# Connection count by state (useful for detecting connection flooding)
netstat -an | awk '/^tcp/ {print $6}' | sort | uniq -c | sort -rn
```

### iftop — Bandwidth by Connection

```bash
sudo apt install iftop
sudo iftop -i eth0          # Monitor eth0
sudo iftop -i eth0 -n       # No DNS resolution (faster)
sudo iftop -i eth0 -P       # Show ports

# Interactive keys:
# n → toggle DNS resolution
# p → toggle port display
# s/d → source/destination totals
# 1/2/3 → sort by 2s/10s/40s average
```

### nethogs — Bandwidth by Process

```bash
sudo apt install nethogs
sudo nethogs eth0
sudo nethogs -d 5 eth0     # Refresh every 5 seconds

# Interactive keys:
# m → cycle between kb/s, kb, b
# r → sort by received
# s → sort by sent
```

### tcpdump — Packet Capture

```bash
# Capture all traffic on eth0
sudo tcpdump -i eth0 -n

# Capture HTTP traffic
sudo tcpdump -i eth0 -n port 80

# Capture and save to file (for Wireshark analysis)
sudo tcpdump -i eth0 -w /tmp/capture.pcap -n -s 0

# Filter by host
sudo tcpdump -i eth0 host 10.0.0.5

# HTTP request lines only
sudo tcpdump -i eth0 -A -s 0 port 80 | grep -E 'GET|POST|HTTP'

# High-level statistics (no payload)
sudo tcpdump -i eth0 -n -q | head -50
```

### Network Errors and Statistics

```bash
# Interface errors and drops
cat /proc/net/dev
ip -s link show eth0

# Dropped packets — alert if non-zero and growing
netstat -i | grep -v 'lo\|Iface'

# TCP retransmissions (high value = network congestion)
cat /proc/net/snmp | grep -E 'Tcp:|RetransSegs'
ss -s | grep retrans

# Connection tracking table (for firewall-heavy servers)
cat /proc/sys/net/netfilter/nf_conntrack_count   # current
cat /proc/sys/net/netfilter/nf_conntrack_max     # maximum
```

---

## 6. Process and Service Monitoring

### ps — Process Snapshot

```bash
# Full process list with all info
ps aux

# Process tree
ps axjf
pstree -p

# Find process by name
ps aux | grep nginx
pgrep -la nginx

# Processes by memory
ps aux --sort=-%mem | head -10

# Processes by CPU
ps aux --sort=-%cpu | head -10

# Long format with all columns
ps -eo pid,ppid,user,stat,pcpu,pmem,vsz,rss,comm,args --sort=-%cpu | head -20
```

### systemctl — Service Monitoring

```bash
# List all failed units (should be zero in production)
systemctl --failed

# Status of a service
systemctl status nginx

# Service start/stop/restart times
systemctl show nginx --property=ActiveEnterTimestamp
systemctl show nginx --property=ActiveExitTimestamp

# Services that took longest to start
systemd-analyze blame | head -20

# Full boot time breakdown
systemd-analyze
systemd-analyze critical-chain nginx.service

# Watch a service in real-time
watch -n2 'systemctl status nginx | head -20'

# List all active services with memory usage
systemctl list-units --type=service --state=active \
  | while read -r unit _; do
    pid=$(systemctl show "$unit" --property=MainPID --value 2>/dev/null)
    [[ "$pid" -gt 0 ]] 2>/dev/null && \
      mem=$(cat /proc/$pid/status 2>/dev/null | awk '/VmRSS/ {print $2, $3}')
    echo "$unit: $mem"
  done
```

### Zombie and Orphan Processes

```bash
# Find zombie processes (Z state)
ps aux | awk '$8=="Z" {print "Zombie:", $2, $11}'

# Find the parent of a zombie (must kill parent to clean up zombie)
ps -o ppid= -p <zombie_pid>

# Count zombies
ps aux | grep -c 'Z '

# Orphan processes (parent = init/systemd, PID 1)
ps --ppid 1 -o pid,comm,stat | grep -v 'S\|NAME'
```

### Monitoring with watch

```bash
# Watch system stats every 2 seconds
watch -n2 'cat /proc/loadavg && echo "" && free -h && echo "" && df -h | grep -v tmpfs'

# Watch specific service connections
watch -n2 'ss -tnp | grep nginx'

# Watch log file for errors
watch -n5 'sudo journalctl -u myapp --since "1 minute ago" | grep -E "ERROR|WARN|CRIT"'
```

---

## 7. Log Management and Analysis

### journalctl — systemd Journal

```bash
# Follow all logs in real-time
journalctl -f

# Follow specific service
journalctl -f -u nginx
journalctl -f -u myapp --output=short-iso

# Last 100 lines of a service
journalctl -u postgresql -n 100 --no-pager

# Logs since a time window
journalctl --since "2024-01-15 09:00:00" --until "2024-01-15 10:00:00"
journalctl --since "2 hours ago"
journalctl --since today

# Filter by priority
# 0=emerg 1=alert 2=crit 3=err 4=warning 5=notice 6=info 7=debug
journalctl -p err            # Errors and above
journalctl -p warning -u nginx
journalctl -p 0..3           # Emergency through error

# Kernel messages only
journalctl -k                # Same as dmesg
journalctl -k --since "1 hour ago"

# Show with full output (no truncation)
journalctl -u nginx -n 50 --no-pager -o verbose

# Disk space used by journal
journalctl --disk-usage

# Vacuum old logs
sudo journalctl --vacuum-time=30d    # Keep only last 30 days
sudo journalctl --vacuum-size=500M   # Keep only 500MB

# Make journal persistent across reboots
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
echo 'Storage=persistent' | sudo tee -a /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
```

### grep — Log Pattern Searching

```bash
# Find all errors in nginx logs
grep -i 'error\|crit\|alert\|emerg' /var/log/nginx/error.log | tail -50

# Count errors by type
grep -oP '(?<=\[)\w+(?=\])' /var/log/nginx/error.log | sort | uniq -c | sort -rn

# Find 5xx responses in access log
awk '$9 ~ /^5/ {print $0}' /var/log/nginx/access.log | tail -20

# Count requests per status code
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Top 10 client IPs by request count
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# Requests per minute
awk '{print $4}' /var/log/nginx/access.log \
  | cut -d: -f1-3 \
  | sort | uniq -c

# Failed SSH logins with source IPs
grep 'Failed password' /var/log/auth.log \
  | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -20
```

### logrotate — Log Rotation in Production

```bash
# Test logrotate config
sudo logrotate --debug /etc/logrotate.d/nginx

# Force rotation now (useful after config changes)
sudo logrotate --force /etc/logrotate.d/nginx

# View last rotation status
cat /var/lib/logrotate/status | grep nginx
```

```ini
# /etc/logrotate.d/myapp — Production logrotate config
/opt/myapp/logs/*.log {
    daily                   # Rotate daily
    missingok               # Don't error if log file is missing
    rotate 30               # Keep 30 days of logs
    compress                # gzip old logs
    delaycompress           # Compress previous rotation (not current)
    notifempty              # Don't rotate empty files
    create 0640 myapp myapp # New file permissions and ownership
    sharedscripts           # Run scripts once even if multiple logs match

    prerotate
        # Verify app is running before rotation
        systemctl is-active myapp || exit 1
    endscript

    postrotate
        # Signal app to reopen log file
        systemctl reload myapp 2>/dev/null || true
        # OR: kill -USR1 $(cat /var/run/myapp.pid) 2>/dev/null || true
    endscript
}
```

### Centralised Log Analysis Patterns

```bash
# Extract slow queries from MySQL slow log
grep -A2 'Query_time' /var/log/mysql/slow.log \
  | awk '/Query_time/ {time=$2} /^SELECT|^UPDATE|^DELETE|^INSERT/ {print time, $0}' \
  | sort -rn | head -10

# Parse Apache/Nginx combined log format
# 127.0.0.1 - frank [10/Oct/2024:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326

# Requests causing 5xx in last hour
awk -v d="$(date -d '1 hour ago' +'%d/%b/%Y:%H')" \
  '$4 > "["d && $9 ~ /^5/' /var/log/nginx/access.log

# Response time p99 (if response time in log format)
awk '{print $NF}' /var/log/nginx/access.log \
  | sort -n | awk 'BEGIN{c=0} {a[c++]=$1} END{print "p99:", a[int(c*0.99)]}'
```

---

## 8. The /proc Filesystem — Direct Kernel Metrics

```bash
# System uptime in seconds
cat /proc/uptime

# CPU info
cat /proc/cpuinfo | grep -E 'model name|cpu cores|processor' | sort -u

# Memory info
cat /proc/meminfo

# Load averages
cat /proc/loadavg
# 0.95 0.88 0.72 2/453 12847
# 1min 5min 15min running/total_threads last_pid

# Network interface statistics
cat /proc/net/dev

# Open file descriptors system-wide
cat /proc/sys/fs/file-nr
# open_fds  free_fds  max_fds

# TCP connection states
cat /proc/net/tcp | awk '{print $4}' | sort | uniq -c
# State codes: 01=ESTABLISHED 02=SYN_SENT 06=TIME_WAIT 0A=LISTEN

# Disk I/O statistics
cat /proc/diskstats

# Virtual memory parameters
cat /proc/sys/vm/swappiness           # 10 = prefer RAM, 60 = default
cat /proc/sys/vm/dirty_ratio          # % of RAM for dirty pages before writeback
cat /proc/sys/vm/overcommit_memory    # 0=heuristic 1=always 2=never

# Process-specific info
PID=$(pgrep nginx | head -1)
cat /proc/$PID/status            # Process status, memory, threads
cat /proc/$PID/cmdline | tr '\0' ' '  # Full command line
cat /proc/$PID/fd | wc -l       # Open file descriptors
cat /proc/$PID/net/tcp | wc -l  # TCP connections
ls -la /proc/$PID/fd/            # All open file descriptors
```

---

## 9. sysstat Tools — sar, iostat, mpstat, pidstat

### Setup sysstat Data Collection

```bash
# Install
sudo apt install sysstat    # Debian/Ubuntu
sudo yum install sysstat    # RHEL/CentOS

# Enable collection (every 10 minutes)
sudo systemctl enable --now sysstat

# Edit collection interval (change to 2 minutes for better granularity)
sudo vi /etc/cron.d/sysstat
# */2 * * * * root ...

# On newer systems using sysstat.service
sudo vi /etc/default/sysstat
# ENABLED="true"
```

### sar — System Activity Reporter

```bash
# Today's CPU summary
sar -u

# Memory usage over time
sar -r

# Swap usage
sar -S

# Disk I/O per device
sar -d -p         # -p = pretty device names

# Network traffic
sar -n DEV        # Network devices
sar -n EDEV       # Network errors
sar -n TCP        # TCP stats
sar -n SOCK       # Socket stats

# Load average history
sar -q

# All metrics for yesterday
sar -A -f /var/log/sysstat/sa$(date -d yesterday +%d)

# CPU last 7 days at 9AM
for i in $(seq 7 -1 1); do
  DATE=$(date -d "$i days ago" +%d)
  FILE="/var/log/sysstat/sa${DATE}"
  [[ -f "$FILE" ]] && echo "=== $(date -d "$i days ago" +%Y-%m-%d) ===" && \
    sar -u -s 09:00:00 -e 09:15:00 -f "$FILE"
done
```

---

## 10. Prometheus + Node Exporter + Grafana

### Node Exporter — Expose Linux Metrics

```bash
# Install Node Exporter
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
VER="1.7.0"
wget https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-${ARCH}.tar.gz
tar xzf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/
sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
```

```ini
# /etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes \
    --collector.diskstats \
    --web.listen-address=:9100 \
    --web.telemetry-path=/metrics

Restart=on-failure
RestartSec=5

NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# Verify metrics endpoint
curl -s http://localhost:9100/metrics | head -30
curl -s http://localhost:9100/metrics | grep node_cpu_seconds_total
```

### Prometheus — Scrape and Store Metrics

```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets:
          - 'prod-web-01:9100'
          - 'prod-web-02:9100'
          - 'prod-app-01:9100'
          - 'prod-db-01:9100'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):\d+'
        replacement: '${1}'

  - job_name: 'nginx'
    static_configs:
      - targets: ['prod-web-01:9113']   # nginx-prometheus-exporter

  - job_name: 'postgres'
    static_configs:
      - targets: ['prod-db-01:9187']    # postgres_exporter
```

### Key PromQL Queries

```promql
# CPU usage percentage (5-minute average)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage percentage by mountpoint
(1 - node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes) * 100

# Disk I/O utilisation
rate(node_disk_io_time_seconds_total[5m]) * 100

# Network receive throughput (MB/s)
rate(node_network_receive_bytes_total{device!~"lo"}[5m]) / 1024 / 1024

# Load average vs CPU cores
node_load1 / count without(cpu, mode)(node_cpu_seconds_total{mode="idle"})

# Failed systemd units
node_systemd_unit_state{state="failed"} == 1

# Open file descriptors ratio
node_filefd_allocated / node_filefd_maximum
```

### Grafana — Dashboard Setup

```bash
# Import community dashboards (save as JSON to /etc/grafana/dashboards/)
# Node Exporter Full:    Dashboard ID 1860
# Nginx:                 Dashboard ID 9614
# PostgreSQL:            Dashboard ID 9628
# Linux System Overview: Dashboard ID 7039

# Recommended panels for production dashboard:
# - CPU Usage (stacked: user/sys/iowait/steal)
# - Memory Usage (used/cached/available)
# - Disk Usage % per mountpoint
# - Network I/O (in/out bytes/s)
# - Load Average vs Core Count
# - Disk I/O utilisation %
# - Failed systemd services
# - Open file descriptors
# - TCP connection states
```

---

## 11. Alerting and Automated Response

### Prometheus Alert Rules

```yaml
# /etc/prometheus/rules/system-alerts.yml
groups:
  - name: system
    rules:

    - alert: HighCPUUsage
      expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High CPU on {{ $labels.instance }}"
        description: "CPU usage is {{ $value | humanize }}% for 5+ minutes."

    - alert: CriticalCPUUsage
      expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 95
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Critical CPU on {{ $labels.instance }}"
        description: "CPU usage is {{ $value | humanize }}% — immediate action required."

    - alert: HighMemoryUsage
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory on {{ $labels.instance }}"
        description: "Memory usage is {{ $value | humanize }}%."

    - alert: DiskSpaceWarning
      expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100 > 75
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Disk space warning on {{ $labels.instance }}:{{ $labels.mountpoint }}"
        description: "Disk is {{ $value | humanize }}% full."

    - alert: DiskSpaceCritical
      expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100 > 90
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Disk space critical on {{ $labels.instance }}:{{ $labels.mountpoint }}"
        description: "Disk is {{ $value | humanize }}% full — take action immediately."

    - alert: HighLoadAverage
      expr: node_load5 / count without(cpu,mode)(node_cpu_seconds_total{mode="idle"}) > 2
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High load average on {{ $labels.instance }}"
        description: "5-min load ratio is {{ $value | humanize }} (> 2x core count)."

    - alert: SwapUsage
      expr: (1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes) * 100 > 20
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Swap usage on {{ $labels.instance }}"
        description: "Swap is {{ $value | humanize }}% used — possible memory pressure."

    - alert: SystemdServiceFailed
      expr: node_systemd_unit_state{state="failed"} == 1
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Systemd unit failed: {{ $labels.name }} on {{ $labels.instance }}"
        description: "Service {{ $labels.name }} is in failed state."

    - alert: HighOpenFileDescriptors
      expr: node_filefd_allocated / node_filefd_maximum > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High file descriptor usage on {{ $labels.instance }}"
        description: "{{ $value | humanizePercentage }} of file descriptors are in use."
```

### Shell-Based Alerting

```bash
#!/bin/bash
# Simple threshold-based alerting via email/Slack webhook
# Add to cron: */5 * * * * /opt/scripts/check-thresholds.sh

SLACK_WEBHOOK="https://hooks.slack.com/services/XXX/YYY/ZZZ"
HOSTNAME=$(hostname -f)
ALERTS=()

send_slack() {
  local message="$1"
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "{\"text\":\":alert: *${HOSTNAME}*: ${message}\"}" > /dev/null
}

# CPU load check
CORES=$(nproc)
LOAD=$(awk '{print $1}' /proc/loadavg)
RATIO=$(echo "scale=2; $LOAD / $CORES" | bc)
if (( $(echo "$RATIO > 2.0" | bc -l) )); then
  ALERTS+=("CPU load ratio: ${RATIO} (load: ${LOAD}, cores: ${CORES})")
fi

# Memory check
MEM_AVAIL_PCT=$(awk '/MemAvailable/{a=$2} /MemTotal/{t=$2} END{printf "%.0f", a/t*100}' /proc/meminfo)
if (( MEM_AVAIL_PCT < 15 )); then
  ALERTS+=("Low memory: only ${MEM_AVAIL_PCT}% available")
fi

# Disk check
while IFS= read -r line; do
  PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
  MNT=$(echo "$line" | awk '{print $6}')
  if (( PCT > 85 )); then
    ALERTS+=("Disk ${MNT} is ${PCT}% full")
  fi
done < <(df -h | grep -vE 'tmpfs|devtmpfs|Filesystem')

# Failed services check
FAILED=$(systemctl --failed --plain --no-legend | awk '{print $1}' | tr '\n' ', ')
if [[ -n "$FAILED" ]]; then
  ALERTS+=("Failed services: ${FAILED}")
fi

# Send alerts
for alert in "${ALERTS[@]}"; do
  send_slack "$alert"
  logger -t system-monitor "ALERT: $alert"
done
```

---

## 12. Production Monitoring Runbook

### Incident: High CPU

```bash
# Step 1: Identify load
uptime && mpstat -P ALL 1 3

# Step 2: Top processes
ps aux --sort=-%cpu | head -15

# Step 3: Is it I/O wait?
iostat -xz 1 3   # Check %iowait

# Step 4: Profile the process
sudo strace -p <PID> -c -f -e trace=all   # syscall summary
sudo perf top -p <PID>                     # CPU hotspots (needs perf installed)

# Step 5: Check for runaway cron
ps aux | grep cron
journalctl -u cron --since "30 min ago"

# Resolution options:
# - renice process: sudo renice +10 <PID>
# - kill runaway:   sudo kill -15 <PID>
# - scale out:      add capacity via load balancer
```

### Incident: High Memory / OOM

```bash
# Step 1: Current state
free -h && vmstat 1 3

# Step 2: Top memory consumers
ps aux --sort=-%mem | head -10

# Step 3: Check for OOM events
sudo dmesg -T | grep -i 'oom\|killed'
sudo journalctl -k | grep -i 'oom'

# Step 4: Check swap
swapon -s
cat /proc/swaps

# Step 5: Per-process details
cat /proc/$(pgrep myapp)/status | grep -E 'VmRSS|VmSize|VmSwap'

# Resolution options:
# - Restart memory-leaking service: sudo systemctl restart myapp
# - Add swap:    sudo fallocate -l 4G /swapfile && mkswap /swapfile && swapon /swapfile
# - Tune limits: /etc/security/limits.conf or systemd MemoryMax=
```

### Incident: Disk Full

```bash
# Step 1: Which filesystem
df -hT | grep -vE 'tmpfs|devtmpfs'

# Step 2: Where is the space
du -sh /* 2>/dev/null | sort -rh | head -10
du -sh /var/* 2>/dev/null | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

# Step 3: Large files
sudo find / -size +500M -type f 2>/dev/null | xargs ls -lh

# Step 4: Deleted files still held open
sudo lsof +L1 | grep deleted

# Resolution options:
# - Clear old logs:       sudo journalctl --vacuum-size=500M
# - Force log rotation:   sudo logrotate --force /etc/logrotate.conf
# - Clear package cache:  sudo apt clean / sudo yum clean all
# - Remove old kernels:   sudo apt autoremove
# - Truncate log:         > /var/log/bigfile.log   (careful!)
```

### Daily Monitoring Checklist

```bash
#!/bin/bash
# Run daily: 0 8 * * * /opt/scripts/daily-check.sh | mail -s "Daily Health: $(hostname)" ops@company.com

echo "=== $(hostname) — $(date) ==="
echo ""
echo "--- Uptime & Load ---"
uptime
echo ""
echo "--- Memory ---"
free -h
echo ""
echo "--- Disk ---"
df -hT | grep -vE 'tmpfs|devtmpfs'
echo ""
echo "--- Failed Services ---"
systemctl --failed --plain --no-legend | head -10 || echo "None"
echo ""
echo "--- Recent Errors (last 24h) ---"
journalctl -p err --since "24 hours ago" --no-pager | tail -20
echo ""
echo "--- Top CPU Processes ---"
ps aux --sort=-%cpu | head -6
echo ""
echo "--- Top Memory Processes ---"
ps aux --sort=-%mem | head -6
echo ""
echo "--- Recent Login Activity ---"
last -10
```

---

## Quick Reference Card

```
# CPU
uptime                      Load average (1/5/15 min)
top / htop                  Interactive process monitor
mpstat -P ALL 1 5           Per-core CPU stats
pidstat -u 1                Per-process CPU
sar -u                      Historical CPU

# Memory
free -h                     Memory overview
vmstat 1 5                  VM stats (watch si/so for swap)
cat /proc/meminfo           Detailed memory info

# Disk
df -hT                      Disk usage by filesystem
du -sh /path/*              Directory sizes
iostat -xz 1                I/O stats per device
iotop -o                    Processes doing I/O
lsof +L1                    Deleted files still open

# Network
ss -tulnp                   Open ports + process
iftop -i eth0               Bandwidth by connection
nethogs eth0                Bandwidth by process
tcpdump -i eth0 port 80     Packet capture

# Logs
journalctl -f -u service    Follow service log
journalctl -p err           Error priority + above
grep -r 'ERROR' /var/log/   Search log files

# Process
ps aux --sort=-%cpu         Top processes by CPU
systemctl --failed          Failed systemd services
pgrep -la processname       Find process by name
```

---

*References: `man top`, `man iostat`, `man ss`, `man journalctl`, `man sar`, `man vmstat`, [Brendan Gregg's Linux Performance](https://www.brendangregg.com/linuxperf.html), [Prometheus Documentation](https://prometheus.io/docs/)*

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 07-system-monitoring
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
