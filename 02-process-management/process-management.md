# Linux Process Management — Production Reference Guide

> Comprehensive reference for process lifecycle, signals, job control, resource limits, systemd, priority tuning, daemon patterns, and process observability on production Linux servers.

---

![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)


## Table of Contents

1. [Process Lifecycle and States](#1-process-lifecycle-and-states)
2. [Viewing and Inspecting Processes](#2-viewing-and-inspecting-processes)
3. [Signals — Communicating with Processes](#3-signals--communicating-with-processes)
4. [Job Control — Foreground and Background](#4-job-control--foreground-and-background)
5. [Process Priority — nice and ionice](#5-process-priority--nice-and-ionice)
6. [Resource Limits — ulimit and limits.conf](#6-resource-limits--ulimit-and-limitsconf)
7. [systemd — Service Management](#7-systemd--service-management)
8. [Daemon Patterns](#8-daemon-patterns)
9. [Zombie and Orphan Processes](#9-zombie-and-orphan-processes)
10. [Process Profiling — strace, lsof, /proc](#10-process-profiling--strace-lsof-proc)
11. [cgroups — Resource Control Groups](#11-cgroups--resource-control-groups)
12. [Production Process Runbook](#12-production-process-runbook)

---

## 1. Process Lifecycle and States

### Process States

Every Linux process is always in one of these states:

| State | Code | Meaning |
|---|---|---|
| Running | `R` | Actively executing on CPU or in run queue |
| Sleeping (interruptible) | `S` | Waiting for event (I/O, signal, timer) — most processes |
| Sleeping (uninterruptible) | `D` | Waiting for I/O — cannot be killed; usually brief |
| Stopped | `T` | Paused by `Ctrl+Z` or `SIGSTOP` |
| Zombie | `Z` | Exited but parent hasn't called `wait()` — entry stays in process table |
| Dead | `X` | Process is being removed — almost never seen |

```bash
# View process states
ps aux | awk '{print $8, $11}' | sort | head -20

# Count by state
ps aux | awk '{print $8}' | sort | uniq -c

# Find uninterruptible processes (potential I/O hang)
ps aux | awk '$8=="D" {print $0}'

# Find all zombie processes
ps aux | awk '$8=="Z" {print "Zombie:", $2, $11}'
```

### Process Identifiers

```bash
# Key identifiers
$$          # Current shell PID
$!          # Last background process PID
$PPID       # Parent PID of current shell

# Show PID, PPID, session, group for all processes
ps -eo pid,ppid,sid,pgid,comm | head -20

# Process hierarchy — who spawned what
pstree -p -a
pstree -p $(pgrep nginx | head -1)    # Tree for nginx
```

### fork() and exec() — How Processes Are Created

```bash
# Every process is created by forking its parent
# The shell forks a child, which calls exec() to load the program

# See this in action with strace
strace -e trace=fork,clone,execve bash -c "ls /tmp" 2>&1 | head -20

# Process genealogy — trace parent chain
CHILD_PID=1234
while [ "$CHILD_PID" -gt 1 ]; do
  PPID=$(awk '/^PPid:/ {print $2}' /proc/$CHILD_PID/status 2>/dev/null)
  NAME=$(cat /proc/$CHILD_PID/comm 2>/dev/null)
  echo "PID $CHILD_PID → $NAME"
  CHILD_PID=$PPID
done
```

---

## 2. Viewing and Inspecting Processes

### ps — Process Snapshot

```bash
# All processes, all users — BSD style (most common)
ps aux

# All processes — UNIX style (more fields available)
ps -ef

# Custom output format — most useful in production
ps -eo pid,ppid,user,stat,%cpu,%mem,vsz,rss,comm,args --sort=-%cpu | head -20

# Fields reference:
# pid    → process ID
# ppid   → parent process ID
# user   → owner
# stat   → process state (R/S/D/T/Z)
# %cpu   → CPU usage percentage
# %mem   → memory percentage
# vsz    → virtual memory size (KB)
# rss    → resident set size (actual RAM used, KB)
# comm   → command name (truncated)
# args   → full command with arguments

# Sort by memory
ps aux --sort=-%mem | head -15

# Filter by user
ps -u www-data
ps --user appuser -o pid,stat,%cpu,%mem,comm

# Show all threads of a process
ps -eLf | grep nginx
ps -p $(pgrep nginx | head -1) -L -o pid,tid,stat,%cpu,comm

# Process start time and run duration
ps -eo pid,comm,lstart,etime | grep nginx
```

### pgrep and pidof

```bash
# Find PIDs by name
pgrep nginx
pgrep -l nginx           # With process names
pgrep -la nginx          # With full command line
pgrep -u appuser         # Processes owned by user
pgrep -P 1234            # Children of PID 1234
pgrep -x nginx           # Exact name match

# Find PID of a named daemon
pidof nginx
pidof -x script.sh       # Include shell scripts

# Count processes matching name
pgrep -c nginx

# Test if process is running (exit 0 = found)
pgrep -x nginx &>/dev/null && echo "nginx is up" || echo "nginx is down"
```

### top — Interactive Monitor

```bash
top

# Non-interactive batch mode (great for scripts)
top -bn1 | head -25
top -bn1 -u nginx            # Filter by user
top -bn3 -d1 | grep nginx    # 3 samples, 1s interval

# Key interactive commands:
# P → sort by CPU (default)
# M → sort by memory
# T → sort by time
# k → kill process (enter PID then signal)
# r → renice (change priority)
# 1 → toggle per-core CPU view
# H → toggle threads
# u → filter by user
# c → toggle full command line
# V → tree view
# W → save config to ~/.toprc
# q → quit

# Useful top fields to add (press f in top):
# nTH → number of threads
# P   → last used CPU
# SWAP → swap usage
```

### htop / btop — Enhanced Monitors

```bash
# Install
sudo apt install htop btop    # Debian/Ubuntu
sudo yum install htop         # RHEL/CentOS

htop
# F2 → Setup (columns, colours, meters)
# F3 → Search by name
# F4 → Filter (regex)
# F5 → Tree view
# F6 → Sort column
# F7/F8 → Change nice value (priority)
# F9 → Send signal (kill menu)
# Space → Tag process for bulk action

btop    # Modern ncurses monitor — CPU, memory, disk, network
```

### Watching Processes Over Time

```bash
# Refresh process list every 2 seconds
watch -n2 'ps aux --sort=-%cpu | head -15'

# Watch a specific process
watch -n1 'ps -p $(pgrep myapp) -o pid,stat,%cpu,%mem,vsz,rss,etime'

# Track process CPU over time (pidstat — requires sysstat)
pidstat -p $(pgrep myapp) 1 60     # Every 1s for 60 seconds
pidstat -C nginx 1                  # All nginx processes, every 1s

# Track per-thread CPU
pidstat -t -p $(pgrep java | head -1) 2
```

---

## 3. Signals — Communicating with Processes

### Signal Reference

| Signal | Number | Meaning | Catchable? | Production Use |
|---|---|---|---|---|
| `SIGHUP` | 1 | Hangup / reload | Yes | Reload config without restart |
| `SIGINT` | 2 | Interrupt (Ctrl+C) | Yes | Stop interactive process |
| `SIGQUIT` | 3 | Quit + core dump | Yes | Debug: get stack trace |
| `SIGKILL` | 9 | Force kill | **No** | Last resort — use SIGTERM first |
| `SIGTERM` | 15 | Terminate gracefully | Yes | Standard graceful shutdown |
| `SIGUSR1` | 10 | User-defined 1 | Yes | App-specific (e.g., reopen logs) |
| `SIGUSR2` | 12 | User-defined 2 | Yes | App-specific action |
| `SIGSTOP` | 19 | Pause (uncatchable) | **No** | Pause a process (resume with SIGCONT) |
| `SIGCONT` | 18 | Continue | Yes | Resume a stopped process |
| `SIGCHLD` | 17 | Child state changed | Yes | Parent notified when child exits |

### Sending Signals

```bash
# By PID
kill -15 1234           # SIGTERM to PID 1234
kill -9 1234            # SIGKILL to PID 1234
kill -HUP 1234          # SIGHUP — reload config
kill -USR1 1234         # SIGUSR1

# By name
pkill nginx             # SIGTERM to all processes named nginx
pkill -9 nginx          # SIGKILL to all nginx
pkill -HUP nginx        # SIGHUP to all nginx
pkill -USR1 nginx       # Log rotation signal

# By user
pkill -u appuser        # Kill all processes of appuser (careful!)

# killall — kill by exact name
killall nginx           # SIGTERM
killall -9 nginx        # SIGKILL
killall -HUP nginx      # Reload

# Signal a process group (all children too)
kill -15 -1234          # Negative PID = process group
kill -- -$(pgrep -s $(pgrep -P $$))   # Kill process group of background job
```

### Safe Graceful Shutdown Pattern

```bash
#!/bin/bash
# Production-safe process termination

graceful_stop() {
  local pid="$1"
  local name="${2:-process}"
  local timeout="${3:-30}"

  echo "Stopping ${name} (PID: ${pid})..."

  # Step 1: Try SIGTERM (graceful)
  kill -15 "$pid" 2>/dev/null || { echo "${name} already stopped"; return 0; }

  # Step 2: Wait up to timeout seconds
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null && (( elapsed < timeout )); do
    sleep 1
    elapsed=$((elapsed + 1))
    echo "  Waiting... ${elapsed}s"
  done

  # Step 3: If still alive, SIGKILL
  if kill -0 "$pid" 2>/dev/null; then
    echo "  SIGTERM ignored after ${timeout}s — sending SIGKILL"
    kill -9 "$pid" 2>/dev/null || true
    sleep 1
  fi

  kill -0 "$pid" 2>/dev/null && echo "  Failed to stop ${name}" || echo "  ${name} stopped."
}

graceful_stop $(pgrep myapp) "myapp" 30
```

### Signal Handling in Applications

```bash
# Python: trap SIGTERM for graceful shutdown
python3 - <<'EOF'
import signal, sys, time

def shutdown(signum, frame):
    print(f"Received signal {signum} — shutting down...")
    # cleanup code here
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGHUP,  lambda s,f: print("Reloading config..."))

print(f"Running as PID {os.getpid()}")
while True:
    time.sleep(1)
EOF

# Bash: trap signals in shell scripts
trap 'echo "SIGTERM received"; cleanup; exit 0' SIGTERM SIGINT
trap 'echo "Reloading config"; load_config' SIGHUP
```

---

## 4. Job Control — Foreground and Background

### Basic Job Control

```bash
# Run in background
long-running-command &

# Suspend foreground job (Ctrl+Z sends SIGSTOP)
Ctrl+Z

# List all jobs in current shell
jobs -l

# Resume suspended job in background
bg %1       # Job number 1
bg          # Most recent suspended job

# Bring background job to foreground
fg %1
fg %2       # Job number 2

# Kill a job by number
kill %1

# Get exit status of last background job
wait %1; echo "Exit: $?"
```

### nohup — Survive Terminal Close

```bash
# Run command that persists after logout
nohup ./long-script.sh > /var/log/script.log 2>&1 &
echo "PID: $!"

# nohup with environment preserved
nohup env -i HOME=$HOME PATH=$PATH bash -c './script.sh' > /tmp/out.log 2>&1 &

# Without nohup — disown after starting
./script.sh &
disown -h %1    # Remove from job table, keep running

# disown all background jobs
disown -a
```

### screen and tmux — Persistent Sessions

```bash
# screen — classic multiplexer
screen -S mysession          # New named session
screen -ls                   # List sessions
screen -r mysession          # Reattach
Ctrl+A, D                    # Detach (session keeps running)
Ctrl+A, K                    # Kill current window

# tmux — modern multiplexer (preferred)
tmux new-session -s deploy    # New named session
tmux ls                       # List sessions
tmux attach -t deploy         # Reattach
Ctrl+B, D                     # Detach
tmux kill-session -t deploy   # Kill session

# Run a command in a new tmux session (non-interactive)
tmux new-session -d -s backup -c /opt/app \
  'bash /opt/scripts/backup.sh > /var/log/backup.log 2>&1'
```

---

## 5. Process Priority — nice and ionice

### CPU Priority with nice

```bash
# nice values range: -20 (highest priority) to +19 (lowest priority)
# Default is 0. Only root can set negative values.

# Start a process with lower priority (background work)
nice -n 10 ./backup.sh
nice -n 19 ./low-priority-task.sh     # Lowest CPU priority

# Start with high priority (requires root)
sudo nice -n -10 ./critical-service.sh

# Change priority of a running process
renice +10 -p 1234                     # Lower priority
renice -5 -p 1234                      # Higher priority (root required)
renice +15 -u appuser                  # All processes of a user
renice +10 -g 1001                     # All processes of a group

# View nice values
ps -eo pid,ni,comm | grep myapp
top     # NI column shows nice value

# Automated: lower priority if CPU exceeds threshold
for pid in $(pgrep backup); do
  CPU=$(ps -p "$pid" -o %cpu --no-headers)
  if (( $(echo "$CPU > 50" | bc -l) )); then
    renice +15 -p "$pid"
    echo "Reniced PID $pid (was using ${CPU}% CPU)"
  fi
done
```

### I/O Priority with ionice

```bash
# I/O scheduling classes:
# 0 → none (inherits from process priority)
# 1 → real-time (highest, requires root)
# 2 → best-effort (default, 0-7 within class)
# 3 → idle (only when disk is idle — backup/archiving)

# Run backup with idle I/O priority (won't compete with app)
ionice -c 3 ./backup.sh

# Start app with real-time I/O (requires root — use sparingly)
sudo ionice -c 1 -n 0 ./database-startup.sh

# Change running process I/O priority
ionice -c 3 -p 1234              # Set to idle
ionice -c 2 -n 7 -p 1234        # Best-effort, lowest level

# Combine nice + ionice for batch jobs
nice -n 19 ionice -c 3 ./large-backup.sh &

# View current I/O class of a process
ionice -p 1234
```

---

## 6. Resource Limits — ulimit and limits.conf

### ulimit — Per-Session Limits

```bash
# View all current limits
ulimit -a

# Common limits
ulimit -n 65536      # Open file descriptors (nofile) — most critical
ulimit -u 4096       # Max user processes (nproc)
ulimit -s 8192       # Stack size in KB
ulimit -v unlimited  # Virtual memory (address space)
ulimit -c unlimited  # Core dump size (unlimited = enable core dumps)
ulimit -t unlimited  # CPU time in seconds

# Soft vs hard limits
ulimit -Sn 65536     # Set soft limit
ulimit -Hn 131072    # Set hard limit (root only beyond current hard)

# Apply before starting a service
ulimit -n 65536
./myapp &

# Set limits in a startup script
cat > /etc/profile.d/production-limits.sh << 'EOF'
ulimit -n 65536
ulimit -u 4096
EOF
```

### /etc/security/limits.conf — Persistent Limits

```bash
# /etc/security/limits.conf
# Format: <domain> <type> <item> <value>
# domain: username, @group, * (all users), root
# type:   soft (warning) or hard (maximum soft can reach)
# item:   nofile, nproc, stack, core, memlock, ...
```

```ini
# /etc/security/limits.conf — Production settings

# ── Web server (nginx/apache) ────────────────────────────────────────────────
www-data        soft    nofile      65535
www-data        hard    nofile      131070
www-data        soft    nproc       4096
www-data        hard    nproc       8192

# ── Application service account ─────────────────────────────────────────────
appuser         soft    nofile      65535
appuser         hard    nofile      131070
appuser         soft    nproc       8192
appuser         hard    nproc       16384
appuser         soft    stack       65536
appuser         hard    stack       65536

# ── Database (PostgreSQL / MySQL) ────────────────────────────────────────────
postgres        soft    nofile      65535
postgres        hard    nofile      131070
postgres        soft    nproc       16384
postgres        hard    nproc       32768
postgres        soft    memlock     unlimited
postgres        hard    memlock     unlimited

# ── All users ────────────────────────────────────────────────────────────────
*               soft    nofile      65535
*               hard    nofile      131070
*               soft    nproc       4096
*               hard    nproc       8192
*               soft    core        0           # Disable core dumps for users
```

```bash
# Apply: restart PAM session or re-login
# Verify limits for a process
cat /proc/$(pgrep nginx | head -1)/limits

# Check current limits for a running service
cat /proc/$(systemctl show nginx --property=MainPID --value)/limits
```

### systemd Resource Limits in Service Units

```ini
# /etc/systemd/system/myapp.service
[Service]
# File descriptor limit
LimitNOFILE=65536

# Process limit
LimitNPROC=4096

# Core dump (0 = disabled, infinity = unlimited)
LimitCORE=0

# Memory limit via cgroup (hard stop — process gets OOM killed)
MemoryMax=2G
MemorySwapMax=0          # Disable swap for this service

# CPU quota (50% = half a core, 200% = 2 full cores)
CPUQuota=200%

# I/O weight (100 is default, lower = less I/O priority)
IOWeight=50
```

---

## 7. systemd — Service Management

### Essential systemctl Commands

```bash
# Service lifecycle
sudo systemctl start myapp
sudo systemctl stop myapp
sudo systemctl restart myapp        # Stop + start (brief downtime)
sudo systemctl reload myapp         # Send SIGHUP — reload config, no downtime
sudo systemctl try-reload-or-restart myapp  # Reload if supported, else restart

# Boot behaviour
sudo systemctl enable myapp         # Enable start on boot
sudo systemctl disable myapp        # Disable start on boot
sudo systemctl mask myapp           # Prevent starting (even manually)
sudo systemctl unmask myapp

# Inspection
systemctl status myapp              # Status, recent logs, PID, memory
systemctl is-active myapp           # active/inactive/failed
systemctl is-enabled myapp          # enabled/disabled
systemctl is-failed myapp           # Exit 0 if failed
systemctl show myapp                # All service properties (machine-readable)
systemctl show myapp --property=MainPID,ActiveState,MemoryCurrent

# List units
systemctl list-units --type=service              # All active services
systemctl list-units --type=service --state=failed  # Failed only
systemctl list-units --type=service --all        # All including inactive
systemctl list-unit-files --type=service         # All unit files

# Reload systemd (after editing unit files)
sudo systemctl daemon-reload
```

### journalctl — Service Log Management

```bash
# Follow live logs for a service
journalctl -u myapp -f

# Last 100 lines
journalctl -u myapp -n 100 --no-pager

# Since a time
journalctl -u myapp --since "2024-01-15 09:00"
journalctl -u myapp --since "1 hour ago"

# Priority filter
journalctl -u myapp -p err          # Errors only
journalctl -u myapp -p warning      # Warnings and above
journalctl -p 0..3 --since today    # Emergency through error, today

# Multiple units
journalctl -u nginx -u myapp --since today

# All logs since last boot
journalctl -b

# Kernel messages
journalctl -k

# Export format
journalctl -u myapp --output=json | jq .

# Disk usage
journalctl --disk-usage

# Clean old logs
sudo journalctl --vacuum-time=30d
sudo journalctl --vacuum-size=500M
```

### Writing Production systemd Unit Files

```ini
# /etc/systemd/system/myapp.service
# Production-hardened service unit

[Unit]
Description=My Production Application
Documentation=https://docs.example.com/myapp
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service     # Fail if postgres not running

[Service]
# ── Identity ─────────────────────────────────────────────────────────────────
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp

# ── Process ──────────────────────────────────────────────────────────────────
Type=simple                         # simple|forking|notify|oneshot|idle
ExecStart=/opt/myapp/bin/myapp \
    --config /opt/myapp/conf/app.yaml \
    --log-level info
ExecReload=/bin/kill -HUP $MAINPID  # Reload config on 'systemctl reload'
ExecStop=/bin/kill -TERM $MAINPID   # Custom stop signal

# ── Restart Policy ───────────────────────────────────────────────────────────
Restart=on-failure                  # Restart if exits non-zero or signal
RestartSec=5s                       # Wait 5 seconds before restarting
StartLimitIntervalSec=60s           # Within 60-second window...
StartLimitBurst=5                   # ...allow max 5 restarts

# ── Logging ──────────────────────────────────────────────────────────────────
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp

# ── Environment ──────────────────────────────────────────────────────────────
EnvironmentFile=-/etc/myapp/env     # Load env file (- = ignore if missing)
Environment=APP_ENV=production
Environment=LOG_LEVEL=info

# ── Resource Limits ──────────────────────────────────────────────────────────
LimitNOFILE=65536
LimitNPROC=4096
LimitCORE=0
MemoryMax=2G
MemorySwapMax=0
CPUQuota=200%

# ── Security Hardening ───────────────────────────────────────────────────────
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadWritePaths=/opt/myapp/data /opt/myapp/logs
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallFilter=@system-service
ProtectKernelTunables=yes
ProtectControlGroups=yes

# ── OOM Killer Protection ─────────────────────────────────────────────────────
OOMScoreAdjust=-500                 # Less likely to be OOM killed (-1000 = never)

# ── Timeouts ─────────────────────────────────────────────────────────────────
TimeoutStartSec=30                  # Fail if not started in 30s
TimeoutStopSec=30                   # Force SIGKILL after 30s if not stopped

[Install]
WantedBy=multi-user.target
```

```bash
# After creating/editing unit file
sudo systemctl daemon-reload
sudo systemctl enable --now myapp

# Check it started correctly
systemctl status myapp
journalctl -u myapp --since "1 minute ago"
```

### systemd Service Types

```ini
# Type=simple (default)
# ExecStart process IS the main process. systemd considers the service
# started immediately. Use for most apps.

# Type=forking
# ExecStart forks to background and the parent exits. systemd tracks the
# child. Requires PIDFile= to identify the main process.
Type=forking
PIDFile=/var/run/myapp.pid

# Type=notify
# Process sends systemd notification when ready via sd_notify().
# Enables proper dependency ordering (Requires=, After=).
Type=notify

# Type=oneshot
# For scripts that run to completion (backup jobs, init tasks).
# systemd waits for ExecStart to exit before considering "active".
Type=oneshot
RemainAfterExit=yes       # Stay "active" after script finishes
```

---

## 8. Daemon Patterns

### Pattern 1: systemd Unit (Recommended)

```bash
# Always prefer systemd for production daemons.
# See Section 7 for full unit file template.

sudo systemctl start myapp
journalctl -u myapp -f
```

### Pattern 2: Supervisord (Non-systemd Environments)

```ini
# /etc/supervisor/conf.d/myapp.conf
[program:myapp]
command=/opt/myapp/bin/myapp --config /opt/myapp/conf/app.yaml
directory=/opt/myapp
user=myapp
autostart=true
autorestart=true
startretries=3
startsecs=5
stopwaitsecs=30
stopasgroup=true
killasgroup=true
stdout_logfile=/opt/myapp/logs/app.stdout.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=5
stderr_logfile=/opt/myapp/logs/app.stderr.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=5
environment=APP_ENV="production",LOG_LEVEL="info"
```

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start myapp
sudo supervisorctl status
sudo supervisorctl tail -f myapp stdout
```

### Pattern 3: Double Fork (Legacy Daemons)

```bash
#!/bin/bash
# Double-fork to fully detach from terminal
# This is what old-school daemons do. Use systemd instead.

double_fork() {
  local cmd="$1"
  local pidfile="$2"

  # First fork — exit parent so child becomes orphan adopted by init
  (
    # Second fork — create session, detach from terminal
    (
      setsid
      exec $cmd
    ) &
    echo $! > "$pidfile"
  ) &
}

double_fork "./myapp --config /etc/myapp.conf" /var/run/myapp.pid
```

### Pattern 4: Running Background Jobs Safely

```bash
# Bad: loses job if shell exits
./long-job.sh &

# Better: nohup + redirect output
nohup ./long-job.sh \
  > /var/log/long-job.log \
  2>&1 &
echo "PID: $!" | tee /var/run/long-job.pid

# Best for cron jobs: wrap in systemd-run
sudo systemd-run \
  --unit=one-off-backup \
  --description="Manual backup job" \
  --uid=backupuser \
  /opt/scripts/backup.sh

# Check status of systemd-run unit
systemctl status one-off-backup
journalctl -u one-off-backup
```

---

## 9. Zombie and Orphan Processes

### What Is a Zombie?

When a process exits, it becomes a zombie until its parent calls `wait()` to collect its exit status. Zombies take up a process table entry but consume no CPU or memory. A large number of zombies (> 10) indicates a bug in the parent process.

```bash
# Find zombies
ps aux | awk '$8=="Z"'
ps -eo pid,ppid,stat,comm | grep '^.*Z'

# Count zombies
ps aux | grep -c 'Z '

# Find the parent of zombies (must fix the parent, not the zombie)
ps -eo pid,ppid,stat,comm | awk '$3=="Z" {print "Zombie PID:", $1, "Parent PID:", $2}'

# Zombies go away when parent exits or is fixed
# You CANNOT kill a zombie — it's already dead
# Sending SIGCHLD to the parent may help
kill -CHLD $(ps -eo ppid,stat | awk '$2=="Z" {print $1}' | head -1)
```

### What Is an Orphan?

An orphan is a process whose parent has exited. Linux automatically re-parents orphans to PID 1 (systemd/init), which properly calls `wait()` on them.

```bash
# Find processes parented by PID 1 (potential orphans or daemons)
ps --ppid 1 -o pid,comm,stat,user

# Find processes in a zombie state with their parent
ps -eo pid,ppid,stat,comm | awk '$3 ~ /Z/ {print $0}'
```

### Preventing Zombies in Shell Scripts

```bash
#!/bin/bash
# Reap children properly in long-running scripts

# Option 1: wait for all children
pids=()
for i in {1..5}; do
  ./worker.sh $i &
  pids+=($!)
done

for pid in "${pids[@]}"; do
  wait "$pid"
  echo "Worker $pid exited: $?"
done

# Option 2: trap SIGCHLD to reap immediately
trap 'wait $!' SIGCHLD

# Option 3: Use 'wait' without arguments to reap all
wait
```

---

## 10. Process Profiling — strace, lsof, /proc

### strace — System Call Tracer

```bash
# Trace all system calls of a running process
sudo strace -p $(pgrep myapp | head -1)

# Summary of system calls (very useful for profiling)
sudo strace -p $(pgrep myapp | head -1) -c -f

# Trace only specific calls
sudo strace -p $(pgrep myapp | head -1) -e trace=read,write,open,close

# Trace file operations
sudo strace -p $(pgrep myapp | head -1) -e trace=file

# Trace network operations
sudo strace -p $(pgrep myapp | head -1) -e trace=network

# Trace and save to file
sudo strace -p $(pgrep myapp | head -1) -o /tmp/strace.out

# Trace a new command
strace -f ./myapp --config app.yaml 2>&1 | head -50

# Show timestamps
sudo strace -p $(pgrep myapp | head -1) -T -tt    # -T = time per call, -tt = wall time

# Most useful strace invocation for debugging slow processes:
sudo strace -p $(pgrep myapp | head -1) -c -f -e trace=!futex 2>&1 | head -30
```

### lsof — List Open Files

```bash
# All files opened by a process
sudo lsof -p $(pgrep nginx | head -1)

# All files opened by a user
sudo lsof -u appuser

# Who has a specific file open
sudo lsof /var/log/app.log

# All network connections
sudo lsof -i

# TCP connections on port 8080
sudo lsof -i TCP:8080

# Files opened by process name
sudo lsof -c nginx

# Count file descriptors per process
sudo lsof | awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Find deleted files still held open (disk not freed)
sudo lsof +L1 | grep deleted
# To free space: either kill the process or truncate the file
> /proc/$(sudo lsof +L1 | grep deleted | awk '{print $2}' | head -1)/fd/$(...)
```

### /proc Filesystem — Direct Kernel Data

```bash
# Process status — memory, threads, signals
cat /proc/1234/status

# Full command line (null-separated args)
cat /proc/1234/cmdline | tr '\0' ' '

# Environment variables of process
sudo cat /proc/1234/environ | tr '\0' '\n'

# Open file descriptors
ls -la /proc/1234/fd/

# Memory maps
cat /proc/1234/maps
sudo pmap -x 1234      # Formatted memory map with RSS per region

# CPU and scheduling info
cat /proc/1234/sched
cat /proc/1234/schedstat

# I/O statistics
sudo cat /proc/1234/io
# rchar: bytes read
# wchar: bytes written
# syscr: read syscall count
# syscw: write syscall count
# read_bytes: bytes actually read from storage
# write_bytes: bytes actually written to storage

# Limits
cat /proc/1234/limits

# Network connections (for this process/namespace)
cat /proc/1234/net/tcp

# Current working directory and executable
ls -la /proc/1234/cwd    # → /opt/myapp
ls -la /proc/1234/exe    # → /opt/myapp/bin/myapp
```

---

## 11. cgroups — Resource Control Groups

### cgroups v2 Overview

```bash
# Check cgroup version
ls /sys/fs/cgroup/cgroup.controllers   # v2 exists if this file exists
mount | grep cgroup

# View current cgroup hierarchy
systemd-cgls
systemd-cgtop              # Real-time resource usage per cgroup

# Resource usage per service
systemctl show myapp --property=MemoryCurrent,CPUUsageNSec,TasksCurrent
```

### Resource Control via systemd (Recommended)

```bash
# Set resource limits on a running service (temporary, lost on restart)
sudo systemctl set-property myapp MemoryMax=1G
sudo systemctl set-property myapp CPUQuota=50%
sudo systemctl set-property myapp TasksMax=200

# Set permanently (written to override file)
sudo systemctl set-property --runtime myapp MemoryMax=1G

# Create a drop-in override
sudo systemctl edit myapp
```

```ini
# Appears in /etc/systemd/system/myapp.service.d/override.conf
[Service]
MemoryMax=2G
MemorySwapMax=0
CPUQuota=200%
IOWeight=50
TasksMax=512
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart myapp

# Verify cgroup limits applied
cat /sys/fs/cgroup/system.slice/myapp.service/memory.max
cat /sys/fs/cgroup/system.slice/myapp.service/cpu.max
```

---

## 12. Production Process Runbook

### Incident: Process Consuming 100% CPU

```bash
# Step 1: Identify the process
top -bn1 | head -20
ps aux --sort=-%cpu | head -10

# Step 2: Get details on the offending process
PID=$(ps aux --sort=-%cpu | awk 'NR==2{print $2}')
ps -p $PID -o pid,ppid,user,stat,ni,%cpu,%mem,comm,args
cat /proc/$PID/cmdline | tr '\0' ' '
cat /proc/$PID/status

# Step 3: Identify what it's doing
sudo strace -p $PID -c -e trace=\!futex -f 2>&1 &
STRACE_PID=$!
sleep 10
kill $STRACE_PID

# Step 4: Temporary mitigation — reduce priority
renice +15 -p $PID
ionice -c 3 -p $PID

# Step 5: If runaway — graceful then force
kill -15 $PID; sleep 5; kill -0 $PID 2>/dev/null && kill -9 $PID

# Step 6: If it's a systemd service — restart it
sudo systemctl restart myapp
```

### Incident: Process Keeps Crashing (Restart Loop)

```bash
# Check how many times it has restarted
systemctl show myapp --property=NRestarts

# View recent failure logs
journalctl -u myapp -n 50 --no-pager
journalctl -u myapp -p err --since "1 hour ago"

# Check exit code of last run
systemctl show myapp --property=ExecMainStatus

# Check if OOM killed
sudo dmesg -T | grep -i 'killed process\|oom'
journalctl -k | grep -i oom | tail -10

# Temporarily increase restart limit
sudo systemctl edit myapp
# [Service]
# StartLimitBurst=10
# StartLimitIntervalSec=120

# Run manually to see full error output
sudo -u appuser /opt/myapp/bin/myapp --config /opt/myapp/conf/app.yaml
```

### Incident: Too Many Processes / Fork Bomb

```bash
# Check current process count
ps aux | wc -l
cat /proc/sys/kernel/pid_max

# Find who is spawning the most processes
ps aux | awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Limit processes for a user immediately
sudo -u appuser bash -c 'ulimit -u 200; exec bash'

# Kill all processes of a user (dangerous — also kills their login)
pkill -u appuser

# Set permanent process limit
echo "appuser hard nproc 200" | sudo tee -a /etc/security/limits.conf

# Enable systemd TasksMax for the service
sudo systemctl set-property myapp TasksMax=200
```

### Incident: Zombie Pile-up

```bash
# Count zombies
ps aux | grep -c 'Z '

# Identify zombies and their parents
ps -eo pid,ppid,stat,comm | awk '$3~/Z/'

# Attempt to trigger parent reap
PARENT=$(ps -eo pid,ppid,stat | awk '$3~/Z/ {print $2; exit}')
kill -CHLD $PARENT

# If parent is misbehaving — restart the parent service
PARENT_CMD=$(cat /proc/$PARENT/comm)
echo "Misbehaving parent: $PARENT_CMD (PID: $PARENT)"
sudo systemctl restart ${PARENT_CMD}.service 2>/dev/null || kill $PARENT
```

---

## Quick Reference Card

```
# Process inspection
ps aux                     All processes (all users)
ps -eo pid,%cpu,%mem,comm  Custom format, sorted by field
pgrep -la name             PIDs + names
pstree -p                  Process tree with PIDs
cat /proc/PID/status       Detailed process info

# Signals
kill -15 PID              SIGTERM — graceful stop
kill -9 PID               SIGKILL — force stop
kill -1 PID               SIGHUP  — reload config
kill -USR1 PID            SIGUSR1 — app-defined
pkill name                SIGTERM to all matching
killall -HUP name         SIGHUP to all matching

# Priority
nice -n 10 cmd            Start with low CPU priority
renice +10 -p PID         Lower running process priority
ionice -c 3 cmd           Idle I/O priority
ionice -c 3 -p PID        Change running process I/O

# systemd
systemctl status svc       Status + recent logs
systemctl restart svc      Restart (brief downtime)
systemctl reload svc       Reload config (no downtime)
systemctl --failed         List failed services
journalctl -u svc -f       Follow service logs
journalctl -u svc -p err   Error logs only

# Limits
ulimit -a                  Current session limits
ulimit -n 65536            Set FD limit
cat /proc/PID/limits       Limits for a running process
```

---

*References: `man ps`, `man kill`, `man nice`, `man ionice`, `man strace`, `man lsof`, `man systemctl`, `man journalctl`, `man systemd.service`, `man ulimit`, [systemd documentation](https://www.freedesktop.org/wiki/Software/systemd/)*

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 02-process-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
